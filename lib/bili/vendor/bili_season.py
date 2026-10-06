#!/usr/bin/env python3
"""
下载 B 站「合集」（ugc_season）里的所有视频。

和 bili_dl.py 的分工：
    bili_dl.py      —— 一个 BV 号内部的多个「分P」
    bili_season.py  —— 一个合集里的多个「视频」（各自独立的 BV 号）

两者容易混。页面上「选集」有时是分P、有时是合集，先用 --list 看一眼再下。

实现要点（踩过的坑）：
  * season_id 一般只能从 x/web-interface/view 拿，但那个接口被风控挡着（412）。
    改用 **WBI 签名版** x/web-interface/wbi/view 就能通 —— 这是关键。
  * 列合集内容用 x/polymer/web-space/seasons_archives_list，需要 mid + season_id。
  * 实际下载直接复用 bili_dl.py，避免重复实现 DASH 合并那套。

用法:
    python3 bili_season.py BV1SzwTzdEYo --list
    python3 bili_season.py BV1SzwTzdEYo -o ~/Videos/美文朗读
    python3 bili_season.py BV1SzwTzdEYo --index 3-10 --cookies ck.txt -q 80
"""

import argparse
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bili_space_list import Space, Risk          # 复用 WBI 签名与会话处理

DL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bili_dl.py")


def parse_bvid(s):
    m = re.search(r"(BV[0-9A-Za-z]{10})", s)
    if not m:
        raise SystemExit(f"无法从 {s!r} 中识别 BV 号")
    return m.group(1)


def safe_name(s, maxlen=120):
    s = re.sub(r'[/\\:*?"<>|\x00-\x1f]', "_", s).strip(" .")
    return s[:maxlen] or "untitled"


def resolve_season(sp, bvid):
    """BV 号 -> (season_id, mid, 合集标题, 总集数)。不属于合集则返回 None。"""
    j = sp._raw("https://api.bilibili.com/x/web-interface/wbi/view?"
                + sp.sign({"bvid": bvid}),
                f"https://www.bilibili.com/video/{bvid}")
    if j.get("code") != 0:
        raise SystemExit(f"取视频信息失败: code={j.get('code')} {j.get('message')}")
    v = j["data"]
    season = v.get("ugc_season")
    if not season:
        return None, v
    return {
        "season_id": season["id"],
        "mid": v["owner"]["mid"],
        "title": season.get("title"),
        "total": season.get("ep_count"),
    }, v


def list_archives(sp, mid, season_id, delay=2.0):
    """翻页取合集内全部视频。"""
    out, pn = [], 1
    while True:
        j = sp._raw("https://api.bilibili.com/x/polymer/web-space/seasons_archives_list"
                    f"?mid={mid}&season_id={season_id}&sort_reverse=false"
                    f"&page_num={pn}&page_size=30",
                    f"https://space.bilibili.com/{mid}")
        if j.get("code") != 0:
            raise Risk(f"列合集失败: code={j.get('code')} {j.get('message')}")
        d = j["data"]
        batch = d.get("archives") or []
        if not batch:
            break
        out.extend(batch)
        total = (d.get("page") or {}).get("total") or len(out)
        print(f"  第{pn}页 +{len(batch)}  {len(out)}/{total}", file=sys.stderr)
        if len(out) >= total:
            break
        pn += 1
        time.sleep(delay)
    return out


def parse_range(spec, total):
    if not spec:
        return list(range(1, total + 1))
    out = []
    for chunk in spec.split(","):
        chunk = chunk.strip()
        if not chunk:
            continue
        if "-" in chunk:
            a, _, b = chunk.partition("-")
            out.extend(range(int(a) if a.strip() else 1,
                             (int(b) if b.strip() else total) + 1))
        else:
            out.append(int(chunk))
    seen, res = set(), []
    for i in out:
        if 1 <= i <= total and i not in seen:
            seen.add(i)
            res.append(i)
    return res


