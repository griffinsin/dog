#!/usr/bin/env python3
"""
列出 B 站 UP 主的全部投稿，并按标题正则分拣。

接口说明：
  空间投稿走 x/space/wbi/arc/search，需要 WBI 签名（img_key+sub_key 打乱取前32位，
  再对排序后的 query 做 md5）。旧的 x/space/arc/search 已废弃，直接返回 -799。

风控（重要）：
  该接口对匿名请求非常敏感。一旦返回 -352（带 v_voucher，即人机校验），
  该 IP 会被锁一段时间，连正常网页都刷不出列表。
  所以本脚本的策略是：**遇到 -352 立刻停止**，把已抓到的页缓存下来，
  等冷却后再续跑——而不是不停重试（重试只会让封锁升级）。

  想稳定抓完几千条，强烈建议带上登录 cookie（--cookies），
  已登录账号的风控阈值高得多。

用法:
    python3 bili_space_list.py 523604442 --cookies ck.txt
    python3 bili_space_list.py 523604442 --filter 'N3练习题' -o n3.txt
    python3 bili_space_list.py 523604442 --resume        # 冷却后接着抓
"""

import argparse, hashlib, http.cookiejar, json, os, re, sys, time
import urllib.parse, urllib.request

UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36")
MIXIN_TAB = [46,47,18,2,53,8,23,32,15,50,10,31,58,3,45,35,27,43,5,49,33,9,42,
             19,29,28,14,39,12,38,41,13,37,48,7,16,24,55,40,61,26,17,0,1,60,
             51,30,4,22,25,54,21,56,59,6,63,57,62,11,36,20,34,44,52]


class Risk(Exception):
    """触发人机校验，必须停下来等冷却。"""


class Space:
    def __init__(self, mid, cookie_file=None):
        self.mid = str(mid)
        self.ref = f"https://space.bilibili.com/{self.mid}/upload/video"
        self.jar = http.cookiejar.MozillaCookieJar()
        if cookie_file:
            self.jar.load(cookie_file, ignore_discard=True, ignore_expires=True)
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self.jar))
        self.logged_in = any(c.name == "SESSDATA" for c in self.jar)
        self.keys = None

    def _raw(self, url, referer=None, as_json=True):
        req = urllib.request.Request(url, headers={
            "User-Agent": UA,
            "Referer": referer or "https://www.bilibili.com/",
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "zh-CN,zh;q=0.9",
        })
        with self.opener.open(req, timeout=30) as r:
            body = r.read().decode(errors="replace")
        return json.loads(body) if as_json else body

    def warmup(self):
        """先访问首页拿 buvid3/b_nut，否则接口直接 412。"""
        if not any(c.name == "buvid3" for c in self.jar):
            try:
                self._raw("https://www.bilibili.com/", as_json=False)
            except Exception as e:
                print(f"! 预热失败：{e}", file=sys.stderr)

    def load_keys(self):
        img = self._raw("https://api.bilibili.com/x/web-interface/nav")["data"]["wbi_img"]
        base = lambda u: u.rsplit("/", 1)[-1].split(".")[0]
        self.keys = (base(img["img_url"]), base(img["sub_url"]))

    def sign(self, params):
        ik, sk = self.keys
        mixin = "".join((ik + sk)[i] for i in MIXIN_TAB)[:32]
        p = dict(params, wts=int(time.time()))
        q = urllib.parse.urlencode(
            {k: "".join(c for c in str(v) if c not in "!'()*")
             for k, v in sorted(p.items())})
        p["w_rid"] = hashlib.md5((q + mixin).encode()).hexdigest()
        return urllib.parse.urlencode(p)

    def page(self, pn, ps=30):
        qs = self.sign({"mid": self.mid, "ps": ps, "pn": pn, "index": 1,
                        "order": "pubdate", "platform": "web",
                        "web_location": 1550101})
        d = self._raw(f"https://api.bilibili.com/x/space/wbi/arc/search?{qs}", self.ref)
        code = d.get("code")
        if code == -352:
            raise Risk("人机校验（-352）")
        if code in (-799, -509):
            raise Risk(f"限流（{code}）")
        if code != 0:
            raise RuntimeError(f"code={code} {d.get('message')}")
        return d["data"]["list"]["vlist"], d["data"]["page"]["count"]


def collect(cache_dir):
    seen, out = set(), []
    if os.path.isdir(cache_dir):
        for f in sorted(os.listdir(cache_dir)):
            for x in json.load(open(os.path.join(cache_dir, f))):
                if x["bvid"] not in seen:
                    seen.add(x["bvid"])
                    out.append(x)
    return out


def main():
    ap = argparse.ArgumentParser(
        description="列出并分拣 B 站 UP 主投稿",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__.split("用法:")[-1])
    ap.add_argument("mid", help="UP 主 uid，如 523604442")
    ap.add_argument("--cookies", help="Netscape cookie 文件（带 SESSDATA 更稳）")
    ap.add_argument("--filter", help="标题正则，只输出匹配项")
    ap.add_argument("-o", "--out", help="结果输出文件（默认打印到屏幕）")
    ap.add_argument("--cache", default=None, help="分页缓存目录（默认 .space_<mid>）")
    ap.add_argument("--delay", type=float, default=6.0, help="每页间隔秒（默认 6，别调太小）")
    ap.add_argument("--ps", type=int, default=30, help="每页条数（默认 30）")
    ap.add_argument("--max-pages", type=int, help="最多抓多少页（调试用）")
    ap.add_argument("--offline", action="store_true", help="不联网，只用缓存出结果")
    args = ap.parse_args()

    cache = args.cache or f".space_{args.mid}"
    os.makedirs(cache, exist_ok=True)

    if not args.offline:
        sp = Space(args.mid, args.cookies)
        sp.warmup()
        sp.load_keys()
        print(f"UP {args.mid}"
              f"{'（已登录）' if sp.logged_in else '（未登录，风控严格）'}", file=sys.stderr)

        pn, total, got = 1, None, 0
        while True:
            cf = os.path.join(cache, f"{pn:04d}.json")
            if os.path.exists(cf):
                vlist = json.load(open(cf))
            else:
                try:
                    vlist, total = sp.page(pn, args.ps)
                except Risk as e:
                    print(f"\n触发风控：{e}", file=sys.stderr)
                    print(f"已缓存 {len(os.listdir(cache))} 页；等冷却（通常几十分钟）后"
                          f"重跑同一条命令即可续抓。", file=sys.stderr)
                    print("带 --cookies（登录态）能大幅降低触发概率。", file=sys.stderr)
                    break
                json.dump(vlist, open(cf, "w"), ensure_ascii=False)
                time.sleep(args.delay)
            if not vlist:
                break
            got += len(vlist)
            tail = f"/{total}" if total else ""
            print(f"  p{pn}: +{len(vlist)}  {got}{tail}", file=sys.stderr)
            if total and got >= total:
                break
            if args.max_pages and pn >= args.max_pages:
                break
            pn += 1

    videos = collect(cache)
    if args.filter:
        rx = re.compile(args.filter)
        videos = [v for v in videos if rx.search(v["title"])]

    lines = [f"https://www.bilibili.com/video/{v['bvid']}  {v['title']}" for v in videos]
    text = "\n".join(lines) + ("\n" if lines else "")
    if args.out:
        open(args.out, "w").write(text)
        print(f"\n{len(videos)} 条 -> {args.out}", file=sys.stderr)
    else:
        print(text)
        print(f"\n共 {len(videos)} 条", file=sys.stderr)


if __name__ == "__main__":
    main()
