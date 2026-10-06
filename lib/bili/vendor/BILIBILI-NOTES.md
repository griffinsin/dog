# B 站抓取与下载 —— 实践笔记

> 记录于 2026-09-08，基于一次完整的实战（抓 UP 投稿列表 + 下载 224 个视频）。
> 配套脚本：`bili_dl.py`（下载）、`bili_space_list.py`（抓列表）

---

## 一、最重要的一条：风控 `-352` 不能硬闯

这是本次踩得最狠的坑，单独放在最前面。

**现象**：接口返回 `{"code":-352,"message":"风控校验失败","data":{"v_voucher":"..."}}`

**错误做法（我犯的）**：写重试循环，每次失败就换一套 cookie 再试。结果是
封锁**升级**——从接口层的 `-352` 变成 IP 层的 `HTTP 412`，最后连**正常浏览器
打开该主页都刷不出视频列表**（页面显示"空间主人还没投过视频"，但头部仍显示
视频数 2889）。20 秒换一次 `buvid3` 比正常翻页更像机器人。

**正确做法**：
- 遇到 `-352` **立即停止**，保留已抓到的分页缓存，等冷却后续跑
- 冷却时间：几十分钟到几小时
- 带 `v_voucher` 说明触发了人机验证（极验captcha）。**不要尝试绕过**
- 根本解法是**登录态**：带 `SESSDATA` 的请求风控阈值高得多

**实测对比**：
| 状态 | 结果 |
|---|---|
| 匿名 + 硬重试 | 3 页后 `-352`，随后 IP 级 412，全站列表不可用 |
| 登录态 + 15~40 秒/页 | 连翻 16 页零报错 |

---

## 二、接口清单（实测）

### 可用

| 接口 | 用途 | 备注 |
|---|---|---|
| `x/player/pagelist?bvid=` | 取分P列表和 cid | 最稳，必带 Referer |
| `x/player/playurl?bvid=&cid=&qn=127&fnval=4048&fourk=1` | 取 DASH 流地址 | 返回 `accept_description` 和 `dash` |
| `x/web-interface/nav` | 取 WBI 签名密钥 | 匿名可用 |
| `x/space/wbi/arc/search` | UP 投稿列表 | **需 WBI 签名**，风控极敏感 |
| `x/polymer/web-space/seasons_series_list` | UP 的合集/系列列表 | 无合集时返回空 |
| `x/web-interface/wbi/view?bvid=` | 视频详情 + **合集 ugc_season 信息** | **需 WBI 签名**，见下方更正 |
| `x/polymer/web-space/seasons_archives_list` | 列出合集内全部视频 | 需 `mid` + `season_id` |

> **⚠ 更正（2026-10-06）**：早先这里写 `x/web-interface/view` 不可用就没了下文，
> 导致「拿不到 season_id」被当成死路。实际上**加 WBI 签名的 `wbi/view` 能通**，
> 无签名的那个才是 412。要合集信息走签名版即可。

### 不可用

| 接口/路径 | 现象 |
|---|---|
| `x/web-interface/view`（无签名） | 返回 HTML 错误页（"出错啦!"），非 JSON；**改用 `wbi/view`** |
| `x/web-interface/view/detail` | 412 Precondition Failed |
| `www.bilibili.com/video/BVxxx`（页面 HTML） | 412 Precondition Failed |
| `x/space/arc/search`（旧版空间接口） | `-799 请求过于频繁`，已废弃 |

> **yt-dlp 用不了**：其 bilibili 提取器抓的正是被 412 拦掉的视频页 HTML。
> 本机 2026.03.17 版实测失败。这也是为什么要自己写 `bili_dl.py`。

---

## 三、必备请求头与 cookie 预热

两者缺一都会失败。

```python
headers = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                  "AppleWebKit/537.36 (KHTML, like Gecko) "
                  "Chrome/140.0.0.0 Safari/537.36",
    "Referer": f"https://www.bilibili.com/video/{bvid}",   # 缺了直接报错页
    "Accept": "application/json, text/plain, */*",
    "Accept-Language": "zh-CN,zh;q=0.9",
}
```

