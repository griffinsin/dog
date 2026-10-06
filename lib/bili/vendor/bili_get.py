#!/usr/bin/env python3
"""
B 站统一下载入口 —— 自动识别「视频选集」和「合集」，你不用管是哪种。

B 站有两种把视频编组的方式，页面上长得很像，底层完全不同：

    视频选集（pages）     一个 BV 号内部的多个分P
    合集·XXX（ugc_season） 多个独立 BV 号被编成一组

用错脚本的后果不对称：把合集当选集下，只会下到其中一个视频，
**不报错、静默漏掉其余的**。所以这里做成自动判断。

判断依据：wbi/view 返回里有没有 ugc_season 字段。
（注意是 **wbi/view** —— 无签名的 x/web-interface/view 被风控挡着。）

用法:
    python3 bili_get.py <BV号或URL> -o ~/Videos/目标目录
    python3 bili_get.py <BV号或URL> --list              # 只看内容
    python3 bili_get.py <BV号或URL> --pick 1-10         # 只要前10个
    python3 bili_get.py <BV号或URL> --this-only         # 在合集里也只下当前这个视频
    python3 bili_get.py <BV号或URL> --cookies ck.txt -q 64   # 720P 需登录
"""

import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from bili_space_list import Space

DL = os.path.join(HERE, "bili_dl.py")
SEASON = os.path.join(HERE, "bili_season.py")


def parse_bvid(s):
    m = re.search(r"(BV[0-9A-Za-z]{10})", s)
    if not m:
        raise SystemExit(f"无法从 {s!r} 中识别 BV 号")
    return m.group(1)


def probe(bvid, cookies=None):
    """返回 (kind, info)。kind ∈ {'season', 'pages', 'single'}"""
    sp = Space("0", cookies)
    sp.warmup()
    sp.load_keys()
    j = sp._raw("https://api.bilibili.com/x/web-interface/wbi/view?"
                + sp.sign({"bvid": bvid}),
                f"https://www.bilibili.com/video/{bvid}")
    if j.get("code") != 0:
        raise SystemExit(f"取视频信息失败: code={j.get('code')} {j.get('message')}\n"
                         f"（若是 -352，等冷却后再试，别连续重试）")
    v = j["data"]
    info = {
        "title": v.get("title"),
        "up": v.get("owner", {}).get("name"),
        "pages": v.get("videos") or 1,
        "logged_in": sp.logged_in,
    }
    season = v.get("ugc_season")
    if season:
        info["season_title"] = season.get("title")
        info["season_count"] = season.get("ep_count")
        return "season", info
    return ("pages" if info["pages"] > 1 else "single"), info


def main():
    ap = argparse.ArgumentParser(
        description="B 站统一下载入口：自动识别视频选集 / 合集",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__.split("用法:")[-1])
    ap.add_argument("url", help="BV 号或视频 URL")
    ap.add_argument("-o", "--outdir", default=".", help="输出目录")
    ap.add_argument("--list", action="store_true", help="只列出内容，不下载")
    ap.add_argument("--pick", help="只要其中几个，如 1-10,15（选集=分P号，合集=第几个视频）")
    ap.add_argument("--this-only", action="store_true",
                    help="即使属于合集，也只下当前这个视频（含它自己的分P）")
    ap.add_argument("--cookies", help="Netscape cookie 文件；720P 以上必须带")
    ap.add_argument("-q", "--quality", type=int,
                    help="画质上限 id：80=1080P 64=720P 32=480P 16=360P")
    ap.add_argument("--codec", choices=["avc", "hev", "av0"], default="avc")
    ap.add_argument("--sleep", type=float, help="每项之间间隔秒")
    args = ap.parse_args()

    bvid = parse_bvid(args.url)
    kind, info = probe(bvid, args.cookies)

    label = {"season": "合集", "pages": "视频选集", "single": "单个视频"}[kind]
    print(f"识别结果：{label}", file=sys.stderr)
    print(f"  标题: {info['title']}", file=sys.stderr)
    print(f"  UP:   {info['up']}", file=sys.stderr)
    if kind == "season":
        print(f"  合集『{info['season_title']}』共 {info['season_count']} 个视频",
              file=sys.stderr)
        if info["pages"] > 1:
            print(f"  （当前这个视频自身还有 {info['pages']} 个分P）", file=sys.stderr)
    elif kind == "pages":
        print(f"  共 {info['pages']} 个分P", file=sys.stderr)
    if not info["logged_in"]:
        print("  未登录 —— 画质上限 480P", file=sys.stderr)
    print(file=sys.stderr)

    # 组装下游命令
    common = ["--codec", args.codec]
    if args.cookies:
        common += ["--cookies", args.cookies]
    if args.quality:
        common += ["-q", str(args.quality)]
    if args.list:
        common += ["--list"]

    if kind == "season" and not args.this_only:
        cmd = [sys.executable, SEASON, bvid, "-o", args.outdir] + common
        if args.pick:
            cmd += ["--index", args.pick]
        if args.sleep is not None:
            cmd += ["--sleep", str(args.sleep)]
    else:
        if kind == "season" and args.this_only:
            print("（--this-only：跳过合集其余视频）\n", file=sys.stderr)
        cmd = [sys.executable, DL, bvid, "-o", args.outdir] + common
        if args.pick:
            cmd += ["-p", args.pick]
        if args.sleep is not None:
            cmd += ["--sleep", str(args.sleep)]

    sys.exit(subprocess.run(cmd).returncode)


if __name__ == "__main__":
    main()
