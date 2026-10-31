#!/usr/bin/env python3
"""从浏览器导出的 HTML 书签里提取 wnacg 作品，批量下载并输出成功/失败清单。

用法：
    python batch_bookmarks.py bookmarks.html
    python batch_bookmarks.py bookmarks.html -o downloads --direct
    python batch_bookmarks.py bookmarks.html --no-pdf --overwrite
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from datetime import datetime
from html.parser import HTMLParser
from pathlib import Path
from typing import Iterable, Optional
from urllib.parse import urljoin, urlparse

import wnacg_dl as core

AID_RE = re.compile(r"(?:photos-index|photos-slide|photos-view|download-index)-aid-(\d+)")
ANY_AID_RE = re.compile(r"aid-(\d+)")


@dataclass
class Bookmark:
    aid: str
    url: str


@dataclass
class Result:
    aid: str
    url: str
    title: str = ""
    status: str = "失败"
    message: str = ""
    zip_path: Optional[Path] = None
    pdf_path: Optional[Path] = None


class BookmarkParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.hrefs: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, Optional[str]]]) -> None:
        if tag.lower() != "a":
            return
        for key, value in attrs:
            if key.lower() == "href" and value:
                self.hrefs.append(value.strip())
                break


def parse_bookmarks(paths: Iterable[Path]) -> list[Bookmark]:
    found: list[Bookmark] = []
    seen: set[str] = set()
    for path in paths:
        try:
            text = path.read_text(encoding="utf-8-sig", errors="replace")
        except OSError as exc:
            raise core.DownloadError(f"读取书签文件失败：{path}：{exc}") from None
        parser = BookmarkParser()
        parser.feed(text)

        for raw in parser.hrefs:
            url = urljoin("https://www.wnacg.com/", raw)
            parsed = urlparse(url)
            host = (parsed.hostname or "").lower()
            if host not in {"wnacg.com", "www.wnacg.com"}:
                continue
            match = AID_RE.search(parsed.path) or ANY_AID_RE.search(parsed.path)
            if not match:
                continue
            aid = match.group(1)
            if aid in seen:
                continue
            seen.add(aid)
            found.append(Bookmark(
                aid=aid,
                url=f"https://www.wnacg.com/photos-index-aid-{aid}.html",
            ))
    return found


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="解析浏览器 HTML 书签，批量下载其中的 wnacg 作品",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("bookmarks", nargs="+", metavar="HTML", help="书签导出文件（可多个）")
    parser.add_argument("-o", "--output", default="downloads", metavar="目录",
                        help="保存目录（默认 downloads）")
    parser.add_argument("--proxy", metavar="URL",
                        help="代理地址，例如 http://127.0.0.1:7890")
    parser.add_argument("--no-proxy", action="store_true", help="强制直连，不使用代理")
    parser.add_argument("--direct", action="store_true",
                        help="DoH 直连模式（无需代理）")
    parser.add_argument("--cookie", default="", metavar="字符串",
                        help="额外 Cookie，例如 cf_clearance=...")
    parser.add_argument("--user-agent", default=core.DEFAULT_UA, metavar="UA")
    parser.add_argument("--timeout", type=float, default=60, metavar="秒")
    parser.add_argument("--retries", type=int, default=4, metavar="次数")
    parser.add_argument("--no-pdf", action="store_true", help="只下载 ZIP，不生成 PDF")
    parser.add_argument("--overwrite", action="store_true", help="覆盖已有文件")
    parser.add_argument("--pdf-dpi", type=float, default=core.DEFAULT_PDF_DPI)
    parser.add_argument("--pdf-quality", type=int, default=core.DEFAULT_PDF_QUALITY)
    parser.add_argument("--limit", type=int, default=0, metavar="N",
                        help="最多处理 N 个（0 表示全部）")
    parser.add_argument("--start", type=int, default=1, metavar="N",
                        help="从第 N 个开始（默认 1）")
    parser.add_argument("--report", metavar="文件",
                        help="报告保存路径（默认 输出目录/batch_report.txt）")
    parser.add_argument("--dry-run", action="store_true", help="只解析，不下载")
    return parser


def download_one(http: core.HttpClient, bookmark: Bookmark, args: argparse.Namespace,
                 output_dir: Path) -> Result:
    result = Result(aid=bookmark.aid, url=bookmark.url)
    target = core.resolve_target(bookmark.aid, http)
    album = core.fetch_album(http, target)
    result.title = album.title or ""

    size, status = core.probe_size(http, album.zip_url or "", album.page_url)
    print(f"  标题：{album.title or '（未获取到）'}")
    print(f"  文件：{album.filename}（{core.human_size(size)}）")

    if core.is_dead_status(status):
        album = core.switch_to_worker(http, album, status)
        size, status = core.probe_size(http, album.zip_url or "", album.page_url)
        if core.is_dead_status(status):
            raise core.DownloadError(
                f"Server 1 直链不可用（HTTP {status}），请稍后重试"
            )

    dest = output_dir / album.filename
    if args.dry_run:
        print(f"  ZIP：{dest}")
        if not args.no_pdf:
            print(f"  PDF：{dest.with_suffix('.pdf')}")
        print("  [dry-run] 未下载")
        result.status = "跳过"
        result.message = "dry-run"
        return result

    zip_skipped = False
    if dest.exists() and not args.overwrite:
        valid, count = core.verify_zip(dest)
        if valid:
            print(f"  [跳过] ZIP 已存在且有效（{count} 个文件）")
            zip_skipped = True
        else:
            print("  [注意] 同名 ZIP 无效，将重新下载")

    if not zip_skipped:
        if args.overwrite:
            Path(str(dest) + ".part").unlink(missing_ok=True)
        try:
            core.download_zip(
                http, album, dest,
                retries=max(1, args.retries), timeout=args.timeout,
            )
        except core.LinkDeadError:
            album = core.switch_to_worker(http, album)
            core.download_zip(
                http, album, dest,
                retries=max(1, args.retries), timeout=args.timeout,
            )
        print(f"  [成功] ZIP：{dest}")
    result.zip_path = dest

    pdf_path = dest.with_suffix(".pdf")
    if args.no_pdf:
        print("  [跳过] 未生成 PDF（--no-pdf）")
    elif pdf_path.exists() and not args.overwrite and core.verify_pdf(pdf_path):
        print(f"  [跳过] PDF 已存在：{pdf_path}")
    else:
        if pdf_path.exists() and not args.overwrite:
            print("  [注意] 同名 PDF 无效，将重新生成")
        pages, pdf_size, skipped = core.build_pdf_from_zip(
            dest, pdf_path, args.pdf_dpi, args.pdf_quality
        )
        print(f"  [成功] PDF：{pdf_path}（{pages} 页，{core.human_size(pdf_size)}）")
        if skipped:
            print(f"  [提示] {len(skipped)} 张图片无法读取，已跳过")
    result.pdf_path = pdf_path if pdf_path.exists() else None

    if zip_skipped and (args.no_pdf or pdf_path.exists()):
        result.status = "跳过"
        result.message = "文件已存在"
    else:
        result.status = "成功"
    return result


def write_report(path: Path, results: list[Result], output_dir: Path) -> None:
    successes = [r for r in results if r.status == "成功"]
    skipped = [r for r in results if r.status == "跳过"]
    failures = [r for r in results if r.status == "失败"]
    lines = [
        "wnacg 书签批量下载报告",
        f"时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        f"输出目录：{output_dir.resolve()}",
        f"成功 {len(successes)}，跳过 {len(skipped)}，失败 {len(failures)}",
        "",
        f"== 成功（{len(successes)}）==",
    ]
    for item in successes:
        lines.append(f"[{item.aid}] {item.title}")
        if item.zip_path:
            lines.append(f"  ZIP: {item.zip_path}")
        if item.pdf_path:
            lines.append(f"  PDF: {item.pdf_path}")
    lines.append("")
    lines.append(f"== 跳过（{len(skipped)}）==")
    for item in skipped:
        lines.append(f"[{item.aid}] {item.title} - {item.message}")
    lines.append("")
    lines.append(f"== 失败（{len(failures)}）==")
    for item in failures:
        lines.append(f"[{item.aid}] {item.title or item.url}")
        lines.append(f"  {item.message}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main(argv: Optional[list[str]] = None) -> int:
    core.setup_console()
    args = build_parser().parse_args(argv)

    paths = [Path(p).expanduser() for p in args.bookmarks]
    try:
        bookmarks = parse_bookmarks(paths)
    except core.DownloadError as exc:
        print(f"[错误] {exc}", file=sys.stderr)
        return 1

    if not bookmarks:
        print("[错误] 书签里没有找到 wnacg 作品链接", file=sys.stderr)
        return 1

    start = max(0, args.start - 1)
    selected = bookmarks[start:]
    if args.limit > 0:
        selected = selected[: args.limit]
    if not selected:
        print("[错误] 指定的范围里没有作品", file=sys.stderr)
        return 1

    output_dir = Path(args.output).expanduser()
    try:
        output_dir.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        print(f"[错误] 无法创建输出目录：{exc}", file=sys.stderr)
        return 1

    proxy = None
    if not args.direct and not args.no_proxy:
        proxy = args.proxy or core.detect_system_proxy()
    http = core.HttpClient(
        proxy=proxy,
        cookie=args.cookie,
        user_agent=args.user_agent,
        timeout=args.timeout,
        direct=args.direct,
    )

    print(f"从书签解析到 {len(bookmarks)} 个作品，本次处理 {len(selected)} 个")
    print(f"输出目录：{output_dir.resolve()}")
    print(f"网络：{'DoH 直连' if args.direct else (proxy or '直连/系统网络')}")
    print()

    results: list[Result] = []
    interrupted = False
    for index, bookmark in enumerate(selected, 1):
        print(f"[{index}/{len(selected)}] aid {bookmark.aid}")
        try:
            result = download_one(http, bookmark, args, output_dir)
        except KeyboardInterrupt:
            print("\n[中断] 已停止，正在保存报告…", file=sys.stderr)
            interrupted = True
            break
        except core.DownloadError as exc:
            result = Result(
                aid=bookmark.aid, url=bookmark.url,
                status="失败", message=str(exc),
            )
            print(f"  [失败] {exc}", file=sys.stderr)
        except Exception as exc:  # 单个作品异常不中断整批
            result = Result(
                aid=bookmark.aid, url=bookmark.url,
                status="失败", message=f"{type(exc).__name__}: {exc}",
            )
            print(f"  [异常] {result.message}", file=sys.stderr)
        results.append(result)
        print()

    report_path = Path(args.report).expanduser() if args.report else output_dir / "batch_report.txt"
    write_report(report_path, results, output_dir)

    successes = [r for r in results if r.status == "成功"]
    skipped = [r for r in results if r.status == "跳过"]
    failures = [r for r in results if r.status == "失败"]

    print("=" * 60)
    print(f"完成：成功 {len(successes)}，跳过 {len(skipped)}，失败 {len(failures)}")
    if successes:
        print("\n成功：")
        for item in successes:
            print(f"  [{item.aid}] {item.title}")
    if skipped:
        print("\n跳过：")
        for item in skipped:
            print(f"  [{item.aid}] {item.title} - {item.message}")
    if failures:
        print("\n失败：")
        for item in failures:
            print(f"  [{item.aid}] {item.message}")
    print(f"\n报告：{report_path.resolve()}")
    if interrupted:
        return 130
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
