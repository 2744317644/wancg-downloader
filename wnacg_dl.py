#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
wnacg 漫画下载器（ZIP + PDF）
============================

给它一个作品页面，例如：
    https://www.wnacg.com/photos-index-aid-383877.html

脚本会自动：
    1. 打开该作品的「下載」页（等价于你点开漫画后看到的下载按钮）；
    2. 从页面里取出压缩包直链；
    3. 带进度、可断点续传地把 ZIP 保存到本地，并校验 ZIP 是否完整；
    4. 从 ZIP 中按文件名顺序读取图片，组合成一个 PDF（JPG 无损嵌入）。

只使用 Python 标准库；PDF 里的 JPG 不需要额外依赖。
PNG/WebP/CMYK 等格式会借助 Pillow，并以最高质量 JPEG（默认 100）写入；
如果更在意体积，可以用 --pdf-quality 调低到 90/95。
没装 Pillow 时会给出安装提示。

常用示例
--------
    python wnacg_dl.py https://www.wnacg.com/photos-index-aid-383877.html
    python wnacg_dl.py -o D:\\manga 383877 383000
    python wnacg_dl.py -i urls.txt --proxy http://127.0.0.1:7890
    python wnacg_dl.py --no-proxy URL
    python wnacg_dl.py --no-pdf URL
    python wnacg_dl.py --cookie "cf_clearance=..." URL