def main():
    ap = argparse.ArgumentParser(
        description="下载 B 站合集（ugc_season）里的所有视频",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__.split("用法:")[-1])
    ap.add_argument("url", help="合集内任一视频的 BV 号或 URL")
    ap.add_argument("-o", "--outdir", default=".", help="输出目录")
    ap.add_argument("--list", action="store_true", help="只列出合集内容，不下载")
    ap.add_argument("--index", help="只下第几个，如 1-10,15（按合集顺序）")
    ap.add_argument("--cookies", help="Netscape cookie 文件；要 720P 以上必须带")
    ap.add_argument("-q", "--quality", type=int, help="画质上限 id：80=1080P 64=720P 32=480P")
    ap.add_argument("--codec", choices=["avc", "hev", "av0"], default="avc")
    ap.add_argument("--sleep", type=float, default=4.0, help="视频之间间隔秒（默认 4）")
    args = ap.parse_args()

    bvid = parse_bvid(args.url)
    sp = Space("0", args.cookies)      # mid 占位，仅借用其会话与签名能力
    sp.warmup()
    sp.load_keys()

    season, view = resolve_season(sp, bvid)
    if not season:
        print(f"「{view.get('title')}」不属于任何合集。", file=sys.stderr)
        n = view.get("videos") or 1
        if n > 1:
            print(f"但它有 {n} 个分P —— 那种情况用 bili_dl.py：", file=sys.stderr)
            print(f"    python3 bili_dl.py {bvid} -o <目录>", file=sys.stderr)
        raise SystemExit(1)

    print(f"合集『{season['title']}』 共 {season['total']} 个视频"
          f"{'（已登录）' if sp.logged_in else '（未登录，画质上限 480P）'}", file=sys.stderr)

    archives = list_archives(sp, season["mid"], season["season_id"])
    total = len(archives)
    if total != season["total"]:
        print(f"! 实际取到 {total} 个，与声明的 {season['total']} 不符", file=sys.stderr)

    if args.list:
        for i, a in enumerate(archives, 1):
            d = a.get("duration") or 0
            print(f"{i:>3}. {a['title']}  [{d//60}:{d%60:02d}]  {a['bvid']}")
        return

    wanted = parse_range(args.index, total)
    os.makedirs(args.outdir, exist_ok=True)
    width = len(str(total))
    ok = skip = fail = 0
    t0 = time.time()

    for n, i in enumerate(wanted, 1):
        a = archives[i - 1]
        tag = f"{i:0{width}d}"
        print(f"\n[{n}/{len(wanted)}] #{tag} {a['title']}", file=sys.stderr)

        # 合集里每个视频可能自己还有多个分P，交给 bili_dl.py 下到各自子目录，
        # 避免不同视频的分P编号互相撞车。
        # 但单分P的视频没必要套一层目录 —— 下完扁平化，直接用视频标题命名。
        base = f"{tag}-{safe_name(a['title'])}"
        sub = os.path.join(args.outdir, base)
        flat = os.path.join(args.outdir, base + ".mp4")

        if os.path.exists(flat) or (os.path.isdir(sub) and
                                    any(f.endswith(".mp4") for f in os.listdir(sub))):
            print("    已存在，跳过", file=sys.stderr)
            skip += 1
            continue

        cmd = [sys.executable, DL, a["bvid"], "-o", sub, "--codec", args.codec]
        if args.cookies:
            cmd += ["--cookies", args.cookies]
        if args.quality:
            cmd += ["-q", str(args.quality)]
        r = subprocess.run(cmd)

        got = sorted(f for f in os.listdir(sub)) if os.path.isdir(sub) else []
        mp4s = [f for f in got if f.endswith(".mp4")]
        if r.returncode == 0 and mp4s:
            if len(mp4s) == 1 and len(got) == 1:
                # 单分P：提到上层，用视频标题命名（分P标题常是无意义的原始文件名）
                os.replace(os.path.join(sub, mp4s[0]), flat)
                os.rmdir(sub)
                print(f"    -> {os.path.basename(flat)}", file=sys.stderr)
            ok += 1
        else:
            print(f"    x 失败（退出码 {r.returncode}）", file=sys.stderr)
            fail += 1

        if n < len(wanted):
            time.sleep(args.sleep)

    el = int(time.time() - t0)
    print(f"\n完成: 成功 {ok}，跳过 {skip}，失败 {fail}，耗时 {el//60}分{el%60}秒",
          file=sys.stderr)
    print(f"目录: {os.path.abspath(args.outdir)}", file=sys.stderr)


if __name__ == "__main__":
    main()