**cookie 预热**：先 GET 一次 `https://www.bilibili.com/` 拿到 `buvid3` + `b_nut`，
否则接口直接 412。

浏览器真实会话还会有 `buvid4`、`bili_ticket`、`buvid_fp` 等，
可以从 `document.cookie` 抠出来喂给脚本。
但注意 **`SESSDATA` 是 httpOnly，JS 读不到**——想要登录态必须用浏览器扩展
（如 Get cookies.txt）导出 Netscape 格式 cookie 文件。

> `SESSDATA` 等同于登录凭证，用完即删，不要提交进任何仓库。

---

## 四、WBI 签名（空间接口必需）

```python
MIXIN_TAB = [46,47,18,2,53,8,23,32,15,50,10,31,58,3,45,35,27,43,5,49,33,9,42,
             19,29,28,14,39,12,38,41,13,37,48,7,16,24,55,40,61,26,17,0,1,60,
             51,30,4,22,25,54,21,56,59,6,63,57,62,11,36,20,34,44,52]

# 1) 从 nav 接口取 img_key / sub_key（URL basename 去扩展名）
img = get("https://api.bilibili.com/x/web-interface/nav")["data"]["wbi_img"]
base = lambda u: u.rsplit("/", 1)[-1].split(".")[0]
ik, sk = base(img["img_url"]), base(img["sub_url"])

# 2) 按固定表打乱拼接，取前 32 位
mixin = "".join((ik + sk)[i] for i in MIXIN_TAB)[:32]

# 3) 参数加 wts，按 key 排序后 urlencode，过滤 !'()* 字符
p = dict(params, wts=int(time.time()))
q = urllib.parse.urlencode({k: "".join(c for c in str(v) if c not in "!'()*")
                            for k, v in sorted(p.items())})

# 4) w_rid = md5(query + mixin)
p["w_rid"] = hashlib.md5((q + mixin).encode()).hexdigest()
```

浏览器里做同样的事需要自己实现 MD5（`SubtleCrypto` 不支持 MD5）。

---

## 五、清晰度：登录门槛

**关键认知**：`accept_description` 列出的是视频**存在**的清晰度，
`dash.video` 里才是你**实际能取到**的。两者经常不一致。

实测（同一视频）：
```
声明可选：['高清 1080P', '高清 720P', '清晰 480P', '流畅 360P']
匿名实得：[(32, 852, 480), (16, 640, 360)]        ← 480P 封顶
```

720P 及以上被登录门槛挡住。`-q 80` 之类的参数在匿名下不起作用。

**判断片源质量**：看 `accept_description` 的上限。
同一课程的两个搬运源，一个标称到 1080P、一个只到 720P，
说明后者的**源文件本身**就是压过的——即使都只能下 480P，
前者留了将来升级的余地。

**480P 够不够用**：讲题类视频（幻灯片 + 大字）480P 完全可读，
包括汉字上的振假名小字。静态画面 H.264 压得很狠，
7 分钟视频可能只有 7.5MB，别被文件小吓到。
真正会露怯的是快速运动画面。

---

## 六、下载：DASH 流合并

`playurl` 返回的 `dash` 里 video / audio 是分开的，需要各下一路再合并。

```python
# 选流：优先高画质 id，编码偏好 avc（兼容性最好）> hev > av01
video = sorted(dash["video"], key=lambda v: (-v["id"], codec_pref(v)))[0]
audio = max(dash["audio"], key=lambda a: a.get("bandwidth") or 0)
```

**下载 m4s 时同样要带 Referer**，CDN（`*.bilivideo.com`）会校验。

`baseUrl` 之外还有 `backupUrl` 镜像列表，主源失败时逐个换。
不同镜像速度差异很大——本次实测同一批内容，
一个源 2MB/s，另一个只有 200KB/s。

**合并**：
```bash
ffmpeg -y -i video.m4s -i audio.m4s -c copy -movflags +faststart out.mp4
```

老视频可能没有 `dash` 只有 `durl`（整段 flv/mp4），直接取回即可。

---

## 七、浏览器方案（API 走不通时）

当 IP 被风控、或需要登录态时，直接在**页面上下文里**跑循环最可靠——
请求带着真实浏览器指纹和完整 cookie。

