#!/usr/bin/env python3
"""
B站多P视频下载器（纯标准库 + ffmpeg）

为什么不用 yt-dlp：站点对视频页 HTML 做了风控（HTTP 412），
yt-dlp 的 bilibili 提取器走的就是那条路。这里直接走仍然可用的
player API（pagelist + playurl），拿 DASH 流后用 ffmpeg 合并。

用法:
    python3 bili_dl.py BV1AJ411J7W6
    python3 bili_dl.py BV1AJ411J7W6 -p 1-10,20 -o ~/Videos/N3
    python3 bili_dl.py <完整URL> --cookies ck.txt      # 登录后可下高清
    python3 bili_dl.py BV1AJ411J7W6 --list             # 只列分P，不下载
"""

import argparse
import http.cookiejar
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
API = "https://api.bilibili.com"

# 画质 id -> 名称（playurl 的 qn / dash video id）
QUALITY = {
    127: "8K", 126: "杜比视界", 125: "HDR", 120: "4K", 116: "1080P60",
    112: "1080P+", 80: "1080P", 74: "720P60", 64: "720P", 32: "480P", 16: "360P",
}
# 编码偏好：avc 兼容性最好，hev/av1 体积小但老播放器可能不支持
CODEC_ORDER = {"avc": 0, "hev": 1, "av0": 2}


# ---------------------------------------------------------------- HTTP 基础

class Http:
    def __init__(self, cookie_file=None):
        self.jar = http.cookiejar.MozillaCookieJar()
        if cookie_file:
            self.jar.load(cookie_file, ignore_discard=True, ignore_expires=True)
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self.jar))
        self.logged_in = any(c.name == "SESSDATA" for c in self.jar)

    def _headers(self, referer):
        return {
            "User-Agent": UA,
            "Referer": referer,
            "Accept-Language": "zh-CN,zh;q=0.9",
        }

    def open(self, url, referer="https://www.bilibili.com/", extra=None, retries=4):
        """返回打开的 response；失败重试（指数退避）。"""
        headers = self._headers(referer)
        if extra:
            headers.update(extra)
        last = None
        for attempt in range(retries):
            req = urllib.request.Request(url, headers=headers)
            try:
                return self.opener.open(req, timeout=60)
            except (urllib.error.HTTPError, urllib.error.URLError, OSError) as e:
                # 416 = Range 越界，说明已下完，交给调用方处理
                if isinstance(e, urllib.error.HTTPError) and e.code == 416:
                    raise
                last = e
                if attempt < retries - 1:
                    time.sleep(2 ** attempt)
        raise last

    def json(self, url, referer="https://www.bilibili.com/"):
        with self.open(url, referer, {"Accept": "application/json, text/plain, */*"}) as r:
            data = json.loads(r.read().decode("utf-8"))
        if data.get("code") != 0:
            raise RuntimeError(f"API 返回 code={data.get('code')}: {data.get('message')}")
        return data["data"]

    def bootstrap(self):
        """访问首页拿 buvid3/b_nut，缺了这些接口会被风控拦。"""
        if any(c.name == "buvid3" for c in self.jar):
            return
        try:
            with self.open("https://www.bilibili.com/") as r:
                r.read(1024)
        except Exception as e:
            print(f"  ! 预热 cookie 失败（继续尝试）: {e}", file=sys.stderr)


# ---------------------------------------------------------------- 业务逻辑

def parse_bvid(s):
    m = re.search(r"(BV[0-9A-Za-z]{10})", s)
    if not m:
        raise SystemExit(f"无法从 {s!r} 中识别 BV 号")
    return m.group(1)


