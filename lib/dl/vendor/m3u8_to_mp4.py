#!/usr/bin/env python3

import argparse
import os
import shutil
import subprocess
import sys
import urllib.parse
from typing import List, Optional


def load_netscape_cookies(cookie_file: str) -> str:
    cookies: List[str] = []

    with open(cookie_file, "r", encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue

            parts = line.split("\t")
            if len(parts) < 7:
                continue

            name = parts[5].strip()
            value = parts[6].strip()
            if not name:
                continue
            cookies.append(f"{name}={value}")

    return "; ".join(cookies)


def sanitize_filename(name: str) -> str:
    allowed = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.() ")
    cleaned = "".join(ch if ch in allowed else "_" for ch in name).strip()
    cleaned = "_".join(cleaned.split())
    return cleaned or "output"


def derive_output_path(m3u8_url: str, output_dir: Optional[str]) -> str:
    parsed = urllib.parse.urlparse(m3u8_url)
    base = os.path.basename(parsed.path.rstrip("/"))

    if not base:
        base = "output"
    if base.lower().endswith(".m3u8"):
        base = base[: -len(".m3u8")]

    filename = sanitize_filename(base) + ".mp4"
    if output_dir:
        return os.path.join(output_dir, filename)
    return filename


def default_safari_user_agent() -> str:
    return (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/605.1.15 (KHTML, like Gecko) "
        "Version/17.0 Safari/605.1.15"
    )


def mask_header_value(header_line: str) -> str:
    if header_line.lower().startswith("cookie:"):
        return "Cookie: <redacted>"
    return header_line


def printable_command(cmd: List[str], redact_headers: bool) -> str:
    out: List[str] = []
    i = 0
    while i < len(cmd):
        part = cmd[i]
        if redact_headers and part == "-headers" and i + 1 < len(cmd):
            header_blob = cmd[i + 1]
            lines = [ln for ln in header_blob.split("\r\n") if ln]
            masked = [mask_header_value(ln) for ln in lines]
            out.append("-headers")
            out.append("\\r\\n".join(masked) + "\\r\\n")
            i += 2
            continue

        if any(ch in part for ch in (" ", "\t", "\n", "\r", "\"")):
            out.append("'" + part.replace("'", "'\\''") + "'")
        else:
            out.append(part)
        i += 1
    return " ".join(out)


def ensure_header(headers: List[str], name: str, value: str) -> None:
    needle = name.strip().lower() + ":"
    for h in headers:
        if h.strip().lower().startswith(needle):
            return
    headers.append(f"{name}: {value}")


def derive_origin_from_referer(referer: Optional[str]) -> Optional[str]:
    if not referer:
        return None
    parsed = urllib.parse.urlparse(referer)
    if not parsed.scheme or not parsed.netloc:
        return None
    return f"{parsed.scheme}://{parsed.netloc}"


def build_ffmpeg_command(
    m3u8_url: str,
    output_path: str,
    headers: List[str],
    user_agent: Optional[str],
    referer: Optional[str],
    origin: Optional[str],
    cookie: Optional[str],
    ffmpeg_loglevel: str,
    stats: bool,
    overwrite: bool,
) -> List[str]:
    cmd = ["ffmpeg"]

    if overwrite:
        cmd.append("-y")
    else:
        cmd.append("-n")

    cmd += ["-hide_banner", "-loglevel", ffmpeg_loglevel]
    if stats:
        cmd.append("-stats")

    # Add HTTP headers.
    all_headers: List[str] = []
    if user_agent:
        all_headers.append(f"User-Agent: {user_agent}")
    if referer:
        all_headers.append(f"Referer: {referer}")
    if origin:
        all_headers.append(f"Origin: {origin}")
    if cookie:
        all_headers.append(f"Cookie: {cookie}")
    all_headers.extend(headers)

    if all_headers:
        # ffmpeg expects a single string with CRLF-separated headers.
        header_value = "\r\n".join(all_headers) + "\r\n"
        cmd += ["-headers", header_value]

    # Input.
    cmd += ["-i", m3u8_url]

    # Output.
    # -c copy avoids re-encoding and is usually fast.
    # -bsf:a aac_adtstoasc helps when the stream is HLS with AAC in ADTS.
    cmd += ["-c", "copy", "-bsf:a", "aac_adtstoasc", output_path]

    return cmd


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Download an HLS (.m3u8) stream to an MP4 file using ffmpeg.")
    parser.add_argument("m3u8_url", help="The HLS playlist URL (http(s)://.../index.m3u8)")
    parser.add_argument(
        "-o",
        "--output",
        default=None,
        help="Output MP4 path (default: derived from m3u8 URL)",
    )
    parser.add_argument(
        "--output-dir",
        default=None,
        help="Output directory (default: current directory)",
    )
    parser.add_argument(
        "--header",
        action="append",
        default=[],
        help='Additional HTTP header, e.g. --header "Cookie: a=b" (repeatable)',
    )
    parser.add_argument("--user-agent", default=None, help="Set User-Agent header")
    parser.add_argument("--referer", default=None, help="Set Referer header")
    parser.add_argument("--origin", default=None, help="Set Origin header")
    parser.add_argument(
        "--safari",
        action="store_true",
        default=True,
        help="Use a Safari-like default User-Agent if --user-agent is not provided (default: enabled)",
    )
    parser.add_argument(
        "--no-safari",
        action="store_false",
        dest="safari",
        help="Disable Safari-like defaults",
    )
    parser.add_argument(
        "--cookie",
        default=None,
        help="Set Cookie header value, e.g. \"a=b; c=d\"",
    )
    parser.add_argument(
        "--cookie-file",
        default=None,
        help="Load cookies from a Netscape-format cookie file and send as Cookie header",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite output file if it already exists",
    )
    parser.add_argument(
        "--ffmpeg-loglevel",
        default="error",
        help="ffmpeg loglevel (default: error). Examples: warning, info, verbose",
    )
    parser.add_argument(
        "--stats",
        action="store_true",
        default=True,
        help="Show ffmpeg progress stats (frame/time/bitrate) (default: enabled).",
    )
    parser.add_argument(
        "--no-stats",
        action="store_false",
        dest="stats",
        help="Disable ffmpeg progress stats",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        default=True,
        help="Print diagnostic output (default: enabled)",
    )
    parser.add_argument(
        "--quiet",
        action="store_false",
        dest="verbose",
        help="Disable diagnostic output",
    )

    args = parser.parse_args()

    if shutil.which("ffmpeg") is None:
        print("ffmpeg not found in PATH.", file=sys.stderr)
        print("Install ffmpeg and try again.", file=sys.stderr)
        return 2

    if args.user_agent is None and args.safari:
        args.user_agent = default_safari_user_agent()

    if args.origin is None:
        args.origin = derive_origin_from_referer(args.referer)

    output_path = args.output or derive_output_path(args.m3u8_url, args.output_dir)

    # Ensure the output directory exists.
    out_dir = os.path.dirname(output_path)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    cookie_value = args.cookie
    if args.cookie_file:
        try:
            cookie_value = load_netscape_cookies(args.cookie_file)
        except OSError as exc:
            print(f"Failed to read cookie file: {exc}", file=sys.stderr)
            return 2

    extra_headers = list(args.header)

    if args.safari:
        ensure_header(extra_headers, "Accept", "*/*")
        ensure_header(extra_headers, "Accept-Language", "en-US,en;q=0.9")
        ensure_header(extra_headers, "Accept-Encoding", "gzip, deflate, br")
        ensure_header(extra_headers, "Connection", "keep-alive")

    cmd = build_ffmpeg_command(
        m3u8_url=args.m3u8_url,
        output_path=output_path,
        headers=extra_headers,
        user_agent=args.user_agent,
        referer=args.referer,
        origin=args.origin,
        cookie=cookie_value,
        ffmpeg_loglevel=args.ffmpeg_loglevel,
        stats=args.stats,
        overwrite=args.overwrite,
    )

    if args.verbose:
        print(f"Input m3u8: {args.m3u8_url}")
        print(f"Output path: {output_path}")
        if not (args.user_agent or args.referer or args.origin or cookie_value or extra_headers):
            print("No HTTP headers are being sent.")
        if not args.stats and args.ffmpeg_loglevel == "error":
            print("Progress output is suppressed. Use --stats and/or --ffmpeg-loglevel info to see progress.")
        print("ffmpeg command (headers redacted):")
        print(printable_command(cmd, redact_headers=True))

    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError as exc:
        print(f"ffmpeg failed with exit code {exc.returncode}.", file=sys.stderr)
        return exc.returncode

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