**实战做法**：在页面注入一个后台 async 循环，翻页 + 抽取 DOM，
结果存 `window.__acc`，然后短轮询读取状态。

```javascript
window.__n3 = {items: [], seen: new Set(), pages: 0, done: false, err: null};
(async () => {
  while (!S.stop && S.items.length < S.target) {
    window.scrollBy(0, 300 + Math.random() * 500);   // 像人一样先滚一下
    await sleep(rnd(800, 2000));
    /* 抽取当前页 */
    const btn = [...document.querySelectorAll('button.vui_pagenation--btn-side')]
      .find(b => b.innerText.trim() === '下一页');
    if (!btn || btn.disabled) break;
    btn.click();
    await sleep(rnd(15000, 40000));                   // 模拟阅读停顿
  }
  S.done = true;
})();
```

### 三个必须知道的限制

1. **CDP `Runtime.evaluate` 超时 45 秒** —— 单次 JS 调用里的 `await`
   必须短于此。轮询用 35 秒比较安全。
2. **`browser_batch` 有整体超时** —— 3 × 35 秒的批量可以，5 × 35 秒会超时。
3. **后台标签页定时器被 Chrome 限流到约每分钟一次** —— 设的
   `setTimeout(15~40秒)` 实际变成 ~60 秒。
   对爬取来说反而是好事，节奏更像真人。

**空列表要当作风控信号**：如果某页抽到 0 个链接，立刻停，别继续点。

---

## 八、批量下载的工程细节

### 断点续跑

按"最终文件名存在就跳过"来判断，比记录进度文件可靠。
中断后重跑同一条命令即可。分片下载用 `.part` 临时文件 + `Range` 续传，
注意服务端忽略 `Range` 时（返回 200 而非 206）必须从头写，否则文件会拼错。

### 命名陷阱

- 多 P 视频：脚本按分P号加前缀，但**分P标题本身可能已经带编号**，
  会产生 `065-065 【…】.mp4` 这种重复。下完统一规整一次。
- 补零要一开始就想好：`01-` 和 `001-` 混在一起排序会乱。
- 全角/半角不统一（`【Ｎ３文法】` vs `【N３文法】`）也会影响排序和搜索。
- **分P标题可能本身就以 `.mp4` 结尾**（UP 直接拿原始文件名当标题），无条件追加扩展名会得到 `xxx.mp4.mp4`。命名前先剥一次已知媒体扩展名。
- 合集里**单分P的视频**不必套子目录 —— 分P标题常是无意义的原始文件名，扁平化后用视频标题命名更可读。

### 节奏

| 场景 | 间隔 | 实测结果 |
|---|---|---|
| 下载视频（playurl + CDN） | 3~8 秒 | 104 个零失败 |
| 空间翻页（登录态） | 15~40 秒 | 16 页零报错 |
| 空间翻页（匿名） | 任何间隔 | 3 页后必挂 |

---

## 九、校验：别只看"下完了"

下完必须验，且要用**能真正发现问题**的方法。

```python
# 1) 完整性：编号无缺号、无重号
# 2) 零字节 / 异常小文件
# 3) 每个文件 ffprobe，确认 video + audio 两条轨都在
# 4) 总时长对比源站标称值
# 5) 重复检测：比对精确字节数（相同字节数才可疑）
# 6) 顺序：与原版**逐位**比对（见下，这条最容易漏）
```

### 集合相等 ≠ 顺序相同

**踩过的大坑。** 合并两个搬运源的内容时，我用 set 做差集，确认了
「这 64 集的内容都在原版前 64 集里」，就下结论说「完全对得上」。

实际上**前 64 位里有 31 位错位**——两个搬运号各自排的序不同。
集合相等只证明内容齐全，完全不保证位置对应。差点让整套课程按错误顺序学完。

正确做法是差集之后再加一道逐位比对：

```python
mismatch = [(i+1, mine[i], canon[i]) for i in range(n)
            if norm(mine[i]) != norm(canon[i])]
```