def parse_pages(spec, total):
    """'1-10,20,25-' -> 有序去重的页码列表。"""
    if not spec:
        return list(range(1, total + 1))
    out = []
    for chunk in spec.split(","):
        chunk = chunk.strip()
        if not chunk:
            continue
        if "-" in chunk:
            a, _, b = chunk.partition("-")
            start = int(a) if a.strip() else 1
            end = int(b) if b.strip() else total
            out.extend(range(start, end + 1))
        else:
            out.append(int(chunk))
    seen, res = set(), []
    for p in out:
        if 1 <= p <= total and p not in seen:
            seen.add(p)
            res.append(p)
    return res


def safe_name(s, maxlen=120):
    # 有些 UP 直接拿原始文件名当分P标题（如 "studio_video_123.mp4"），
    # 不剥掉结尾的扩展名就会生成 "xxx.mp4.mp4"。
    s = re.sub(r'\.(mp4|flv|mkv|mov|m4v|avi|wmv|webm|ts)$', '', s, flags=re.I)
    s = re.sub(r'[/\\:*?"<>|\x00-\x1f]', "_", s).strip(" .")
    return (s[:maxlen] or "untitled")


def pick_streams(dash, want_codec, max_quality):
    """从 DASH 里选一路视频 + 一路音频。"""
    videos = [v for v in dash.get("video") or []
              if max_quality is None or v["id"] <= max_quality]
    if not videos:
        raise RuntimeError("没有符合条件的视频流")

    def vkey(v):
        codec = (v.get("codecs") or "")[:3]
        pref = CODEC_ORDER.get(codec, 9)
        if want_codec:
            pref = 0 if codec == want_codec else pref + 10
        return (-v["id"], pref, -(v.get("bandwidth") or 0))

    video = sorted(videos, key=vkey)[0]

    audios = list(dash.get("audio") or [])
    # 无损/杜比音轨在单独字段里，有就一并考虑
    for extra_key in ("flac", "dolby"):
        node = dash.get(extra_key) or {}
        found = node.get("audio")
        if isinstance(found, dict):
            audios.append(found)
        elif isinstance(found, list):
            audios.extend(found)
    if not audios:
        raise RuntimeError("没有音频流")
    audio = max(audios, key=lambda a: a.get("bandwidth") or 0)
    return video, audio


def stream_urls(node):
    """baseUrl 优先，backupUrl 作为备用镜像。"""
    urls = [node.get("baseUrl") or node.get("base_url")]
    backup = node.get("backupUrl") or node.get("backup_url") or []
    urls.extend(backup)
    return [u for u in urls if u]


def human(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.1f}{unit}"
        n /= 1024


def download(http_client, urls, dest, referer, label, max_rounds=40, max_stall=6):
    """带断点续传的下载，多轮重试。

    B 站的流 CDN（尤其 PCDN）对顺序下载常限流/断连：一个连接只给几 MB 就断，
    备镜像有时还直接拒连。旧实现把镜像列表只遍历一遍、每个失败就换下一个、
    列表走完就彻底放弃，所以这种 CDN 下很容易整段失败；更隐蔽的是，当某次
    续传恰好把字节数凑够、但中途换的镜像内容和前半段不一致时，字节数检查
    （done<total）发现不了，就会得到能播放却“有声无画/黑屏”的坏视频流。

    改为多轮续传：反复用 Range 从断点往下续，**优先坚持同一个镜像**
    （减少跨镜像拼接导致的内容错位），只有当某镜像这一轮一个字节都没拿到时
    才换下一个；连续 max_stall 轮毫无进展才放弃。最后以字节数是否达到
    Content-Length 作为完成判据。"""
    part = dest + ".part"
    total = None
    mirror = 0
    stall = 0  # 连续“没拿到任何新字节”的轮数

    for _ in range(max_rounds):
        have = os.path.getsize(part) if os.path.exists(part) else 0
        if total is not None and have >= total:
            break

        url = urls[mirror % len(urls)]
        try:
            extra = {"Origin": "https://www.bilibili.com"}
            if have:
                extra["Range"] = f"bytes={have}-"
            try:
                resp = http_client.open(url, referer, extra)
            except urllib.error.HTTPError as e:
                if e.code == 416 and have:      # Range 越界 = 已经下完
                    total = have
                    break
                raise

            with resp:
                # 服务端忽略 Range（返回 200）时要从头写，否则文件会拼错
                if have and resp.status != 206:
                    have = 0
                    mode = "wb"
                else:
                    mode = "ab" if have else "wb"

                total = have + int(resp.headers.get("Content-Length") or 0)
                done = have
                t0 = time.time()
                with open(part, mode) as f:
                    while True:
                        chunk = resp.read(1 << 18)
                        if not chunk:
                            break
                        f.write(chunk)
                        done += len(chunk)
                        if total:
                            pct = done * 100 / total
                            speed = done_rate(done - have, t0)
                            print(f"\r    {label} {pct:5.1f}%  "
                                  f"{human(done)}/{human(total)}  {speed}   ",
                                  end="", file=sys.stderr)
                print(file=sys.stderr)
        except Exception as e:
            print(f"\n    ! 续传中断({e})，重试", file=sys.stderr)

        got = (os.path.getsize(part) if os.path.exists(part) else 0) - have
        if got > 0:
            stall = 0            # 有进展，继续坚持这个镜像
        else:
            stall += 1
            mirror += 1          # 这个镜像不给字节，换下一个
            if stall >= max_stall:
                break

    final = os.path.getsize(part) if os.path.exists(part) else 0
    if total is None or final < total:
        raise RuntimeError(f"{label} 下载失败/不完整: {final}/{total}")
    os.replace(part, dest)


