#!/usr/bin/env python3
"""
B 站扫码登录 —— 纯终端拿到 SESSDATA，写成 Netscape cookie 文件。

为什么需要这个：720P 以上被登录门槛挡着（见 BILIBILI-NOTES.md 第五节），
而 SESSDATA 是 httpOnly、JS 读不到，过去只能靠浏览器扩展导出 cookie 文件。
官方的 web 扫码登录接口可以完全在终端里走完，不用密码、不碰验证码。

流程（两个接口，实测可用）：
    qrcode/generate -> {url, qrcode_key}
    qrcode/poll?qrcode_key=xxx -> 嵌套 data.code:
        86101 未扫码   86090 已扫码待确认   86038 二维码已失效   0 成功

成功时 cookie 由响应的 Set-Cookie 带回，直接 jar.save() 落盘。

二维码渲染用 qrencode（brew install qrencode）。不把 url 发给任何在线
二维码服务 —— 那个 url 就是登录凭证入口。

用法:
    python3 bili_login.py -o ~/.config/dog/bili_cookies.txt
    python3 bili_login.py --check -o <cookie文件>     # 只检查登录态
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

UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
PASSPORT = "https://passport.bilibili.com/x/passport-login/web/qrcode"
NAV = "https://api.bilibili.com/x/web-interface/nav"

POLL_MSG = {
    86101: "等待扫码",
    86090: "已扫码，请在手机上确认",
    86038: "二维码已失效",
}


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
    """在终端画二维码。没有 qrencode 就退回打印 url。"""
    qrencode = shutil.which("qrencode")
    if not qrencode:
        print("! 未找到 qrencode，无法在终端渲染二维码。", file=sys.stderr)
        print("  安装： brew install qrencode", file=sys.stderr)
        print(f"\n  也可以手动把下面这个地址转成二维码用 B站 App 扫：\n  {url}\n",
              file=sys.stderr)
        return
    # ANSIUTF8 在深色/浅色终端下都能扫；-m 1 留一圈静默区，少了扫不出来
    subprocess.run([qrencode, "-t", "ANSIUTF8", "-m", "1", url], check=False)


def check(cookie_file):
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


def login(cookie_file, timeout=180):
    jar = http.cookiejar.MozillaCookieJar(cookie_file)
    opener = make_opener(jar)

    # 先摸一次首页拿 buvid3；缺了它后续接口会被风控拦（笔记第三节）
    try:
        opener.open(urllib.request.Request(
            "https://www.bilibili.com/", headers={"User-Agent": UA}), timeout=30).read(1024)
    except Exception as e:
        print(f"! 预热失败（继续尝试）: {e}", file=sys.stderr)

    j = get_json(opener, f"{PASSPORT}/generate")
    if j.get("code") != 0:
        raise SystemExit(f"申请二维码失败: code={j.get('code')} {j.get('message')}")
    url = j["data"]["url"]
    key = j["data"]["qrcode_key"]

    print("\n用手机 B站 App 扫描下面的二维码：\n", file=sys.stderr)
    render_qr(url)
    print(f"\n（{timeout} 秒内有效，Ctrl+C 可中断）\n", file=sys.stderr)

    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        time.sleep(2)
        try:
            j = get_json(opener, f"{PASSPORT}/poll?qrcode_key={urllib.parse.quote(key)}",
                         referer="https://passport.bilibili.com/")
        except Exception as e:
            print(f"\r  轮询出错，重试: {e}   ", end="", file=sys.stderr)
            continue

        d = j.get("data") or {}
        st = d.get("code")
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
    # 先建出 0600 的空文件再写：SESSDATA 等同登录凭证，不能让同机其他账户读到
    fd = os.open(cookie_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.close(fd)
    jar.save(ignore_discard=True, ignore_expires=True)
    os.chmod(cookie_file, 0o600)

    ok, uname = check(cookie_file)
    if ok:
        print(f"已登录: {uname}", file=sys.stderr)
    print(f"cookie 已保存: {cookie_file} (权限 600)", file=sys.stderr)
    return 0


def main():
    ap = argparse.ArgumentParser(description="B 站扫码登录，生成 Netscape cookie 文件")
    ap.add_argument("-o", "--out", required=True, help="cookie 文件输出路径")
    ap.add_argument("--check", action="store_true", help="只检查现有 cookie 的登录态")
    ap.add_argument("--timeout", type=int, default=180, help="扫码等待秒数（默认 180）")
    args = ap.parse_args()

    if args.check:
        ok, uname = check(args.out)
        print(uname or "", end="")
        return 0 if ok else 1

    try:
        return login(args.out, args.timeout)
    except KeyboardInterrupt:
        print("\n已取消", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