修复前先验证映射是**严格一一对应**（全部可映射、目标范围恰好 1..n、
无重复无遗漏），任一条不满足就中止。改名用**两阶段**
（先全部改成临时名，再落位），否则置换过程中会互相覆盖。

**踩过的坑**：用 `stat -f%z`（BSD 语法）在这台机器上失败，
因为 shell 解析到的是 GNU stat，导致整段检查报错、
输出一堆假的"同尺寸"配对。**跨平台就用 Python 的 `os.path.getsize`**。

**总时长偏差怎么看**：和源站标称差几十秒是正常的——
不同搬运源压制参数不同，首尾帧处理差异会累积。
真少一集的话，差值会是分钟级而不是秒级。

---

## 十、找完整版剧集

搬运号经常只搬一部分就停更。本次遇到的情况：
手上的"完整"系列其实只有 64 集，真正的完整版是 120 集。

**查证方法**：
1. 搜索关键词（作者名 + 课程名），列出候选
2. **不要信标题**——用 `pagelist` 接口核对实际分P数和总时长
3. 多个独立搬运源如果集数和时长互相吻合，可信度就高了
4. 用差集算出到底缺哪几集

本次三个源都是 120 集 / 12:27:4x，互相印证，
然后 diff 出缺失的正好是连续的 P65–P120。

搜索结果里逐集投稿的账号（标题带序号，如 `107. 【Ｎ３文法】～間・～間に`）
对确认**完整版总集数**很有帮助。

---

## 十一、分P 不是合集

页面上的「选集 / 选集列表」有两种完全不同的东西，**极易混淆**：

| | 分P（pages） | 合集（ugc_season） |
|---|---|---|
| 本质 | **一个** BV 号内部的多个片段 | **多个独立 BV 号**被编成一组 |
| 怎么取 | `x/player/pagelist?bvid=` | `wbi/view` 拿 season_id → `seasons_archives_list` |
| 用哪个脚本 | `bili_dl.py` | `bili_season.py` |

**日常直接用 `bili_get.py`**，它先查 `wbi/view` 有无 `ugc_season`，再自动分发到上面两个，不用你先分类。

用错的后果不对称：把合集当选集下，只会下到其中一个视频，**不报错、静默漏掉其余的**。这正是要自动判断的原因。

**先用 `--list` 看一眼再下**。判断方法：`wbi/view` 返回里有没有 `ugc_season` 字段——
有就是合集，没有就看 `videos` 字段（>1 即多分P）。

合集里的每个视频**自己还可能有多个分P**，所以 `bili_season.py` 把每个视频下到
各自的子目录，避免不同视频的分P编号互相撞车。

---

## 十二、快速参考

```bash
# 统一入口：自动识别视频选集 / 合集（推荐）
python3 bili_get.py <BV号或URL> -o ~/Videos/目标
python3 bili_get.py <BV号或URL> --list          # 先看内容
python3 bili_get.py <BV号或URL> --pick 1-10     # 只要前10个
python3 bili_get.py <BV号或URL> --this-only     # 合集里只下当前这个

# 列出 UP 投稿并按正则分拣
python3 bili_space_list.py 523604442 --cookies ck.txt --filter 'N3练习题' -o list.txt

# 下载整个多P视频
python3 bili_dl.py BV1rkjZzoEV2 -o ~/Videos/课程

# 只下部分分P
python3 bili_dl.py BV1rkjZzoEV2 -p 65-120 -o ~/Videos/课程

# 只看分P列表不下载
python3 bili_dl.py BV1AJ411J7W6 --list

# 带登录态下高清
python3 bili_dl.py BV1rkjZzoEV2 --cookies ~/bili_cookies.txt -q 80
```

**探测某视频可用清晰度**：
```bash
curl -s -c ck.txt -o /dev/null -A "Mozilla/5.0 ..." https://www.bilibili.com/
# 再用 pagelist 拿 cid，然后
curl -s -b ck.txt -A "Mozilla/5.0 ..." -H "Referer: https://www.bilibili.com/video/$BV" \
  "https://api.bilibili.com/x/player/playurl?bvid=$BV&cid=$CID&qn=127&fnval=4048&fourk=1"
# 看 accept_description（存在的） vs dash.video（实际能取的）
```