说明
----
* 默认会自动读取环境变量或 Windows 系统代理；国内访问一般需要代理。
* 下载中断后重新运行同一条命令即可续传（.part 文件）。
* 最终会同时保留 ZIP 和 PDF；已存在且有效的文件会自动跳过。
* 仅供个人备份使用，请遵守网站条款，不要高频批量抓取。
"""

from __future__ import annotations

import argparse
import http.client
import http.cookiejar
import io
import json
import os
import re
import socket
import ssl
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from dataclasses import dataclass
from html import unescape
from pathlib import Path
from typing import Callable, Iterable, Optional

try:  # PDF 的图片解码优先用 Pillow；纯 JPG 不依赖它
    from PIL import Image, ImageOps

    _HAS_PIL = True
except Exception:  # pragma: no cover - 没装 Pillow 时走纯标准库 JPEG 路径
    Image = None  # type: ignore[assignment]
    ImageOps = None  # type: ignore[assignment]
    _HAS_PIL = False

__version__ = "1.5.0"

DEFAULT_HOST = "www.wnacg.com"
DEFAULT_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/126.0.0.0 Safari/537.36"
)
CHUNK_SIZE = 256 * 1024
DEFAULT_PDF_DPI = 300.0
DEFAULT_PDF_QUALITY = 100
DEFAULT_DOH_URL = "https://doh.pub/dns-query?name={host}&type=A"

# DoH 有时会返回被污染的地址；这些是实测可用的备用 IP。
# 解析时会先用 TLS + SNI 验证，失效后再走 DoH / 系统 DNS。
STATIC_HOST_IPS: dict[str, list[str]] = {
    "www.wnacg.com": ["104.20.44.182", "172.66.175.138"],
    "wnacg.com": ["104.20.44.182", "172.66.175.138"],
    "t4.qy0.ru": ["104.20.44.182", "172.66.175.138"],
    "dl1.wn01.download": ["185.243.218.90", "51.159.194.108"],
    "img4.wnacg.com": ["172.67.74.237", "104.26.12.109"],
    "d1.wcdn.date": ["172.67.158.148", "104.21.33.39"],
}

IMAGE_EXTENSIONS = {
    ".jpg", ".jpeg", ".jpe", ".jfif",
    ".png", ".webp", ".gif", ".bmp",
    ".tif", ".tiff",
}


# ---------------------------------------------------------------------------
# 基础工具
# ---------------------------------------------------------------------------

class DownloadError(Exception):
    """可以直接展示给用户的错误。"""


class LinkDeadError(DownloadError):
    """备用直链失效（404/403 等），可以尝试切换到 Server 1。"""


class PillowRequiredError(DownloadError):
    """遇到了必须借助 Pillow 才能转换的图片格式。"""


class CancelledError(DownloadError):
    """用户取消了任务。"""


class IncompleteDownloadError(DownloadError):
    """网络中断导致文件不完整，可以通过 Range 续传重试。"""


def is_dead_status(status: Optional[int]) -> bool:
    return status in (403, 404, 410)


def setup_console() -> None:
    """尽量让 Windows 控制台正确显示中文，且不会因编码问题崩溃。"""
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(
                encoding="utf-8", errors="replace", line_buffering=True
            )  # type: ignore[attr-defined]
        except (AttributeError, OSError, ValueError):
            pass


def human_size(num: Optional[float]) -> str:
    if num is None:
        return "未知大小"
    value = float(num)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if value < 1024 or unit == "TB":
            if unit == "B":
                return f"{value:.0f} {unit}"
            return f"{value:.1f} {unit}"
        value /= 1024
    return f"{value:.1f} TB"


def is_cloudflare_challenge(text: str, headers=None) -> bool:
    if headers is not None:
        try:
            if (headers.get("cf-mitigated") or "").lower() == "challenge":
                return True
        except AttributeError:
            pass
    head = (text or "")[:6000]
    return (
        "Just a moment" in head
        or "cf-chl-" in head
        or "challenge-platform" in head
        or "Enable JavaScript and cookies to continue" in head
    )


def challenge_hint(url: str) -> str:
    return (
        "被 Cloudflare 人机验证拦截了：\n"
        f"  {url}\n"
        "  处理办法：用浏览器打开上面的链接并通过验证，然后按 F12 → Network（网络）→ "
        "随便点一个请求 → 复制请求头里的 Cookie（至少要有 cf_clearance），再用\n"
        '    --cookie "cf_clearance=..."\n'
        "  传给本脚本；如果仍然不行，请让 --user-agent 与浏览器保持一致。"
    )


# ---------------------------------------------------------------------------
# HTTP 客户端
# ---------------------------------------------------------------------------

class DohResolver:
    """用 DoH 解析真实 IP，绕过本地 DNS 污染（不改变 TLS SNI）。"""

    def __init__(self, endpoint: str = DEFAULT_DOH_URL, timeout: float = 8.0):
        self.endpoint = endpoint
        self.timeout = timeout
        self.cache: dict[str, tuple[float, list[str]]] = {}
        self.lock = threading.Lock()
        self.opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({})
        )
        self.opener.addheaders = [
            ("User-Agent", DEFAULT_UA),
            ("Accept", "application/dns-json"),
        ]

    def resolve(self, host: str) -> list[str]:
        host = host.strip().strip("[]")
        if re.fullmatch(r"\d{1,3}(?:\.\d{1,3}){3}", host):
            return [host]

        now = time.time()
        with self.lock:
            cached = self.cache.get(host)
            if cached and cached[0] > now:
                return cached[1]

            candidates = list(STATIC_HOST_IPS.get(host, []))
            valid = self._validate(host, candidates)
            if not valid:
                for ip in self._query(host, depth=0):
                    if ip not in candidates:
                        candidates.append(ip)
                valid = self._validate(
                    host, [ip for ip in candidates if ip not in STATIC_HOST_IPS.get(host, [])]
                )
            if not valid:
                try:
                    infos = socket.getaddrinfo(
                        host, 443, socket.AF_INET, socket.SOCK_STREAM
                    )
                    fallback = []
                    for info in infos:
                        ip = info[4][0]
                        if ip not in fallback:
                            fallback.append(ip)
                    valid = self._validate(host, fallback)
                except OSError:
                    valid = []
            if not valid:
                raise OSError(
                    f"无法解析到可用的真实 IP：{host}（DoH 可能被污染或 IP 被封锁）"
                )
            self.cache[host] = (now + 600, valid)
            return valid

    @staticmethod
    def _validate(host: str, ips: list[str]) -> list[str]:
        """用 TLS + SNI 握手验证 IP 确实属于该域名，过滤 DNS 污染结果。"""
        valid: list[str] = []
        context = ssl.create_default_context()
        for ip in ips:
            try:
                with socket.create_connection((ip, 443), timeout=3) as sock:
                    with context.wrap_socket(sock, server_hostname=host):
                        valid.append(ip)
            except (OSError, ssl.SSLError):
                continue
            if len(valid) >= 2:
                break
        return valid

    def _query(self, host: str, depth: int) -> list[str]:
        url = self.endpoint.format(host=urllib.parse.quote(host, safe=""))
        try:
            with self.opener.open(url, timeout=self.timeout) as response:
                data = json.loads(response.read(20000))
        except Exception:
            return []

        ips: list[str] = []
        cnames: list[str] = []
        for answer in data.get("Answer") or []:
            if not isinstance(answer, dict):
                continue
            if answer.get("type") == 1 and answer.get("data"):
                ip = str(answer["data"])
                if ip not in ips:
                    ips.append(ip)
            elif answer.get("type") == 5 and answer.get("data"):
                cnames.append(str(answer["data"]).rstrip("."))
        if not ips and cnames and depth < 2:
            for cname in cnames:
                for ip in self._query(cname, depth + 1):
                    if ip not in ips:
                        ips.append(ip)
        return ips


class PinnedHTTPSConnection(http.client.HTTPSConnection):
    """连接 DoH 解析出的 IP，但 TLS SNI 仍然使用原域名。"""

    def __init__(self, host: str, ips: list[str], **kwargs):
        super().__init__(host, **kwargs)
        self._ips = list(ips)

    def connect(self) -> None:
        context = self._context or ssl.create_default_context()
        server_hostname = self.host.split(":")[0]
        last_error: Optional[BaseException] = None
        for ip in self._ips:
            sock = None
            try:
                sock = socket.create_connection(
                    (ip, self.port), self.timeout, self.source_address
                )
                self.sock = context.wrap_socket(
                    sock, server_hostname=server_hostname
                )
                return
            except OSError as exc:
                last_error = exc
                if sock is not None:
                    try:
                        sock.close()
                    except OSError:
                        pass
        raise last_error or OSError("没有可用 IP")


class PinnedHTTPSHandler(urllib.request.HTTPSHandler):
    def __init__(self, resolver: DohResolver):
        super().__init__()
        self.resolver = resolver

    def https_open(self, req):
        host = req.host.split(":")[0]
        try:
            ips = self.resolver.resolve(host)
        except Exception as exc:
            raise urllib.error.URLError(
                f"DoH 解析失败 {host}：{exc}"
            ) from exc

        return self.do_open(
            lambda connection_host, **kwargs: PinnedHTTPSConnection(
                connection_host, ips, **kwargs
            ),
            req,
        )


class HttpClient:
    def __init__(
        self,
        proxy: Optional[str] = None,
        cookie: str = "",
        user_agent: str = DEFAULT_UA,
        timeout: float = 60.0,
        direct: bool = False,
    ) -> None:
        self.proxy = proxy
        self.direct = direct
        self.cookie = (cookie or "").strip()
        self.user_agent = user_agent
        self.timeout = timeout
        self.resolver: Optional[DohResolver] = None

        handlers: list[urllib.request.BaseHandler] = [
            urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar())
        ]
        if direct:
            # DoH 解析真实 IP，直连；仍然使用原域名的 TLS SNI 和 Host
            handlers.append(urllib.request.ProxyHandler({}))
            self.resolver = DohResolver()
            handlers.append(PinnedHTTPSHandler(self.resolver))
        elif proxy:
            handlers.append(
                urllib.request.ProxyHandler({"http": proxy, "https": proxy})
            )
        else:
            # 显式禁用系统代理，保证 --no-proxy 真的是直连
            handlers.append(urllib.request.ProxyHandler({}))
        self.opener = urllib.request.build_opener(*handlers)

    def open(
        self,
        url: str,
        *,
        referer: Optional[str] = None,
        headers: Optional[dict] = None,
        data: Optional[bytes] = None,
        timeout: Optional[float] = None,
    ):
        req_headers = {
            "User-Agent": self.user_agent,
            "Accept": (
                "text/html,application/xhtml+xml,application/xml;q=0.9,"
                "image/avif,image/webp,*/*;q=0.8"
            ),
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.7",
        }
        if self.cookie:
            req_headers["Cookie"] = self.cookie
        if referer:
            req_headers["Referer"] = referer
        if headers:
            req_headers.update(headers)

        request = urllib.request.Request(
            url,
            data=data,
            headers=req_headers,
            method="POST" if data is not None else "GET",
        )
        return self.opener.open(request, timeout=timeout or self.timeout)

    def get_text(self, url: str, *, referer: Optional[str] = None,
                 attempts: int = 3) -> str:
        last_error: object = None
        for attempt in range(1, attempts + 1):
            try:
                with self.open(url, referer=referer) as response:
                    raw = response.read()
                    encoding = response.headers.get_content_charset()
                    if not encoding:
                        match = re.search(
                            rb'charset=["\']?([A-Za-z0-9._-]+)', raw[:4096]
                        )
                        encoding = (
                            match.group(1).decode("ascii", "ignore")
                            if match else "utf-8"
                        )
                    text = raw.decode(encoding or "utf-8", "replace")
                    if is_cloudflare_challenge(text, response.headers):
                        raise DownloadError(challenge_hint(url))
                    return text
            except DownloadError:
                raise
            except urllib.error.HTTPError as exc:
                body = ""
                try:
                    body = exc.read(8192).decode("utf-8", "replace")
                except Exception:
                    pass
                if exc.code == 404:
                    raise DownloadError(f"页面不存在（404）：{url}") from None
                if is_cloudflare_challenge(body, exc.headers):
                    raise DownloadError(challenge_hint(url)) from None
                last_error = f"HTTP {exc.code}"
                if exc.code not in (429, 500, 502, 503, 504, 520, 521, 522, 524):
                    break
            except (urllib.error.URLError, TimeoutError, ConnectionError,
                    OSError, http.client.HTTPException) as exc:
                last_error = exc
            if attempt < attempts:
                time.sleep(min(2 ** (attempt - 1), 8))
        raise DownloadError(
            f"访问失败：{url}\n  原因：{last_error}\n"
            "  如果代理不可用，可加 --no-proxy 直连；如果直连打不开，"
            "可加 --proxy http://127.0.0.1:7890 指定代理。"
        )


def detect_system_proxy() -> Optional[str]:
    """优先读环境变量，其次读 Windows 系统代理设置。"""
    for name in ("HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy"):
        value = os.environ.get(name)
        if value:
            return value

    if os.name != "nt":
        return None

    try:
        import winreg

        path = r"Software\Microsoft\Windows\CurrentVersion\Internet Settings"
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, path) as key:
            enabled, _ = winreg.QueryValueEx(key, "ProxyEnable")
            server, _ = winreg.QueryValueEx(key, "ProxyServer")
        if not enabled or not server:
            return None
        if "=" in server:  # 形如 http=127.0.0.1:7890;https=...
            parts = dict(
                item.split("=", 1)
                for item in server.split(";")
                if "=" in item
            )
            server = parts.get("https") or parts.get("http") or ""
        if not server:
            return None
        return server if "://" in server else f"http://{server}"
    except Exception:
        return None


# ---------------------------------------------------------------------------
# 页面解析
# ---------------------------------------------------------------------------

_WIN_BAD_CHARS = re.compile(r'[<>:"/\\|?*\x00-\x1f]')
_WIN_RESERVED = {
    "CON", "PRN", "AUX", "NUL",
    *(f"COM{i}" for i in range(1, 10)),
    *(f"LPT{i}" for i in range(1, 10)),
}


def sanitize_filename(name: str, limit: int = 140) -> str:
    name = _WIN_BAD_CHARS.sub("_", name or "")
    name = re.sub(r"\s+", " ", name).strip().strip(". ")
    if not name:
        name = "untitled"
    if name.split(".")[0].upper() in _WIN_RESERVED:
        name = "_" + name
    if len(name) > limit:
        name = name[:limit].rstrip(" .")
    return name


def js_config_string(html: str, key: str) -> Optional[str]:
    """读取页面 CONFIG 里形如 FILE_NAME: "..." 的字符串。"""
    match = re.search(
        rf'{re.escape(key)}\s*:\s*("(?:[^"\\]|\\.)*")', html
    )
    if not match:
        return None
    literal = match.group(1)
    try:
        return json.loads(literal)
    except (json.JSONDecodeError, TypeError):
        return literal[1:-1]


def page_title(html: str) -> Optional[str]:
    match = re.search(r"<title[^>]*>(.*?)</title>", html, re.I | re.S)
    if not match:
        return None
    title = unescape(match.group(1)).strip()
    title = re.sub(r"\s*[-–—|]\s*紳士漫畫.*$", "", title).strip()
    title = re.sub(r"\s*下載\s*$", "", title).strip()
    return title or None


def extract_zip_url(html: str) -> Optional[str]:
    """从下载页提取真正的 ZIP 直链（备用线路 dl1 等）。"""
    candidates: list[str] = []
    for match in re.finditer(r'href\s*=\s*"([^"]+)"', html, re.I):
        url = unescape(match.group(1)).strip()
        if not re.search(r"\.zip(?:\?|$)", url, re.I):
            continue
        if url.startswith("//"):
            url = "https:" + url
        elif url.startswith("/"):
            continue
        if url.lower().startswith(("http://", "https://")):
            candidates.append(url)

    # 优先选择下载线路（dl1 / dl2 ...），避免误把广告里的 zip 当成资源
    for url in candidates:
        if re.search(r"://dl\d*\.", url, re.I):
            return url
    if candidates:
        return candidates[0]

    # 兜底：有些页面把直链写在脚本里
    match = re.search(
        r'https?://[^\s"\'<>]+?\.zip(?:\?[^\s"\'<>]*)?', html, re.I
    )
    return match.group(0) if match else None


def url_to_ascii(url: str) -> str:
    """把含中文/空格/方括号的 URL 转成可请求的 ASCII 形式。"""
    parts = urllib.parse.urlsplit(url)
    path = urllib.parse.quote(parts.path, safe="/%:@!$&'()*+,;=-._~")
    query = urllib.parse.quote(parts.query, safe="=&%:@!$'()*+,;/?-._~")
    return urllib.parse.urlunsplit(
        (parts.scheme, parts.netloc, path, query, parts.fragment)
    )


@dataclass
class Target:
    host: str
    aid: str
    sid: Optional[str] = None
    source: str = ""

    @property
    def base(self) -> str:
        return f"https://{self.host}"

    @property
    def gallery_url(self) -> str:
        url = f"{self.base}/photos-index-aid-{self.aid}.html"
        if self.sid:
            url += f"?s={urllib.parse.quote(self.sid)}"
        return url

    @property
    def download_url(self) -> str:
        url = f"{self.base}/download-index-aid-{self.aid}.html"
        if self.sid:
            url += f"?s={urllib.parse.quote(self.sid)}"
        return url


@dataclass
class Album:
    aid: str
    title: Optional[str]
    filename: str
    raw_name: Optional[str]
    page_url: str
    zip_url: Optional[str]
    worker_api: Optional[str] = None
    file_key: Optional[str] = None


def resolve_target(arg: str, http: HttpClient) -> Target:
    text = (arg or "").strip().strip('"\'')
    if not text:
        raise DownloadError("链接为空")

    if re.fullmatch(r"\d+", text):
        return Target(DEFAULT_HOST, text, source=text)

    if "://" not in text:
        text = "https://" + text

    parsed = urllib.parse.urlsplit(text)
    if parsed.scheme not in ("http", "https"):
        raise DownloadError(f"不支持的链接类型：{text}")

    host = parsed.netloc or DEFAULT_HOST
    sid = urllib.parse.parse_qs(parsed.query).get("s", [None])[0]

    match = re.search(r"aid-(\d+)", parsed.path)
    if match:
        return Target(host, match.group(1), sid, text)

    # 阅读页 / 图片页：从页面里找回作品编号
    if "/photos-view-" in parsed.path or "/photos-slide-" in parsed.path:
        html = http.get_text(text)
        match = re.search(r"/photos-index-aid-(\d+)\.html", html)
        if not match:
            raise DownloadError(f"无法从阅读页找到作品编号：{text}")
        sid_match = re.search(
            rf"/photos-index-aid-{match.group(1)}\.html\?s=([\w-]+)", html
        )
        return Target(
            host, match.group(1), sid_match.group(1) if sid_match else sid, text
        )

    raise DownloadError(
        "无法识别这个链接。请使用作品页，例如：\n"
        "  https://www.wnacg.com/photos-index-aid-383877.html"
    )


def parse_album(html: str, target: Target) -> Album:
    zip_url = extract_zip_url(html)
    if zip_url:
        zip_url = url_to_ascii(zip_url)
    file_name = js_config_string(html, "FILE_NAME")
    worker_api = js_config_string(html, "WORKER_API")
    file_key = js_config_string(html, "FILE_KEY")
    title = page_title(html)

    n_param = None
    if zip_url:
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(zip_url).query)
        if query.get("n"):
            n_param = query["n"][0]

    raw_name = file_name or n_param or title or f"wnacg-{target.aid}"
    raw_name = unescape(raw_name).strip()
    raw_name = re.sub(r"\.zip$", "", raw_name, flags=re.I)
    filename = sanitize_filename(raw_name) + ".zip"

    return Album(
        aid=target.aid,
        title=title,
        filename=filename,
        raw_name=(
            unescape(file_name or n_param) if (file_name or n_param) else None
        ),
        page_url=target.download_url,
        zip_url=zip_url,
        worker_api=worker_api,
        file_key=file_key,
    )


def request_worker_link(http: HttpClient, album: Album) -> Optional[str]:
    """Server 1 是 Cloudflare 保护的 JSON 接口；能通就用，不通则由调用方报错。"""
    if not album.worker_api or not album.file_key:
        return None
    payload = json.dumps(
        {"file_key": album.file_key, "file_name": album.raw_name or album.filename},
        ensure_ascii=False,
    ).encode("utf-8")
    try:
        with http.open(
            album.worker_api,
            referer=album.page_url,
            data=payload,
            headers={
                "Content-Type": "application/json",
                "Accept": "application/json, text/plain, */*",
                "Origin": "https://www.wnacg.com",
            },
        ) as response:
            body = response.read().decode("utf-8", "replace")
        data = json.loads(body)
        if data.get("success") and data.get("url"):
            return data["url"]
        message = data.get("msg") or body[:200]
        raise DownloadError(f"Server 1 接口返回失败：{message}")
    except DownloadError:
        raise
    except Exception as exc:  # 接口被 Cloudflare 拦截时走这里
        raise DownloadError(f"Server 1 接口不可用：{exc}") from None


def fetch_album(http: HttpClient, target: Target) -> Album:
    html = http.get_text(target.download_url, referer=target.gallery_url)

    has_chapters = 'id="ch-wrap"' in html
    album = parse_album(html, target)

    if not album.zip_url:
        if has_chapters:
            raise DownloadError(
                "这个链接是「合集 / 系列」页面，本身没有单个压缩包。\n"
                "  请打开其中某一话的页面，把那一话的作品链接传给脚本。"
            )
        if album.worker_api and album.file_key:
            album.zip_url = request_worker_link(http, album)
        if not album.zip_url:
            raise DownloadError(
                "下载页里没有找到 ZIP 直链，可能是作品已下架、需要登录，"
                "或网站改版了。"
            )

    return album


# ---------------------------------------------------------------------------
# 下载
# ---------------------------------------------------------------------------

class Progress:
    def __init__(self, total: Optional[int], prefix: str = "  ") -> None:
        self.total = total
        self.prefix = prefix
        self.started = time.time()
        self.last_print = 0.0
        self.tty = bool(getattr(sys.stdout, "isatty", lambda: False)())
        self.enabled = True

    def update(self, done: int) -> None:
        now = time.time()
        if now - self.last_print < 0.2:
            return
        self.last_print = now
        elapsed = max(now - self.started, 0.001)
        speed = done / elapsed
        if self.total:
            percent = done * 100.0 / self.total
            line = (
                f"{percent:5.1f}%  {human_size(done)} / {human_size(self.total)}"
                f"  {human_size(speed)}/s"
            )
        else:
            line = f"{human_size(done)}  {human_size(speed)}/s"
        if self.tty:
            print(f"\r{self.prefix}{line}", end="", flush=True)

    def finish(self, done: int, total: Optional[int]) -> None:
        elapsed = max(time.time() - self.started, 0.001)
        speed = done / elapsed
        if self.tty:
            print("\r" + " " * 78 + "\r", end="")
            print(
                f"{self.prefix}完成  {human_size(done)}"
                f"  用时 {elapsed:.0f}s  平均 {human_size(speed)}/s"
            )
        else:
            print(f"{self.prefix}完成  {human_size(done)}  用时 {elapsed:.0f}s")


def probe_size(
    http: HttpClient, url: str, referer: str
) -> tuple[Optional[int], Optional[int]]:
    """返回 (文件大小, HTTP 状态码)。状态码为 404/403 时说明直链已失效。"""
    try:
        with http.open(
            url,
            referer=referer,
            headers={
                "Accept": "*/*",
                "Accept-Encoding": "identity",
                "Range": "bytes=0-0",
            },
            timeout=20,
        ) as response:
            content_range = response.headers.get("Content-Range") or ""
            match = re.search(r"/\s*(\d+)\s*$", content_range)
            if match:
                return int(match.group(1)), response.status
            length = response.headers.get("Content-Length")
            if length:
                return int(length), response.status
            return None, response.status
    except urllib.error.HTTPError as exc:
        return None, exc.code
    except Exception:
        return None, None


def switch_to_worker(
    http: HttpClient,
    album: Album,
    status: Optional[int] = None,
    *,
    log: Callable[[str], None] = print,
) -> Album:
    """备用线路失效时，改走下载页上的 Server 1 接口。"""
    reason = f"（HTTP {status}）" if status else ""
    if not (album.worker_api and album.file_key):
        raise DownloadError(
            f"备用直链失效{reason}，下载页里也没有可用的 Server 1 配置。\n"
            "  请稍后重试，或直接用浏览器打开下载页手动下载。"
        )

    log(f"备用直链失效{reason}，尝试 Server 1 接口…")
    try:
        fresh_url = request_worker_link(http, album)
    except DownloadError as exc:
        raise DownloadError(
            "备用直链失效，而 Server 1 接口又被 Cloudflare 人机验证拦截。\n"
            "  可选办法：\n"
            "   1. 稍后重试——新上传的作品可能还没同步到备用线路；\n"
            "   2. 用浏览器打开下载页手动下载；\n"
            "   3. 在浏览器访问 https://d1.wcdn.date/ 通过验证，复制 Cookie 中的 "
            "cf_clearance，然后加参数重试：\n"
            '      --cookie "cf_clearance=..." --user-agent "与浏览器相同的 UA"\n'
            f"  接口详情：{exc}"
        ) from None

    album.zip_url = url_to_ascii(fresh_url)
    log("已切换到 Server 1")
    return album


def verify_zip(path: Path) -> tuple[bool, int]:
    try:
        if not zipfile.is_zipfile(path):
            return False, 0
        with zipfile.ZipFile(path) as archive:
            return True, len(archive.namelist())
    except (OSError, zipfile.BadZipFile):
        return False, 0


# ---------------------------------------------------------------------------
# 从 ZIP 生成 PDF
# ---------------------------------------------------------------------------

def natural_sort_key(text: str) -> list:
    """让 1.jpg, 2.jpg, 10.jpg 按数字顺序排列。"""
    return [
        (0, int(part)) if part.isdigit() else (1, part.lower())
        for part in re.split(r"(\d+)", text)
    ]


def decode_zip_name(info: zipfile.ZipInfo) -> str:
    """处理没有 UTF-8 标志位的老 ZIP（Shift-JIS / GBK / Big5 文件名）。"""
    name = info.filename
    if info.flag_bits & 0x800:
        return name
    try:
        raw = name.encode("cp437")
    except UnicodeEncodeError:
        return name
    for encoding in ("utf-8", "gbk", "big5", "shift_jis", "cp932"):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            continue
    return name


def list_zip_images(archive: zipfile.ZipFile) -> list[zipfile.ZipInfo]:
    images: list[tuple[list, zipfile.ZipInfo]] = []
    for info in archive.infolist():
        if info.is_dir():
            continue
        name = decode_zip_name(info).replace("\\", "/")
        parts = [part for part in name.split("/") if part]
        if not parts or "__MACOSX" in parts:
            continue
        base = parts[-1]
        if base.startswith("."):
            continue
        extension = os.path.splitext(base)[1].lower()
        if extension not in IMAGE_EXTENSIONS:
            continue
        images.append((natural_sort_key(name), info))
    images.sort(key=lambda item: item[0])
    return [info for _, info in images]


def jpeg_dimensions(data: bytes) -> Optional[tuple[int, int, int, int]]:
    """从 JPEG 字节流里读出 (宽, 高, 颜色分量数, 精度)，不依赖 Pillow。"""
    if len(data) < 4 or data[:2] != b"\xff\xd8":
        return None
    sof_markers = {
        0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
        0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF,
    }
    offset = 2
    size = len(data)
    while offset + 4 <= size:
        if data[offset] != 0xFF:
            offset += 1
            continue
        marker = data[offset + 1]
        if marker == 0xFF:
            offset += 1
            continue
        if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
            offset += 2
            continue
        if marker == 0xD9:
            break
        segment_length = int.from_bytes(data[offset + 2:offset + 4], "big")
        if segment_length < 2:
            break
        if marker in sof_markers:
            if offset + 10 > size:
                break
            precision = data[offset + 4]
            height = int.from_bytes(data[offset + 5:offset + 7], "big")
            width = int.from_bytes(data[offset + 7:offset + 9], "big")
            components = data[offset + 9]
            if width and height:
                return width, height, components, precision
            return None
        if marker == 0xDA:  # 图像数据开始，SOF 应在它之前
            break
        offset += 2 + segment_length
    return None


def jpeg_needs_pillow(data: bytes) -> bool:
    """带 EXIF 旋转信息的 JPEG 需要 Pillow 摆正。"""
    if not _HAS_PIL:
        return False
    if b"Exif\x00\x00" not in data[:262144]:
        return False
    try:
        with Image.open(io.BytesIO(data)) as image:
            orientation = image.getexif().get(0x0112, 1)
        return orientation not in (1, None)
    except Exception:
        return False


def prepare_image_with_pillow(
    data: bytes, jpeg_quality: int = DEFAULT_PDF_QUALITY
) -> tuple[int, int, str, bytes, bool]:
    assert Image is not None and ImageOps is not None
    with Image.open(io.BytesIO(data)) as image:
        image.load()
        image = ImageOps.exif_transpose(image)

        if image.mode == "P":
            image = image.convert(
                "RGBA" if "transparency" in image.info else "RGB"
            )
        if image.mode in ("RGBA", "LA"):
            rgba = image.convert("RGBA")
            background = Image.new("RGB", rgba.size, (255, 255, 255))
            background.paste(rgba, mask=rgba.getchannel("A"))
            image = background
        elif image.mode == "1":
            image = image.convert("L")
        elif image.mode in ("I", "I;16", "I;16B", "I;16L", "F"):
            image = image.convert("I").point(lambda value: value / 256).convert("L")
        elif image.mode not in ("L", "RGB"):
            image = image.convert("RGB")

        width, height = image.size
        quality = max(1, min(100, int(jpeg_quality)))
        output = io.BytesIO()
        if image.mode == "L":
            color_space = "/DeviceGray"
            image.save(output, format="JPEG", quality=quality, optimize=True)
        else:
            color_space = "/DeviceRGB"
            image.save(
                output, format="JPEG", quality=quality,
                optimize=True, subsampling=0,
            )
    return width, height, color_space, output.getvalue(), True


def prepare_image(
    data: bytes, jpeg_quality: int = DEFAULT_PDF_QUALITY
) -> tuple[int, int, str, bytes, bool]:
    """返回 (宽, 高, 颜色空间, 图像数据, 是否原始 JPEG)。"""
    info = jpeg_dimensions(data)
    if info:
        width, height, components, precision = info
        if (
            precision == 8
            and components in (1, 3)
            and not jpeg_needs_pillow(data)
        ):
            color_space = "/DeviceGray" if components == 1 else "/DeviceRGB"
            return width, height, color_space, data, True

    if not _HAS_PIL:
        raise PillowRequiredError(
            "这张图片需要 Pillow 才能转换（PNG/WebP/CMYK/带旋转的 JPEG 等）。\n"
            "  请先安装：pip install pillow"
        )
    return prepare_image_with_pillow(data, jpeg_quality)


class PdfWriter:
    """极简 PDF 1.4 写入器：每页一张全幅图片，JPEG 直接嵌入、不重编码。"""

    def __init__(self, path: Path, dpi: float = DEFAULT_PDF_DPI) -> None:
        self.path = path
        self.dpi = max(dpi, 1.0)
        self.file = open(path, "wb")
        self.offsets: dict[int, int] = {}
        self.page_objects: list[int] = []
        self.next_object = 3  # 1 = Catalog, 2 = Pages
        self.file.write(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")

    def _write_object(
        self, number: int, body: bytes, stream: Optional[bytes] = None
    ) -> None:
        self.offsets[number] = self.file.tell()
        self.file.write(f"{number} 0 obj\n".encode("ascii"))
        self.file.write(body)
        if stream is not None:
            self.file.write(b"\nstream\n")
            self.file.write(stream)
            self.file.write(b"\nendstream")
        self.file.write(b"\nendobj\n")

    def add_page(
        self,
        width: int,
        height: int,
        color_space: str,
        stream: bytes,
        is_jpeg: bool,
    ) -> None:
        page_number = self.next_object
        image_number = page_number + 1
        content_number = page_number + 2
        self.next_object += 3
        self.page_objects.append(page_number)

        width_pt = max(1.0, width * 72.0 / self.dpi)
        height_pt = max(1.0, height * 72.0 / self.dpi)
        image_filter = b"DCTDecode" if is_jpeg else b"FlateDecode"

        image_body = (
            f"<< /Type /XObject /Subtype /Image /Width {width} /Height {height} "
            f"/ColorSpace {color_space} /BitsPerComponent 8 "
            f"/Filter /{image_filter.decode('ascii')} /Length {len(stream)} >>"
        ).encode("ascii")
        self._write_object(image_number, image_body, stream)

        content = (
            f"q\n{width_pt:.3f} 0 0 {height_pt:.3f} 0 0 cm\n/Im0 Do\nQ\n"
        ).encode("ascii")
        self._write_object(
            content_number,
            f"<< /Length {len(content)} >>".encode("ascii"),
            content,
        )

        page_body = (
            f"<< /Type /Page /Parent 2 0 R "
            f"/MediaBox [0 0 {width_pt:.3f} {height_pt:.3f}] "
            f"/Resources << /XObject << /Im0 {image_number} 0 R >> >> "
            f"/Contents {content_number} 0 R >>"
        ).encode("ascii")
        self._write_object(page_number, page_body)

    def finish(self) -> None:
        kids = " ".join(f"{number} 0 R" for number in self.page_objects)
        self._write_object(1, b"<< /Type /Catalog /Pages 2 0 R >>")
        self._write_object(
            2,
            f"<< /Type /Pages /Kids [{kids}] /Count {len(self.page_objects)} >>"
            .encode("ascii"),
        )

        xref_offset = self.file.tell()
        total_objects = self.next_object - 1
        self.file.write(f"xref\n0 {total_objects + 1}\n".encode("ascii"))
        self.file.write(b"0000000000 65535 f \n")
        for number in range(1, total_objects + 1):
            if number not in self.offsets:
                raise DownloadError(f"PDF 写入异常：对象 {number} 缺失")
            self.file.write(
                f"{self.offsets[number]:010d} 00000 n \n".encode("ascii")
            )
        self.file.write(
            (
                f"trailer\n<< /Size {total_objects + 1} /Root 1 0 R >>\n"
                f"startxref\n{xref_offset}\n%%EOF\n"
            ).encode("ascii")
        )
        self.file.flush()
        self.file.close()

    def close(self) -> None:
        if not self.file.closed:
            self.file.close()


def verify_pdf(path: Path) -> bool:
    try:
        size = path.stat().st_size
        if size < 100:
            return False
        with open(path, "rb") as handle:
            head = handle.read(8)
            handle.seek(max(0, size - 2048))
            tail = handle.read()
        return head.startswith(b"%PDF-") and b"%%EOF" in tail
    except OSError:
        return False


def build_pdf_from_zip(
    zip_path: Path,
    pdf_path: Path,
    dpi: float = DEFAULT_PDF_DPI,
    jpeg_quality: int = DEFAULT_PDF_QUALITY,
    *,
    on_progress: Optional[Callable[[int, int], None]] = None,
    on_warning: Optional[Callable[[str], None]] = None,
    cancel_event: Optional[threading.Event] = None,
    log: Callable[[str], None] = print,
) -> tuple[int, int, list[str]]:
    """按 ZIP 中的图片顺序生成 PDF，返回 (页数, 字节数, 跳过的图片名)。"""
    temp_path = Path(str(pdf_path) + ".part")
    skipped: list[str] = []
    writer: Optional[PdfWriter] = None
    tty = (on_progress is None) and bool(
        getattr(sys.stdout, "isatty", lambda: False)()
    )
    last_update = 0.0

    try:
        with zipfile.ZipFile(zip_path) as archive:
            images = list_zip_images(archive)
            total = len(images)
            if total == 0:
                raise DownloadError("压缩包里没有找到可转换的图片（jpg/png/webp 等）")

            log(f"正在生成 PDF（共 {total} 张图片）…")
            writer = PdfWriter(temp_path, dpi)
            pages = 0

            for index, info in enumerate(images, 1):
                if cancel_event is not None and cancel_event.is_set():
                    raise CancelledError("已取消")
                name = decode_zip_name(info)
                try:
                    data = archive.read(info)
                    width, height, color_space, stream, is_jpeg = prepare_image(
                        data, jpeg_quality
                    )
                except PillowRequiredError:
                    raise
                except Exception as exc:
                    skipped.append(name)
                    message = f"无法读取图片，已跳过：{name}（{exc}）"
                    if on_warning:
                        on_warning(message)
                    else:
                        print(f"\n  [警告] {message}")
                    if on_progress:
                        on_progress(index, total)
                    continue

                writer.add_page(width, height, color_space, stream, is_jpeg)
                pages += 1

                if on_progress:
                    on_progress(index, total)
                elif tty:
                    now = time.time()
                    if now - last_update > 0.2 or index == total:
                        last_update = now
                        print(f"\r  PDF 进度：{index}/{total}", end="", flush=True)

            if tty:
                print("\r" + " " * 40 + "\r", end="")
            if pages == 0:
                raise DownloadError("所有图片都无法读取，PDF 未生成")

            writer.finish()
            writer = None
            os.replace(temp_path, pdf_path)

        size = pdf_path.stat().st_size
        return pages, size, skipped
    except Exception:
        if writer is not None:
            writer.close()
        temp_path.unlink(missing_ok=True)
        raise


def download_zip(
    http: HttpClient,
    album: Album,
    dest: Path,
    *,
    retries: int = 4,
    timeout: float = 60.0,
    stall_timeout: float = 75.0,
    cancel_event: Optional[threading.Event] = None,
    on_progress: Optional[Callable[[int, Optional[int]], None]] = None,
    log: Callable[[str], None] = print,
) -> int:
    assert album.zip_url
    part = Path(str(dest) + ".part")
    dest.parent.mkdir(parents=True, exist_ok=True)

    last_error: object = None
    for attempt in range(1, retries + 1):
        offset = part.stat().st_size if part.exists() else 0
        headers = {"Accept": "*/*", "Accept-Encoding": "identity"}
        if offset > 0:
            headers["Range"] = f"bytes={offset}-"

        try:
            response = http.open(
                album.zip_url, referer=album.page_url,
                headers=headers, timeout=timeout,
            )
            status = response.status

            if status == 416:  # Range 超出，可能已经下完
                response.close()
                total = None
                content_range = ""
                try:
                    content_range = response.headers.get("Content-Range") or ""
                except Exception:
                    pass
                match = re.search(r"/\s*(\d+)\s*$", content_range)
                if match:
                    total = int(match.group(1))
                if total is not None and part.exists() and part.stat().st_size == total:
                    os.replace(part, dest)
                    if on_progress is not None:
                        on_progress(total, total)
                    return total
                part.unlink(missing_ok=True)
                raise DownloadError("服务器拒绝续传，已清除临时文件，请重试")

            if status == 200:
                offset = 0
                mode = "wb"
            elif status == 206:
                mode = "ab"
            else:
                response.close()
                raise DownloadError(f"下载直链返回 HTTP {status}")

            total: Optional[int] = None
            content_range = response.headers.get("Content-Range") or ""
            match = re.search(r"/\s*(\d+)\s*$", content_range)
            if match:
                total = int(match.group(1))
            elif response.headers.get("Content-Length"):
                total = offset + int(response.headers["Content-Length"])

            content_type = (response.headers.get("Content-Type") or "").lower()
            if "text/html" in content_type:
                snippet = response.read(8192).decode("utf-8", "replace")
                response.close()
                if is_cloudflare_challenge(snippet, None):
                    raise DownloadError(challenge_hint(album.zip_url))
                plain = re.sub(r"<[^>]+>", " ", snippet)
                plain = re.sub(r"\s+", " ", plain).strip()[:180]
                raise DownloadError(
                    "下载直链返回的是网页而不是压缩包，链接可能已失效，"
                    f"或被网站限流。\n  页面内容：{plain}"
                )

            if total is not None and offset >= total > 0:
                response.close()
                if part.exists() and part.stat().st_size == total:
                    os.replace(part, dest)
                    log(f"已下载完整（{human_size(total)}）")
                    if on_progress is not None:
                        on_progress(total, total)
                    return total
                part.unlink(missing_ok=True)
                raise DownloadError("临时文件大小异常，已清除，请重试")

            done = offset
            progress = Progress(total) if on_progress is None else None
            if on_progress is not None:
                on_progress(done, total)

            last_activity = [time.time()]
            stop_watchdog = threading.Event()

            def watchdog() -> None:
                # 有些代理会保持连接但不再发数据，socket 超时不一定触发。
                while not stop_watchdog.wait(2.0):
                    if cancel_event is not None and cancel_event.is_set():
                        try:
                            response.close()
                        except Exception:
                            pass
                        return
                    if time.time() - last_activity[0] > max(5.0, stall_timeout):
                        try:
                            response.close()
                        except Exception:
                            pass
                        return

            watchdog_thread = threading.Thread(
                target=watchdog, name="download-watchdog", daemon=True
            )
            watchdog_thread.start()
            try:
                with open(part, mode) as handle:
                    while True:
                        chunk = response.read(CHUNK_SIZE)
                        last_activity[0] = time.time()
                        if not chunk:
                            break
                        handle.write(chunk)
                        done += len(chunk)
                        if progress is not None:
                            progress.update(done)
                        elif on_progress is not None:
                            on_progress(done, total)
            finally:
                stop_watchdog.set()
            response.close()
            if cancel_event is not None and cancel_event.is_set():
                raise CancelledError("已取消")
            if progress is not None:
                progress.finish(done, total)
            elif on_progress is not None:
                on_progress(done, total)

            size = part.stat().st_size
            if total is not None and size != total:
                raise IncompleteDownloadError(
                    f"下载不完整：{size}/{total} 字节"
                )

            os.replace(part, dest)
            ok, count = verify_zip(dest)
            if not ok:
                dest.unlink(missing_ok=True)
                raise DownloadError("ZIP 校验失败（文件可能不完整），已删除，请重试")
            log(f"已校验：ZIP 内共 {count} 个文件")
            return total or size

        except DownloadError as exc:
            if cancel_event is not None and cancel_event.is_set():
                raise CancelledError("已取消") from None
            if isinstance(exc, IncompleteDownloadError) and attempt < retries:
                last_error = exc
                wait = min(2 * attempt, 10)
                log(f"下载中断（{exc}），{wait}s 后续传…")
                time.sleep(wait)
                continue
            raise
        except urllib.error.HTTPError as exc:
            if cancel_event is not None and cancel_event.is_set():
                raise CancelledError("已取消") from None
            if exc.code in (403, 404, 410):
                raise LinkDeadError(
                    f"下载直链返回 HTTP {exc.code}（备用线路上的文件可能缺失）"
                ) from None
            last_error = exc
            if attempt < retries:
                wait = min(2 * attempt, 10)
                log(f"第 {attempt} 次下载中断（{exc}），{wait}s 后续传…")
                time.sleep(wait)
        except (urllib.error.URLError, TimeoutError,
                ConnectionError, OSError, ValueError,
                http.client.HTTPException) as exc:
            if cancel_event is not None and cancel_event.is_set():
                raise CancelledError("已取消") from None
            last_error = exc
            if attempt < retries:
                wait = min(2 * attempt, 10)
                log(f"第 {attempt} 次下载中断（{exc}），{wait}s 后续传…")
                time.sleep(wait)

    raise DownloadError(f"下载失败（已重试 {retries} 次）：{last_error}")


# ---------------------------------------------------------------------------
# 命令行
# ---------------------------------------------------------------------------

def convert_local_zips(
    paths: Iterable[str],
    overwrite: bool = False,
    dpi: float = DEFAULT_PDF_DPI,
    quality: int = DEFAULT_PDF_QUALITY,
) -> int:
    """离线模式：把本地 ZIP（或目录里的 ZIP）转换成同名 PDF。"""
    files: list[Path] = []
    for raw in paths:
        path = Path(raw).expanduser()
        if path.is_dir():
            files.extend(sorted(path.glob("*.zip")))
        elif path.is_file():
            files.append(path)
        else:
            print(f"[错误] 找不到：{path}", file=sys.stderr)

    if not files:
        print("[错误] 没有找到可转换的 ZIP 文件", file=sys.stderr)
        return 1

    print(f"本地 ZIP → PDF 转换（共 {len(files)} 个文件）")
    print()

    ok = skipped = failed = 0
    for index, zip_path in enumerate(files, 1):
        print(f"[{index}/{len(files)}] {zip_path}")
        try:
            valid, _ = verify_zip(zip_path)
            if not valid:
                raise DownloadError("不是有效的 ZIP 文件")

            pdf_path = zip_path.with_suffix(".pdf")
            if pdf_path.exists() and not overwrite and verify_pdf(pdf_path):
                print(f"  [跳过] PDF 已存在：{pdf_path}\n")
                skipped += 1
                continue

            pages, size, skipped_images = build_pdf_from_zip(
                zip_path, pdf_path, dpi, quality
            )
            print(
                f"  [成功] PDF：{pdf_path}"
                f"（{pages} 页，{human_size(size)}）"
            )
            if skipped_images:
                print(f"  [提示] 有 {len(skipped_images)} 张图片无法读取，已跳过")
            print()
            ok += 1
        except KeyboardInterrupt:
            print("\n已取消", file=sys.stderr)
            return 130
        except DownloadError as exc:
            print(f"  [失败] {exc}\n", file=sys.stderr)
            failed += 1
        except Exception as exc:
            print(f"  [异常] {type(exc).__name__}: {exc}\n", file=sys.stderr)
            failed += 1

    print("=" * 50)
    print(f"全部结束：成功 {ok}，跳过 {skipped}，失败 {failed}")
    return 0 if failed == 0 else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="wnacg 漫画下载器（下载 ZIP 压缩包并自动生成 PDF）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "示例：\n"
            "  python wnacg_dl.py https://www.wnacg.com/photos-index-aid-383877.html\n"
            "  python wnacg_dl.py -o D:\\manga 383877 383000\n"
            "  python wnacg_dl.py -i urls.txt --proxy http://127.0.0.1:7890\n"
        ),
    )
    parser.add_argument("urls", nargs="*", help="作品链接（可多个，也可直接写 aid 数字）")
    parser.add_argument("-i", "--input", metavar="文件",
                        help="从文本文件读取链接，一行一个，# 开头为注释")
    parser.add_argument("-o", "--output", default="downloads", metavar="目录",
                        help="保存目录（默认 ./downloads）")
    parser.add_argument("--proxy", metavar="URL",
                        help="代理地址，如 http://127.0.0.1:7890（默认自动读取系统代理）")
    parser.add_argument("--no-proxy", action="store_true", help="强制直连，不使用代理")
    parser.add_argument("--direct", action="store_true",
                        help="DoH 直连模式：用 doh.pub 解析真实 IP，无需代理")
    parser.add_argument("--cookie", default="", metavar="字符串",
                        help="额外的 Cookie，例如 \"cf_clearance=...\"（应对 Cloudflare 验证）")
    parser.add_argument("--user-agent", default=DEFAULT_UA, metavar="UA",
                        help="自定义 User-Agent（配合 cf_clearance 时需要与浏览器一致）")
    parser.add_argument("--timeout", type=float, default=60, metavar="秒",
                        help="单次网络超时（默认 60）")
    parser.add_argument("--retries", type=int, default=4, metavar="次数",
                        help="下载重试次数（默认 4，支持断点续传）")
    parser.add_argument("--overwrite", action="store_true",
                        help="覆盖已存在的 ZIP / PDF 文件")
    parser.add_argument("--no-pdf", action="store_true",
                        help="只下载 ZIP，不生成 PDF")
    parser.add_argument("--pdf-dpi", type=float, default=DEFAULT_PDF_DPI, metavar="DPI",
                        help="PDF 页面按多少 DPI 换算尺寸（默认 300，最高；不影响图片像素）")
    parser.add_argument("--pdf-quality", type=int, default=DEFAULT_PDF_QUALITY, metavar="质量",
                        help="非 JPEG 图片转 PDF 时的 JPEG 质量（默认 100，最高）")
    parser.add_argument("--from-zip", nargs="+", metavar="ZIP",
                        help="离线模式：不联网，直接把本地 ZIP 或目录转成 PDF")
    parser.add_argument("--dry-run", action="store_true",
                        help="只解析并显示直链，不下载、不生成 PDF")
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    return parser


def collect_inputs(args: argparse.Namespace) -> list[str]:
    items: list[str] = list(args.urls)
    if args.input:
        path = Path(args.input).expanduser()
        try:
            content = path.read_text(encoding="utf-8-sig")
        except OSError as exc:
            raise DownloadError(f"读取链接文件失败：{exc}") from None
        for line in content.splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                items.append(line)

    seen = set()
    result = []
    for item in items:
        if item not in seen:
            seen.add(item)
            result.append(item)
    return result


def main(argv: Optional[Iterable[str]] = None) -> int:
    setup_console()
    parser = build_parser()
    args = parser.parse_args(list(argv) if argv is not None else None)

    if args.from_zip:
        if args.no_pdf:
            parser.error("--from-zip 与 --no-pdf 不能同时使用")
        if args.urls or args.input:
            parser.error("--from-zip 不能和作品链接同时使用")
        return convert_local_zips(
            args.from_zip,
            overwrite=args.overwrite,
            dpi=args.pdf_dpi,
            quality=args.pdf_quality,
        )

    try:
        inputs = collect_inputs(args)
    except DownloadError as exc:
        print(f"[错误] {exc}", file=sys.stderr)
        return 1

    if not inputs:
        parser.error("请至少提供一个作品链接，或使用 -i 指定链接文件")

    direct = bool(args.direct)
    proxy = None
    if not direct and not args.no_proxy:
        proxy = args.proxy or detect_system_proxy()

    output_dir = Path(args.output).expanduser()
    try:
        output_dir.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        print(f"[错误] 无法创建保存目录 {output_dir}：{exc}", file=sys.stderr)
        return 1

    http = HttpClient(
        proxy=proxy,
        cookie=args.cookie,
        user_agent=args.user_agent,
        timeout=args.timeout,
        direct=direct,
    )

    print(f"wnacg 下载器 v{__version__}")
    print(f"保存目录：{output_dir.resolve()}")
    if direct:
        print("网络：直连（DoH 解析真实 IP）")
    else:
        print(f"网络代理：{proxy or '不使用（直连）'}")
    if args.cookie:
        print("Cookie：已设置")
    print()

    ok = skipped = failed = 0
    for index, item in enumerate(inputs, 1):
        print(f"[{index}/{len(inputs)}] {item}")
        try:
            target = resolve_target(item, http)
            album = fetch_album(http, target)
            size, status = probe_size(http, album.zip_url or "", album.page_url)
            print(f"  标题：{album.title or '（未获取到）'}")
            print(f"  文件：{album.filename}（{human_size(size)}）")
            print(f"  直链：{album.zip_url}")

            if is_dead_status(status):
                album = switch_to_worker(http, album, status)
                size, status = probe_size(http, album.zip_url or "", album.page_url)
                print(f"  文件：{album.filename}（{human_size(size)}）")
                print(f"  直链：{album.zip_url}")
                if is_dead_status(status):
                    raise DownloadError(
                        f"Server 1 的新直链也不可用（HTTP {status}），请稍后重试。"
                    )

            dest = output_dir / album.filename
            if args.dry_run:
                print(f"  ZIP：{dest}")
                if not args.no_pdf:
                    print(f"  PDF：{dest.with_suffix('.pdf')}")
                print("  [dry-run] 未下载、未生成 PDF\n")
                ok += 1
                continue

            zip_skipped = False
            if dest.exists() and not args.overwrite:
                valid, count = verify_zip(dest)
                if valid:
                    print(f"  [跳过] ZIP 已存在且校验通过：{dest}（{count} 个文件）")
                    zip_skipped = True
                else:
                    print("  [注意] 同名 ZIP 无效，将重新下载")

            if not zip_skipped:
                if args.overwrite:
                    Path(str(dest) + ".part").unlink(missing_ok=True)
                try:
                    download_zip(
                        http, album, dest,
                        retries=max(1, args.retries), timeout=args.timeout,
                    )
                except LinkDeadError as exc:
                    print(f"  {exc}")
                    album = switch_to_worker(http, album)
                    download_zip(
                        http, album, dest,
                        retries=max(1, args.retries), timeout=args.timeout,
                    )
                print(f"  [成功] ZIP：{dest}")

            pdf_path = dest.with_suffix(".pdf")
            pdf_skipped = False
            if args.no_pdf:
                print("  [跳过] 已指定 --no-pdf，不生成 PDF")
            elif pdf_path.exists() and not args.overwrite and verify_pdf(pdf_path):
                print(f"  [跳过] PDF 已存在：{pdf_path}")
                pdf_skipped = True
            else:
                if pdf_path.exists() and not args.overwrite:
                    print("  [注意] 同名 PDF 无效，将重新生成")
                try:
                    pages, pdf_size, skipped_images = build_pdf_from_zip(
                        dest, pdf_path, args.pdf_dpi, args.pdf_quality
                    )
                except DownloadError as exc:
                    raise DownloadError(
                        f"ZIP 已保存，但 PDF 生成失败：{exc}"
                    ) from None
                print(
                    f"  [成功] PDF：{pdf_path}"
                    f"（{pages} 页，{human_size(pdf_size)}）"
                )
                if skipped_images:
                    print(f"  [提示] 有 {len(skipped_images)} 张图片无法读取，已跳过")

            if zip_skipped and (pdf_skipped or args.no_pdf):
                skipped += 1
            else:
                ok += 1
            print()

        except KeyboardInterrupt:
            print("\n已取消（未完成的 .part 文件会保留，下次可续传）", file=sys.stderr)
            return 130
        except DownloadError as exc:
            print(f"  [失败] {exc}\n", file=sys.stderr)
            failed += 1
        except Exception as exc:  # 防止单个链接的意外错误中断整批
            print(f"  [异常] {type(exc).__name__}: {exc}\n", file=sys.stderr)
            failed += 1

    print("=" * 50)
    print(f"全部结束：成功 {ok}，跳过 {skipped}，失败 {failed}")
    print(f"文件位置：{output_dir.resolve()}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
