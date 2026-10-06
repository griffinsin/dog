#!/usr/bin/env python3
"""
dog bili 的 Python 侧：探测 + 扫码登录。bin/commands/bili.sh 调用本文件。

子命令:
    probe <url>  探清类型与「实际可用」画质，输出 TSV
    login -o <f> 官方 web 扫码登录，写 Netscape cookie 文件
    check -o <f> 检查现有 cookie 的登录态，stdout 打用户名，退出码表示是否登录

vendor/ 下的 4 个脚本（bili_get / bili_dl / bili_season / bili_space_list）
是从 ~/dev/scripts 逐字节复制的外部快照，**不要改**。
改动请在 ~/dev/scripts 做，然后 cmp 对一遍再同步过来。
它们记录的踩坑细节见 vendor/BILIBILI-NOTES.md —— 下面多处判断都以它为依据。
"""

import argparse
import http.cookiejar
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "vendor"))
from bili_space_list import Space          # 复用 WBI 签名与会话
from bili_dl import QUALITY, parse_bvid, safe_name   # 复用画质名表 / BV 解析 / 文件名清洗

UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
PASSPORT = "https://passport.bilibili.com/x/passport-login/web/qrcode"
NAV = "https://api.bilibili.com/x/web-interface/nav"

GAP = 0.6      # 接口之间的间隔，别连打（笔记第一节：-352 风控不能硬闯）

POLL_MSG = {
    86101: "等待扫码",
    86090: "已扫码，请在手机上确认",
    86038: "二维码已失效",
}


# ──────────────────────────────── probe ────────────────────────────────
#
# 为什么要单独探测画质：笔记第五节 —— accept_description 列的是视频「存在」
# 的画质，dash.video 里才是你「实际能取到」的，两者经常不一致。实测同一视频
# 声明到 1080P，匿名只能取到 480P。菜单若照固定表列，用户选 1080P 会被静默
# 降级且不报错。所以只列 dash.video 真实返回的。
#
# API 调用：warmup(首页) + nav + wbi/view + [pagelist] + playurl，共 4~5 次，
# 全部复用同一会话、彼此留 GAP 秒。都不是空间列表那类高危接口。
#
# 输出 TSV（KEY<TAB>值...）：
#   KIND season|pages|single / TITLE / UP / PAGES / LOGGED / BVID
#   SEASON_TITLE / SEASON_COUNT      仅 KIND=season
#   P    分P号 cid 标题              每个分P一行
#   Q    画质id 名称 宽x高 编码       实际可取，按画质降序
#   QDECL 声明存在的画质描述（逗号分隔，仅用于提示对比）
#   WARN / ERR

def out(key, *vals):
    print("\t".join([key] + [str(v) for v in vals]))


def cmd_probe(args):
    bvid = parse_bvid(args.url)
    sp = Space("0", args.cookies)           # mid 占位，只借会话与签名能力
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

    # 分P 列表：顺带拿到第一个 cid 供画质探测。wbi/view 多数情况已带 pages，
    # 带了就不用再打 pagelist —— 少一次请求。
    cid = v.get("cid") or 0
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
        # 老视频可能只有 durl（整段 flv/mp4），没有画质可挑（笔记第六节）
        if d.get("durl"):
            out("WARN", "该视频只有整段流（durl），无法选画质")
        return 0

    # 同一画质 id 可能有多个编码，按 id 去重、保留带宽最高的那条做展示
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


# ──────────────────────────────── login ────────────────────────────────
#
# 为什么需要扫码登录：720P 以上被登录门槛挡着（笔记第五节），而 SESSDATA 是
# httpOnly、JS 读不到，过去只能靠浏览器扩展导出 cookie 文件。官方 web 扫码
# 登录接口可以完全在终端走完，不用密码、不碰验证码。
#
# 两个接口（实测可用）：
#   qrcode/generate -> {url, qrcode_key}
#   qrcode/poll?qrcode_key=xxx -> 嵌套 data.code:
#       86101 未扫码  86090 已扫码待确认  86038 已失效  0 成功
# 成功时 cookie 由响应的 Set-Cookie 带回，jar.save() 直接落盘。

def make_opener(jar):
    return urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))


def get_json(opener, url, referer="https://www.bilibili.com/"):
    req = urllib.request.Request(url, headers={
        "User-Agent": UA,
        "Referer": referer,
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "zh-CN,zh;q=0.9",
    })
    with opener.open(req, timeout=30) as r:
        return json.loads(r.read().decode("utf-8"))


def render_qr(url):
    """在终端画二维码。不把这个 url 发给任何在线二维码服务 —— 它就是登录凭证入口。"""
    qrencode = shutil.which("qrencode")
    if not qrencode:
        print("! 未找到 qrencode，无法在终端渲染二维码。", file=sys.stderr)
        print("  安装： brew install qrencode", file=sys.stderr)
        print(f"\n  也可以手动把下面这个地址转成二维码用 B站 App 扫：\n  {url}\n",
              file=sys.stderr)
        return
    # ANSIUTF8 在深色/浅色终端下都能扫；-m 1 留一圈静默区，少了扫不出来
    subprocess.run([qrencode, "-t", "ANSIUTF8", "-m", "1", url], check=False)


