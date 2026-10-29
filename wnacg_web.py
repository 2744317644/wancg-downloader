#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
wnacg 漫画下载器 · 本地 Web UI
==============================

启动后在浏览器里粘贴作品链接，实时查看 ZIP 下载 / PDF 生成进度。

    python wnacg_web.py
    python wnacg_web.py --port 8765 --no-browser
    python wnacg_web.py --output D:\\manga --proxy http://127.0.0.1:7890

只监听 127.0.0.1，不对外网开放。关闭控制台窗口或按 Ctrl+C 即停止服务。
"""

from __future__ import annotations

import json
import os
import queue
import re
import socket
import subprocess
import sys
import threading
import time
import traceback
import urllib.parse
import webbrowser
import argparse
from html import unescape
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Optional

import wnacg_dl as core

BASE_DIR = Path(__file__).resolve().parent
WEBUI_PATH = BASE_DIR / "webui.html"
MANIFEST_PATH = BASE_DIR / "manifest.webmanifest"
ICON_FILES = {
    "/icon-192.png": BASE_DIR / "icon-192.png",
    "/icon-512.png": BASE_DIR / "icon-512.png",
    "/apple-touch-icon.png": BASE_DIR / "apple-touch-icon.png",
}
DEFAULT_TIMEOUT = 60.0
DEFAULT_RETRIES = 4


# ---------------------------------------------------------------------------
# 任务
# ---------------------------------------------------------------------------

class Job:
    def __init__(
        self,
        url: str,
        make_pdf: bool,
        dpi: float,
        quality: int,
        overwrite: bool,
    ) -> None:
        self.id = f"{int(time.time() * 1000):x}{os.urandom(3).hex()}"
        self.url = url
        self.make_pdf = make_pdf
        self.dpi = dpi
        self.quality = quality
        self.overwrite = overwrite

        self.status = "queued"  # queued / running / done / skipped / error / cancelled
        self.phase = "queued"   # queued / resolving / downloading / pdf / done / error / cancelled
        self.title = ""
        self.filename = ""
        self.downloaded = 0
        self.total: Optional[int] = None
        self.pdf_page = 0
        self.pdf_total = 0
        self.zip_path: Optional[str] = None
        self.pdf_path: Optional[str] = None
        self.error = ""
        self.logs: list[str] = []
        self.created = time.time()
        self.updated = self.created
        self.zip_skipped = False
        self.pdf_skipped = False
        self.cancel_event = threading.Event()
        self._lock = threading.RLock()

    def log(self, message: object) -> None:
        text = str(message).strip()
        if not text:
            return
        stamp = time.strftime("%H:%M:%S")
        with self._lock:
            for line in text.splitlines():
                line = line.strip()
                if line:
                    self.logs.append(f"{stamp}  {line}")
            self.logs = self.logs[-200:]
            self.updated = time.time()

    def update_download(self, done: int, total: Optional[int]) -> None:
        with self._lock:
            self.downloaded = done
            self.total = total
            self.phase = "downloading"
            self.updated = time.time()

    def update_pdf(self, page: int, total: int) -> None:
        with self._lock:
            self.pdf_page = page
            self.pdf_total = total
            self.phase = "pdf"
            self.updated = time.time()

    def fail(self, message: str) -> None:
        with self._lock:
            self.status = "error"
            self.phase = "error"
            self.error = message
            self.updated = time.time()
        self.log(f"[失败] {message}")

    def cancel(self) -> None:
        self.cancel_event.set()
        with self._lock:
            if self.status == "queued":
                self.status = "cancelled"
                self.phase = "cancelled"
                self.updated = time.time()
        self.log("已请求取消")

    def mark_cancelled(self) -> None:
        with self._lock:
            if self.status == "cancelled":
                return
            self.status = "cancelled"
            self.phase = "cancelled"
            self.updated = time.time()
        self.log("任务已取消")

    def reset_for_retry(self) -> bool:
        with self._lock:
            if self.status not in ("error", "cancelled"):
                return False
            self.status = "queued"
            self.phase = "queued"
            self.error = ""
            self.downloaded = 0
            self.total = None
            self.pdf_page = 0
            self.pdf_total = 0
            self.zip_path = None
            self.pdf_path = None
            self.zip_skipped = False
            self.pdf_skipped = False
            self.cancel_event.clear()
            self.updated = time.time()
        self.log("重新加入下载队列（重试）")
        return True

    def percent(self) -> float:
        with self._lock:
            if self.status in ("done", "skipped"):
                return 100.0
            if self.phase == "downloading" and self.total:
                return max(0.0, min(99.5, self.downloaded * 100.0 / self.total))
            if self.phase == "pdf" and self.pdf_total:
                return max(0.0, min(99.5, self.pdf_page * 100.0 / self.pdf_total))
            return 0.0

    def snapshot(self) -> dict:
        with self._lock:
            files = {}
            for kind, path_text in (("zip", self.zip_path), ("pdf", self.pdf_path)):
                if not path_text:
                    continue
                path = Path(path_text)
                if path.is_file():
                    files[kind] = {
                        "url": f"/api/download?id={self.id}&kind={kind}",
                        "size": path.stat().st_size,
                        "name": path.name,
                    }
            return {
                "id": self.id,
                "url": self.url,
                "title": self.title,
                "filename": self.filename,
                "status": self.status,
                "phase": self.phase,
                "percent": round(self.percent(), 2),
                "downloaded": self.downloaded,
                "total": self.total,
                "pdf_page": self.pdf_page,
                "pdf_total": self.pdf_total,
                "zip_skipped": self.zip_skipped,
                "pdf_skipped": self.pdf_skipped,
                "cancel_requested": self.cancel_event.is_set(),
                "error": self.error,
                "logs": self.logs[-80:],
                "files": files,
                "make_pdf": self.make_pdf,
                "created": self.created,
                "updated": self.updated,
            }


class PreviewService:
    """抓取作品详情页，提取封面、标题、页数、标签等信息。"""

    def __init__(self, proxy: Optional[str], direct: bool = False) -> None:
        self.http = core.HttpClient(proxy=proxy, timeout=25, direct=direct)
        self.lock = threading.Lock()
        self.fetch_lock = threading.Lock()
        self.items: dict[str, tuple[float, dict]] = {}
        self.cover_urls: dict[str, tuple[float, str]] = {}
        self.cover_bytes: dict[str, tuple[float, bytes, str]] = {}
        self.ttl = 600.0

    def get(self, raw_url: str) -> dict:
        key = raw_url.strip()
        now = time.time()
        with self.lock:
            cached = self.items.get(key)
            if cached and cached[0] > now:
                return cached[1]

        with self.fetch_lock:
            target = core.resolve_target(key, self.http)
            html = self.http.get_text(target.gallery_url)
            data, cover_url = self._parse(html, target)
            now = time.time()
            with self.lock:
                self.items[key] = (now + self.ttl, data)
                if cover_url:
                    self.cover_urls[target.aid] = (now + self.ttl, cover_url)
                self._evict(now)
            return data

    def get_cover(self, aid: str) -> Optional[tuple[bytes, str]]:
        if not aid.isdigit():
            raise ValueError("bad aid")
        now = time.time()
        with self.lock:
            cached = self.cover_bytes.get(aid)
            if cached and cached[0] > now:
                return cached[1], cached[2]
            entry = self.cover_urls.get(aid)

        cover_url = entry[1] if entry and entry[0] > now else None
        if not cover_url:
            self.get(aid)
            with self.lock:
                entry = self.cover_urls.get(aid)
                cover_url = entry[1] if entry else None
        if not cover_url:
            return None

        referer = f"https://www.wnacg.com/photos-index-aid-{aid}.html"
        with self.fetch_lock:
            with self.http.open(
                cover_url,
                referer=referer,
                headers={"Accept": "image/avif,image/webp,image/*,*/*;q=0.8"},
                timeout=30,
            ) as response:
                data = response.read()
                content_type = response.headers.get_content_type() or "image/jpeg"
        with self.lock:
            self.cover_bytes[aid] = (time.time() + self.ttl, data, content_type)
            self._evict(time.time())
        return data, content_type

    def _evict(self, now: float) -> None:
        if len(self.items) > 100:
            self.items = {
                key: value for key, value in self.items.items()
                if value[0] > now
            }
        if len(self.cover_bytes) > 30:
            self.cover_bytes = {
                key: value for key, value in self.cover_bytes.items()
                if value[0] > now
            }

    @staticmethod
    def _clean(value: str) -> str:
        text = re.sub(r"<[^>]+>", " ", value)
        return unescape(re.sub(r"\s+", " ", text)).strip()

    def _parse(self, html: str, target: core.Target) -> tuple[dict, Optional[str]]:
        title_match = re.search(
            r'<div id="bodywrap" class="userwrap">\s*<h2>(.*?)</h2>',
            html, re.S | re.I,
        )
        title = self._clean(title_match.group(1)) if title_match else ""
        if not title:
            title = core.page_title(html) or ""

        cover_url = None
        thumb_match = re.search(
            r'<div class="asTBcell uwthumb">(.*?)</div>', html, re.S | re.I
        )
        if thumb_match:
            image_match = re.search(
                r'<img[^>]+src="([^"]+)"', thumb_match.group(1), re.I
            )
            if image_match:
                cover_url = normalize_image_url(image_match.group(1))

        labels: dict[str, str] = {}
        for label in re.findall(r"<label[^>]*>(.*?)</label>", html, re.S | re.I):
            text = self._clean(label)
            if "：" in text:
                key, value = text.split("：", 1)
                labels[key.strip()] = value.strip()
            elif ":" in text:
                key, value = text.split(":", 1)
                labels[key.strip()] = value.strip()

        pages = None
        pages_match = re.search(r"(\d+)\s*P", labels.get("頁數", ""), re.I)
        if pages_match:
            pages = int(pages_match.group(1))

        favorites = None
        if labels.get("收藏", "").isdigit():
            favorites = int(labels["收藏"])

        tags: list[str] = []
        tags_match = re.search(
            r'<div class="addtags">(.*?)</div>', html, re.S | re.I
        )
        if tags_match:
            for raw_tag in re.findall(
                r'<a class="tagshow"[^>]*>(.*?)</a>', tags_match.group(1), re.S | re.I
            ):
                tag = self._clean(raw_tag)
                if tag and tag not in tags:
                    tags.append(tag)

        uploader = ""
        uploader_match = re.search(
            r'<a href="/albums-user-uid-\d+\.html">.*?<p>(.*?)</p>',
            html, re.S | re.I,
        )
        if uploader_match:
            uploader = self._clean(uploader_match.group(1))

        uploaded = ""
        uploaded_match = re.search(r"上傳於\s*(\d{4}-\d{2}-\d{2})", html)
        if uploaded_match:
            uploaded = uploaded_match.group(1)

        data = {
            "aid": target.aid,
            "title": title,
            "category": labels.get("分類", ""),
            "pages": pages,
            "favorites": favorites,
            "uploader": uploader,
            "uploaded": uploaded,
            "tags": tags[:12],
            "tag_count": len(tags),
            "cover": f"/api/preview/cover?aid={target.aid}",
            "page_url": f"https://{target.host}/photos-index-aid-{target.aid}.html",
            "url": target.gallery_url,
        }
        return data, cover_url


def normalize_image_url(url: str) -> str:
    url = unescape(url).strip()
    if url.startswith("////"):
        return "https:" + url[2:]
    if url.startswith("//"):
        return "https:" + url
    if url.startswith("/"):
        return "https://www.wnacg.com" + url
    return url



class JobManager:
    def __init__(
        self, output_dir: Path, proxy: Optional[str], direct: bool = False
    ) -> None:
        self.output_dir = output_dir
        self.proxy = proxy
        self.direct = direct
        self.http = core.HttpClient(proxy=proxy, timeout=30, direct=direct)
        self.jobs: dict[str, Job] = {}
        self.order: list[str] = []
        self.lock = threading.Lock()
        self.queue: queue.Queue[Optional[Job]] = queue.Queue()
        self.worker = threading.Thread(target=self._worker_loop, daemon=True)
        self.worker.start()

    def submit(
        self,
        urls: list[str],
        make_pdf: bool,
        dpi: float,
        quality: int,
        overwrite: bool,
    ) -> list[Job]:
        new_jobs: list[Job] = []
        with self.lock:
            for url in urls:
                job = Job(url, make_pdf, dpi, quality, overwrite)
                self.jobs[job.id] = job
                self.order.append(job.id)
                new_jobs.append(job)
        for job in new_jobs:
            self.queue.put(job)
        return new_jobs

    def find(self, job_id: str) -> Optional[Job]:
        with self.lock:
            return self.jobs.get(job_id)

    def retry(self, job_id: str) -> Optional[bool]:
        with self.lock:
            job = self.jobs.get(job_id)
            if job is None:
                return None
            if not job.reset_for_retry():
                return False
            self.queue.put(job)
            return True

    def snapshot(self) -> list[dict]:
        with self.lock:
            jobs = [self.jobs[job_id] for job_id in self.order if job_id in self.jobs]
        return [job.snapshot() for job in jobs]

    def clear_finished(self) -> int:
        with self.lock:
            keep = [
                job_id for job_id in self.order
                if self.jobs[job_id].status in ("queued", "running")
            ]
            removed = len(self.order) - len(keep)
            for job_id in self.order:
                if job_id not in keep:
                    self.jobs.pop(job_id, None)
            self.order = keep
        return removed

    def stop(self) -> None:
        self.queue.put(None)

    def _worker_loop(self) -> None:
        while True:
            job = self.queue.get()
            if job is None:
                return
            if job.cancel_event.is_set():
                job.mark_cancelled()
                continue
            try:
                self._run(job)
            except core.CancelledError:
                job.mark_cancelled()
            except Exception as exc:  # 兜底，任务线程不能退出
                job.fail(f"{type(exc).__name__}: {exc}")
                traceback.print_exc()

    def _run(self, job: Job) -> None:
        with job._lock:
            job.status = "running"
            job.phase = "resolving"
        job.log("开始解析作品链接…")

        dest: Optional[Path] = None
        try:
            if job.cancel_event.is_set():
                raise core.CancelledError("已取消")
            target = core.resolve_target(job.url, self.http)
            album = core.fetch_album(self.http, target)

            with job._lock:
                job.title = album.title or ""
                job.filename = album.filename
            job.log(f"作品：{album.title or '（未获取到标题）'}")
            if job.cancel_event.is_set():
                raise core.CancelledError("已取消")

            dest = self.output_dir / album.filename
            if dest.exists() and not job.overwrite:
                valid, count = core.verify_zip(dest)
                if valid:
                    job.zip_skipped = True
                    job.zip_path = str(dest)
                    with job._lock:
                        job.total = dest.stat().st_size
                    job.log(f"ZIP 已存在且校验通过（{count} 个文件），跳过下载")

            if not job.zip_skipped:
                if job.cancel_event.is_set():
                    raise core.CancelledError("已取消")
                size, status = core.probe_size(
                    self.http, album.zip_url or "", album.page_url
                )
                if size:
                    with job._lock:
                        job.total = size
                if core.is_dead_status(status):
                    album = core.switch_to_worker(
                        self.http, album, status, log=job.log
                    )
                job.phase = "downloading"
                job.log("开始下载 ZIP…")
                try:
                    core.download_zip(
                        self.http, album, dest,
                        retries=DEFAULT_RETRIES,
                        timeout=DEFAULT_TIMEOUT,
                        cancel_event=job.cancel_event,
                        on_progress=job.update_download,
                        log=job.log,
                    )
                except core.LinkDeadError as exc:
                    job.log(str(exc))
                    album = core.switch_to_worker(self.http, album, log=job.log)
                    core.download_zip(
                        self.http, album, dest,
                        retries=DEFAULT_RETRIES,
                        timeout=DEFAULT_TIMEOUT,
                        cancel_event=job.cancel_event,
                        on_progress=job.update_download,
                        log=job.log,
                    )
                size = dest.stat().st_size
                job.update_download(size, size)
                job.zip_path = str(dest)
                job.log(f"ZIP 完成：{core.human_size(size)}")

            if job.make_pdf:
                if job.cancel_event.is_set():
                    raise core.CancelledError("已取消")
                pdf_path = dest.with_suffix(".pdf")
                if (
                    pdf_path.exists()
                    and not job.overwrite
                    and core.verify_pdf(pdf_path)
                ):
                    job.pdf_skipped = True
                    job.pdf_path = str(pdf_path)
                    job.log("PDF 已存在，跳过生成")
                else:
                    job.phase = "pdf"
                    with job._lock:
                        job.pdf_page = 0
                        job.pdf_total = 0
                    job.log("开始生成 PDF…")
                    pages, pdf_size, skipped = core.build_pdf_from_zip(
                        dest, pdf_path, job.dpi, job.quality,
                        on_progress=job.update_pdf,
                        on_warning=lambda msg: job.log(f"[警告] {msg}"),
                        cancel_event=job.cancel_event,
                        log=job.log,
                    )
                    job.pdf_path = str(pdf_path)
                    job.log(
                        f"PDF 完成：{pages} 页，{core.human_size(pdf_size)}"
                    )
                    if skipped:
                        job.log(f"有 {len(skipped)} 张图片无法读取，已跳过")

            with job._lock:
                finished = job.zip_skipped and (
                    job.pdf_skipped or not job.make_pdf
                )
                job.status = "skipped" if finished else "done"
                job.phase = "done"
                job.updated = time.time()
            job.log("全部完成")

        except core.CancelledError:
            job.mark_cancelled()
        except core.DownloadError as exc:
            if dest is not None and core.verify_zip(dest)[0]:
                job.zip_path = str(dest)
                job.fail(f"ZIP 已保存，但后续步骤失败：{exc}")
            else:
                job.fail(str(exc))
        except Exception as exc:
            job.fail(f"{type(exc).__name__}: {exc}")
            traceback.print_exc()


# ---------------------------------------------------------------------------
# HTTP 服务
# ---------------------------------------------------------------------------

class LocalServer(ThreadingHTTPServer):
    # Windows 下 SO_REUSEADDR 会让两个进程同时绑定同一端口，导致请求随机落到旧进程。
    allow_reuse_address = False
    daemon_threads = True


class Handler(BaseHTTPRequestHandler):
    server_version = "wnacg-web/1.0"
    manager: JobManager
    preview: PreviewService
    html: bytes
    manifest: bytes
    icons: dict[str, bytes]
    output_dir: Path

    def log_message(self, fmt: str, *args) -> None:  # 屏蔽轮询日志
        path = str(args[0]) if args else ""
        if "/api/status" in path:
            return
        sys.stderr.write(f"[web] {self.address_string()} {fmt % args}\n")

    # -- 响应工具 ---------------------------------------------------------

    def send_json(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def send_error_json(self, status: int, message: str) -> None:
        self.send_json({"ok": False, "error": message}, status)

    def send_bytes(
        self, data: bytes, content_type: str, cache: str = "no-store"
    ) -> None:
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", cache)
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def read_json(self) -> dict:
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            length = 0
        if length <= 0 or length > 1_000_000:
            raise ValueError("请求内容为空或过大")
        raw = self.rfile.read(length)
        data = json.loads(raw.decode("utf-8"))
        if not isinstance(data, dict):
            raise ValueError("请求格式错误")
        return data

    # -- 路由 -------------------------------------------------------------

    def do_GET(self) -> None:
        parsed = urllib.parse.urlsplit(self.path)
        path = parsed.path

        if path in ("/", "/index.html"):
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(self.html)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            try:
                self.wfile.write(self.html)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return

        if path == "/favicon.ico":
            self.send_response(204)
            self.end_headers()
            return

        if path == "/manifest.webmanifest":
            self.send_bytes(
                self.manifest,
                "application/manifest+json; charset=utf-8",
                "public, max-age=3600",
            )
            return

        if path in self.icons:
            self.send_bytes(
                self.icons[path], "image/png", "public, max-age=86400"
            )
            return

        if path == "/api/status":
            self.send_json({
                "ok": True,
                "version": core.__version__,
                "output_dir": str(self.output_dir),
                "proxy": self.manager.proxy or "",
                "direct": self.manager.direct,
                "jobs": self.manager.snapshot(),
            })
            return

        if path == "/api/download":
            self.handle_download(parsed.query)
            return

        if path == "/api/preview":
            self.handle_preview(parsed.query)
            return

        if path == "/api/preview/cover":
            self.handle_preview_cover(parsed.query)
            return

        self.send_error_json(404, "Not Found")

    def do_POST(self) -> None:
        parsed = urllib.parse.urlsplit(self.path)
        path = parsed.path

        if path == "/api/jobs":
            self.handle_submit()
            return
        if path.startswith("/api/jobs/") and (
            path.endswith("/cancel") or path.endswith("/retry")
        ):
            parts = path.strip("/").split("/")
            if len(parts) != 4:
                self.send_error_json(404, "Not Found")
                return
            job = self.manager.find(parts[2])
            if job is None:
                self.send_error_json(404, "任务不存在")
                return
            if parts[3] == "cancel":
                if job.status in ("queued", "running"):
                    job.cancel()
                    self.send_json({"ok": True})
                else:
                    self.send_error_json(409, "任务已经结束")
                return
            result = self.manager.retry(parts[2])
            if result:
                self.send_json({"ok": True, "job": job.snapshot()})
            else:
                self.send_error_json(409, "当前状态不能重试")
            return
        if path == "/api/clear":
            removed = self.manager.clear_finished()
            self.send_json({"ok": True, "removed": removed})
            return
        if path == "/api/open-folder":
            self.handle_open_folder()
            return
        if path == "/api/shutdown":
            self.send_json({"ok": True})
            threading.Thread(target=self.server.shutdown, daemon=True).start()
            return

        self.send_error_json(404, "Not Found")

    # -- 具体处理 ---------------------------------------------------------

    def handle_submit(self) -> None:
        try:
            payload = self.read_json()
        except (ValueError, json.JSONDecodeError) as exc:
            self.send_error_json(400, f"请求格式错误：{exc}")
            return

        urls = payload.get("urls")
        if isinstance(urls, str):
            urls = [urls]
        if not isinstance(urls, list):
            self.send_error_json(400, "缺少链接列表")
            return

        cleaned: list[str] = []
        for item in urls:
            text = str(item).strip()
            if not text:
                continue
            if len(text) > 2000:
                self.send_error_json(400, "链接过长")
                return
            cleaned.append(text)

        if not cleaned:
            self.send_error_json(400, "请至少粘贴一个链接")
            return
        if len(cleaned) > 30:
            self.send_error_json(400, "一次最多 30 个链接")
            return

        try:
            dpi = float(payload.get("dpi", core.DEFAULT_PDF_DPI))
        except (TypeError, ValueError):
            dpi = core.DEFAULT_PDF_DPI
        dpi = min(600.0, max(50.0, dpi))

        try:
            quality = int(payload.get("quality", core.DEFAULT_PDF_QUALITY))
        except (TypeError, ValueError):
            quality = core.DEFAULT_PDF_QUALITY
        quality = min(100, max(1, quality))

        jobs = self.manager.submit(
            cleaned,
            make_pdf=bool(payload.get("pdf", True)),
            dpi=dpi,
            quality=quality,
            overwrite=bool(payload.get("overwrite", False)),
        )
        self.send_json({
            "ok": True,
            "jobs": [job.snapshot() for job in jobs],
        })

    def handle_preview(self, query: str) -> None:
        params = urllib.parse.parse_qs(query)
        url = (params.get("url") or [""])[0].strip()
        if not url:
            self.send_json({"ok": False, "error": "缺少作品链接"})
            return
        try:
            preview = self.preview.get(url)
        except core.DownloadError as exc:
            self.send_json({"ok": False, "error": str(exc)})
            return
        except Exception as exc:
            self.send_json({
                "ok": False,
                "error": f"{type(exc).__name__}: {exc}",
            })
            return
        self.send_json({"ok": True, "preview": preview})

    def handle_preview_cover(self, query: str) -> None:
        params = urllib.parse.parse_qs(query)
        aid = (params.get("aid") or [""])[0]
        if not aid.isdigit():
            self.send_error_json(400, "参数错误")
            return
        try:
            result = self.preview.get_cover(aid)
        except Exception:
            result = None
        if not result:
            self.send_error_json(404, "封面不存在")
            return
        data, content_type = result
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "public, max-age=600")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def handle_download(self, query: str) -> None:
        params = urllib.parse.parse_qs(query)
        job_id = (params.get("id") or [""])[0]
        kind = (params.get("kind") or [""])[0]
        inline = (params.get("inline") or ["0"])[0] == "1"

        if kind not in ("zip", "pdf"):
            self.send_error_json(400, "未知文件类型")
            return

        job = self.manager.find(job_id)
        if job is None:
            self.send_error_json(404, "任务不存在")
            return

        path_text = job.zip_path if kind == "zip" else job.pdf_path
        if not path_text:
            self.send_error_json(404, "文件尚未生成")
            return

        path = Path(path_text)
        try:
            resolved = path.resolve()
            resolved.relative_to(self.output_dir.resolve())
        except (OSError, ValueError):
            self.send_error_json(403, "文件路径不允许")
            return
        if not resolved.is_file():
            self.send_error_json(404, "文件不存在")
            return

        content_type = "application/pdf" if kind == "pdf" else "application/zip"
        disposition = "inline" if (kind == "pdf" and inline) else "attachment"
        filename = resolved.name
        ascii_name = re.sub(r"[^\x20-\x7e]", "_", filename) or f"download.{kind}"
        encoded = urllib.parse.quote(filename)

        try:
            size = resolved.stat().st_size
        except OSError:
            self.send_error_json(404, "文件不存在")
            return

        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(size))
        self.send_header(
            "Content-Disposition",
            f"{disposition}; filename=\"{ascii_name}\"; filename*=UTF-8''{encoded}",
        )
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        try:
            with open(resolved, "rb") as handle:
                while True:
                    chunk = handle.read(256 * 1024)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def handle_open_folder(self) -> None:
        try:
            if os.name == "nt":
                os.startfile(str(self.output_dir))  # type: ignore[attr-defined]
            elif sys.platform == "darwin":
                subprocess.Popen(["open", str(self.output_dir)])
            else:
                subprocess.Popen(["xdg-open", str(self.output_dir)])
            self.send_json({"ok": True})
        except Exception as exc:
            self.send_error_json(500, f"无法打开文件夹：{exc}")


# ---------------------------------------------------------------------------
# 启动
# ---------------------------------------------------------------------------

def lan_ipv4_addresses() -> list[str]:
    ips: set[str] = set()
    try:
        for info in socket.getaddrinfo(
            socket.gethostname(), None, socket.AF_INET, socket.SOCK_STREAM
        ):
            ip = info[4][0]
            if not ip.startswith("127."):
                ips.add(ip)
    except OSError:
        pass
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.connect(("8.8.8.8", 80))
            ip = probe.getsockname()[0]
            if ip and not ip.startswith("127."):
                ips.add(ip)
    except OSError:
        pass
    return sorted(ips)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="wnacg 漫画下载器 Web UI（本地网页）"
    )
    parser.add_argument("--port", type=int, default=8765,
                        help="监听端口（默认 8765，被占用时自动顺延）")
    parser.add_argument("--host", default="127.0.0.1",
                        help="监听地址（默认仅本机；手机访问用 0.0.0.0）")
    parser.add_argument("--output", default="downloads", metavar="目录",
                        help="保存目录（默认 ./downloads）")
    parser.add_argument("--proxy", metavar="URL",
                        help="代理地址，如 http://127.0.0.1:7890（默认自动检测）")
    parser.add_argument("--no-proxy", action="store_true", help="强制直连")
    parser.add_argument("--direct", action="store_true",
                        help="DoH 直连模式：用 doh.pub 解析真实 IP，无需代理")
    parser.add_argument("--no-browser", action="store_true",
                        help="启动后不自动打开浏览器")
    return parser


def main() -> int:
    core.setup_console()
    args = build_parser().parse_args()

    direct = bool(args.direct)
    proxy = None
    if not direct and not args.no_proxy:
        proxy = args.proxy or core.detect_system_proxy()

    output_dir = Path(args.output).expanduser()
    try:
        output_dir.mkdir(parents=True, exist_ok=True)
        output_dir = output_dir.resolve()
    except OSError as exc:
        print(f"[错误] 无法创建保存目录 {output_dir}：{exc}", file=sys.stderr)
        return 1

    try:
        html = WEBUI_PATH.read_text(encoding="utf-8").encode("utf-8")
    except OSError as exc:
        print(f"[错误] 找不到网页文件 {WEBUI_PATH}：{exc}", file=sys.stderr)
        return 1

    try:
        manifest = MANIFEST_PATH.read_bytes()
    except OSError:
        manifest = (
            b'{"name":"wnacg","short_name":"wnacg","start_url":"/",'
            b'"display":"standalone","background_color":"#0a0d13",'
            b'"theme_color":"#0a0d13"}'
        )
    icons: dict[str, bytes] = {}
    for route, path in ICON_FILES.items():
        try:
            icons[route] = path.read_bytes()
        except OSError:
            continue

    manager = JobManager(output_dir, proxy, direct=direct)
    preview = PreviewService(proxy, direct=direct)

    Handler.manager = manager
    Handler.preview = preview
    Handler.html = html
    Handler.manifest = manifest
    Handler.icons = icons
    Handler.output_dir = output_dir

    server: Optional[ThreadingHTTPServer] = None
    port = args.port
    for candidate in range(args.port, args.port + 20):
        try:
            server = LocalServer((args.host, candidate), Handler)
            port = candidate
            break
        except OSError:
            continue
    if server is None:
        print(f"[错误] {args.port}~{args.port + 19} 端口都被占用", file=sys.stderr)
        return 1

    url = f"http://{args.host}:{port}/"
    local_url = (
        f"http://127.0.0.1:{port}/"
        if args.host in ("0.0.0.0", "::")
        else url
    )
    print("=" * 56)
    print(" wnacg 漫画下载器 · Web UI")
    if port != args.port:
        print(f" 提示：{args.port} 已被占用，已改用 {port}")
    print(f" 地址：{local_url}")
    print(f" 保存：{output_dir.resolve()}")
    if direct:
        print(" 网络：直连（DoH 解析真实 IP）")
    else:
        print(f" 代理：{proxy or '不使用（直连）'}")
    if args.host in ("0.0.0.0", "::"):
        addresses = lan_ipv4_addresses()
        if addresses:
            print(" 手机访问（同一 Wi-Fi）：")
            for address in addresses:
                print(f"   http://{address}:{port}/")
        else:
            print(" 未找到局域网 IPv4 地址")
        print(" 仅限可信局域网，不要在公共 Wi-Fi 下使用")
    print(" 关闭此窗口或按 Ctrl+C 停止服务")
    print("=" * 56)

    if not args.no_browser:
        opener = threading.Timer(0.8, lambda: webbrowser.open_new_tab(local_url))
        opener.daemon = True
        opener.start()

    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        print("\n正在停止服务…")
    finally:
        manager.stop()
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
