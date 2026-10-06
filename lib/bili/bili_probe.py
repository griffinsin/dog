#!/usr/bin/env python3
"""
一次探清一个 BV 号的「类型」和「实际可用画质」，输出 TSV 供 bin/commands/bili.sh 消费。

为什么要单独有这个脚本：bili_get.py 的 probe() 只查 wbi/view，拿不到画质。
而画质菜单如果照着固定表列（8K/4K/1080P/...），未登录时你选 1080P 会被静默
降到 480P —— 笔记第五节写明 accept_description 是「存在的」，dash.video 才是
「实际能取到的」，两者经常不一致。菜单必须按后者来。

API 调用次数（风控敏感，见笔记第一节，-352 冷却几十分钟到几小时）：
    warmup(首页) + nav + wbi/view + pagelist + playurl = 5 次
全部复用同一个会话，彼此之间留间隔。这几个接口都不是空间列表那类高危接口。

输出（TSV，每行 KEY<TAB>值...）：
    KIND     season | pages | single
    TITLE    标题
    UP       UP 名
    PAGES    分P 数
    LOGGED   0 | 1
    UNAME    登录用户名（仅 LOGGED=1）
    SEASON_TITLE / SEASON_COUNT   仅 KIND=season
    P        分P号  cid  标题        （每个分P一行）
    Q        画质id  名称  宽x高  编码   （实际可取，按画质降序）
    QDECL    声明存在的画质描述（逗号分隔，仅供对比提示）
    ERR      出错信息

用法:
    python3 bili_probe.py BV1xx411c7mD [--cookies ck.txt]
"""

import argparse
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from bili_space_list import Space          # 复用 WBI 签名与会话
from bili_dl import QUALITY, parse_bvid     # 复用画质名表与 BV 解析

GAP = 0.6      # 接口之间的间隔，别连打


def out(key, *vals):
    print("\t".join([key] + [str(v) for v in vals]))


def main():
    ap = argparse.ArgumentParser(description="探测 B 站视频类型与实际可用画质")
    ap.add_argument("url", help="BV 号或 URL")
    ap.add_argument("--cookies", help="Netscape cookie 文件")
    ap.add_argument("--no-quality", action="store_true",
                    help="跳过画质探测（少 2 次 API 调用）")
    args = ap.parse_args()

    bvid = parse_bvid(args.url)
    sp = Space("0", args.cookies)           # mid 占位，只借会话与签名
    sp.warmup()
    time.sleep(GAP)
    sp.load_keys()
    time.sleep(GAP)

    j = sp._raw("https://api.bilibili.com/x/web-interface/wbi/view?"
                + sp.sign({"bvid": bvid}),
                f"https://www.bilibili.com/video/{bvid}")
    if j.get("code") != 0:
        code = j.get("code")
        hint = "（-352 是风控，等冷却后再试，别连续重试）" if code == -352 else ""
        out("ERR", f"取视频信息失败: code={code} {j.get('message')}{hint}")
        return 1

    v = j["data"]
    out("BVID", bvid)
    out("TITLE", v.get("title") or "")
    out("UP", (v.get("owner") or {}).get("name") or "")
    npages = v.get("videos") or 1
    out("PAGES", npages)
    out("LOGGED", 1 if sp.logged_in else 0)

    season = v.get("ugc_season")
    if season:
        out("KIND", "season")
        out("SEASON_TITLE", season.get("title") or "")
        out("SEASON_COUNT", season.get("ep_count") or 0)
    else:
        out("KIND", "pages" if npages > 1 else "single")

    # 分P 列表：顺带拿到第一个 cid 供画质探测
    cid = (v.get("cid") or 0)
    pages_meta = v.get("pages") or []
    if pages_meta:
        for p in pages_meta:
            out("P", p.get("page"), p.get("cid"), p.get("part") or "")
        cid = pages_meta[0].get("cid") or cid
    elif not args.no_quality:
        time.sleep(GAP)
        try:
            pl = sp._raw(f"https://api.bilibili.com/x/player/pagelist?bvid={bvid}&jsonp=jsonp",
                         f"https://www.bilibili.com/video/{bvid}")
            for p in (pl.get("data") or []):
                out("P", p.get("page"), p.get("cid"), p.get("part") or "")
            if pl.get("data"):
                cid = pl["data"][0]["cid"]
        except Exception as e:
            out("WARN", f"取分P列表失败: {e}")

    if args.no_quality or not cid:
        return 0

    # 画质探测：qn=127 + fourk=1 问到顶，看实际返回什么
    time.sleep(GAP)
    try:
        pu = sp._raw(f"https://api.bilibili.com/x/player/playurl?bvid={bvid}&cid={cid}"
                     f"&qn=127&fnval=4048&fourk=1",
                     f"https://www.bilibili.com/video/{bvid}")
    except Exception as e:
        out("WARN", f"画质探测失败: {e}")
        return 0

    if pu.get("code") != 0:
        out("WARN", f"画质探测失败: code={pu.get('code')} {pu.get('message')}")
        return 0

    d = pu.get("data") or {}
    decl = d.get("accept_description") or []
    if decl:
        out("QDECL", ",".join(decl))

    dash = d.get("dash")
    if not dash:
        # 老视频只有 durl（整段），没有画质可挑
        if d.get("durl"):
            out("WARN", "该视频只有整段流（durl），无法选画质")
        return 0

    # 同一画质 id 可能有多个编码，这里按 id 去重，保留带宽最高的那条做展示
    best = {}
    for vs in dash.get("video") or []:
        vid = vs.get("id")
        if vid is None:
            continue
        cur = best.get(vid)
        if cur is None or (vs.get("bandwidth") or 0) > (cur.get("bandwidth") or 0):
            best[vid] = vs
    for vid in sorted(best, reverse=True):
        vs = best[vid]
        out("Q", vid, QUALITY.get(vid, str(vid)),
            f"{vs.get('width')}x{vs.get('height')}",
            (vs.get("codecs") or "")[:12])
    return 0


if __name__ == "__main__":
    sys.exit(main())