def login_state(cookie_file):
    """返回 (是否登录, 用户名)。"""
    jar = http.cookiejar.MozillaCookieJar()
    try:
        jar.load(cookie_file, ignore_discard=True, ignore_expires=True)
    except Exception:
        return False, None
    if not any(c.name == "SESSDATA" for c in jar):
        return False, None
    try:
        j = get_json(make_opener(jar), NAV)
    except Exception:
        return False, None
    d = j.get("data") or {}
    if j.get("code") == 0 and d.get("isLogin"):
        return True, d.get("uname")
    return False, None


def cmd_login(args):
    cookie_file = args.out
    jar = http.cookiejar.MozillaCookieJar(cookie_file)
    opener = make_opener(jar)

    # 先摸一次首页拿 buvid3；缺了它后续接口直接 412（笔记第三节）
    try:
        opener.open(urllib.request.Request(
            "https://www.bilibili.com/", headers={"User-Agent": UA}),
            timeout=30).read(1024)
    except Exception as e:
        print(f"! 预热失败（继续尝试）: {e}", file=sys.stderr)

    j = get_json(opener, f"{PASSPORT}/generate")
    if j.get("code") != 0:
        raise SystemExit(f"申请二维码失败: code={j.get('code')} {j.get('message')}")
    url = j["data"]["url"]
    key = j["data"]["qrcode_key"]

    print("\n用手机 B站 App 扫描下面的二维码：\n", file=sys.stderr)
    render_qr(url)
    print(f"\n（{args.timeout} 秒内有效，Ctrl+C 可中断）\n", file=sys.stderr)

    deadline = time.time() + args.timeout
    last = None
    while time.time() < deadline:
        time.sleep(2)
        try:
            j = get_json(opener,
                         f"{PASSPORT}/poll?qrcode_key={urllib.parse.quote(key)}",
                         referer="https://passport.bilibili.com/")
        except Exception as e:
            print(f"\r  轮询出错，重试: {e}   ", end="", file=sys.stderr)
            continue

        st = (j.get("data") or {}).get("code")
        if st == 0:
            break
        if st == 86038:
            raise SystemExit("\n二维码已失效，请重新运行")
        msg = POLL_MSG.get(st, f"状态 {st}")
        if msg != last:
            print(f"\r  {msg} ...                    ", end="", file=sys.stderr)
            last = msg
    else:
        raise SystemExit("\n超时未完成扫码")

    print("\r  扫码成功                        ", file=sys.stderr)

    if not any(c.name == "SESSDATA" for c in jar):
        raise SystemExit("登录成功但响应里没有 SESSDATA —— 接口行为可能变了，"
                         "请检查 poll 返回的 Set-Cookie")

    os.makedirs(os.path.dirname(os.path.abspath(cookie_file)), exist_ok=True)
    # 先建出 0600 的空文件再让 jar 写：SESSDATA 等同登录凭证，
    # 默认 umask 下会是 644，同机其他账户可读
    fd = os.open(cookie_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.close(fd)
    jar.save(ignore_discard=True, ignore_expires=True)
    os.chmod(cookie_file, 0o600)

    ok, uname = login_state(cookie_file)
    if ok:
        print(f"已登录: {uname}", file=sys.stderr)
    print(f"cookie 已保存: {cookie_file} (权限 600)", file=sys.stderr)
    return 0


def cmd_safename(args):
    """把标题清洗成合法文件名。直接复用 vendor/bili_dl.py 的 safe_name，
    保证和下载器自己的命名规则完全一致 —— 不在 bash 里另写一套正则：
    .zshrc 有 coreutils/gnubin，sed/grep 是 GNU 还是 BSD 随上下文变化。"""
    print(safe_name(args.title))
    return 0


def cmd_check(args):
    ok, uname = login_state(args.out)
    print(uname or "", end="")
    return 0 if ok else 1


# ──────────────────────────────── 入口 ────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description="dog bili 的 Python 侧：探测与扫码登录")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("probe", help="探测类型与实际可用画质，输出 TSV")
    p.add_argument("url", help="BV 号或 URL")
    p.add_argument("--cookies", help="Netscape cookie 文件")
    p.add_argument("--no-quality", action="store_true", help="跳过画质探测")
    p.set_defaults(func=cmd_probe)

    p = sub.add_parser("login", help="扫码登录，生成 Netscape cookie 文件")
    p.add_argument("-o", "--out", required=True, help="cookie 文件输出路径")
    p.add_argument("--timeout", type=int, default=180, help="扫码等待秒数（默认 180）")
    p.set_defaults(func=cmd_login)

    p = sub.add_parser("safename", help="把标题清洗成合法文件名（复用下载器的规则）")
    p.add_argument("title", help="原始标题")
    p.set_defaults(func=cmd_safename)

    p = sub.add_parser("check", help="检查现有 cookie 的登录态")
    p.add_argument("-o", "--out", required=True, help="cookie 文件路径")
    p.set_defaults(func=cmd_check)

    args = ap.parse_args()
    try:
        return args.func(args)
    except KeyboardInterrupt:
        print("\n已取消", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