def done_rate(delta, t0):
    el = time.time() - t0
    return f"{human(delta / el)}/s" if el > 0.5 else "--"


def merge(ffmpeg, video, audio, out):
    cmd = [ffmpeg, "-y", "-loglevel", "error",
           "-i", video, "-i", audio,
           "-c", "copy", "-movflags", "+faststart", out]
    subprocess.run(cmd, check=True)


def verify_stream(ffmpeg, path):
    """解码校验流完整性：返回 True 表示没问题。

    PCDN（cosov 等）偶尔会返回字节数对、但 H.264 内容损坏的数据，下出来的
    视频能播却黑屏（有声无画）——光比字节数发现不了（字节数、时长都正常）。
    这里真解一遍码，数 ffmpeg 报的错误行数：容忍开头个别警告（DASH 分片开头
    常有 1~2 条），超过阈值就判损坏。宁可判失败重下，也不要把黑屏文件当成功。"""
    r = subprocess.run([ffmpeg, "-v", "error", "-i", path, "-f", "null", "-"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    errs = [ln for ln in r.stderr.decode("utf-8", "replace").splitlines() if ln.strip()]
    return len(errs) <= 3


# ---------------------------------------------------------------- 主流程

def main():
    ap = argparse.ArgumentParser(
        description="下载 B 站视频（含多P合集）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="示例:\n"
               "  %(prog)s BV1AJ411J7W6 -o ~/Videos/N3\n"
               "  %(prog)s BV1AJ411J7W6 -p 1-10 --codec avc\n"
               "  %(prog)s BV1AJ411J7W6 --cookies ~/bili_cookies.txt   # 高清需登录\n")
    ap.add_argument("url", help="BV 号或视频页 URL")
    ap.add_argument("-o", "--outdir", default=".", help="输出目录（默认当前目录）")
    ap.add_argument("-p", "--pages", help="分P范围，如 1-10,20,30-（默认全部）")
    ap.add_argument("--cookies", help="Netscape 格式 cookie 文件；带 SESSDATA 才能下高清")
    ap.add_argument("-q", "--quality", type=int,
                    help="画质上限 id：80=1080P 64=720P 32=480P 16=360P")
    ap.add_argument("--codec", choices=["avc", "hev", "av0"], default="avc",
                    help="视频编码偏好（默认 avc，兼容性最好）")
    ap.add_argument("--list", action="store_true", help="只列出分P，不下载")
    ap.add_argument("--keep", action="store_true", help="保留合并前的音视频分片")
    ap.add_argument("--sleep", type=float, default=1.0,
                    help="每个分P之间的间隔秒数（默认 1，别调 0 免得被限流）")
    args = ap.parse_args()

    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg and not args.list:
        raise SystemExit("找不到 ffmpeg，请先安装： brew install ffmpeg")

    bvid = parse_bvid(args.url)
    http_client = Http(args.cookies)
    http_client.bootstrap()

    referer = f"https://www.bilibili.com/video/{bvid}"
    pages = http_client.json(f"{API}/x/player/pagelist?bvid={bvid}&jsonp=jsonp", referer)
    total = len(pages)
    print(f"{bvid}: 共 {total} 个分P"
          f"{'（已登录）' if http_client.logged_in else '（未登录，画质上限 480P/720P）'}")

    if args.list:
        for p in pages:
            d = p["duration"]
            print(f"{p['page']:>3}. {p['part']}  ({d // 60}:{d % 60:02d})")
        return

    wanted = parse_pages(args.pages, total)
    if not wanted:
        raise SystemExit("没有选中任何分P")

    os.makedirs(args.outdir, exist_ok=True)
    width = len(str(total))
    ok = skipped = failed = 0

    for i, page_no in enumerate(wanted, 1):
        page = pages[page_no - 1]
        name = f"{page_no:0{width}d}-{safe_name(page['part'])}"
        final = os.path.join(args.outdir, name + ".mp4")
        print(f"\n[{i}/{len(wanted)}] P{page_no} {page['part']}")

        if os.path.exists(final):
            print("    已存在，跳过")
            skipped += 1
            continue

        try:
            qn = args.quality or 127
            info = http_client.json(
                f"{API}/x/player/playurl?bvid={bvid}&cid={page['cid']}"
                f"&qn={qn}&fnval=4048&fourk=1", referer)

            dash = info.get("dash")
            if not dash:
                # 老视频可能只有 durl（整段 flv/mp4），直接取回即可
                durl = info.get("durl") or []
                if not durl:
                    raise RuntimeError("既无 dash 也无 durl")
                ext = "flv" if ".flv" in durl[0]["url"] else "mp4"
                single = os.path.join(args.outdir, name + "." + ext)
                download(http_client, stream_urls(durl[0]), single, referer, "整段")
                print(f"    -> {os.path.basename(single)}")
                ok += 1
                continue

            video, audio = pick_streams(dash, args.codec, args.quality)
            q = QUALITY.get(video["id"], str(video["id"]))
            print(f"    画质 {q} {video.get('width')}x{video.get('height')} "
                  f"{(video.get('codecs') or '')[:12]}")

            vtmp = os.path.join(args.outdir, name + ".video.m4s")
            atmp = os.path.join(args.outdir, name + ".audio.m4s")
            download(http_client, stream_urls(video), vtmp, referer, "视频")
            if not verify_stream(ffmpeg, vtmp):
                raise RuntimeError("视频流解码校验未通过（花屏/黑屏），判为失败；"
                                   "重下有机会换到更好的节点")
            download(http_client, stream_urls(audio), atmp, referer, "音频")

            merge(ffmpeg, vtmp, atmp, final)
            if not args.keep:
                for t in (vtmp, atmp):
                    os.path.exists(t) and os.remove(t)
            print(f"    -> {os.path.basename(final)}  {human(os.path.getsize(final))}")
            ok += 1

        except KeyboardInterrupt:
            print("\n中断（.part 文件已保留，重跑可续传）")
            sys.exit(130)
        except Exception as e:
            print(f"    x 失败: {e}", file=sys.stderr)
            failed += 1

        if args.sleep and i < len(wanted):
            time.sleep(args.sleep)

    print(f"\n完成: 成功 {ok}，跳过 {skipped}，失败 {failed} -> {os.path.abspath(args.outdir)}")


if __name__ == "__main__":
    main()
