#!/bin/bash

# Description: 下载 m3u8(HLS) 视频为 mp4

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# ───────────────────────── 给维护者 ─────────────────────────
#
# 复用 lib/dl/vendor/m3u8_to_mp4.py（从 ~/dev/scripts 逐字节复制，不要在这里改；
# 要改去 ~/dev/scripts 改完 cmp 对一遍再同步）。它用 ffmpeg -c copy 下 HLS，
# 自带 referer/origin 推导、cookie、headers 脱敏。本命令只做三件 vendor 没做好的事：
#
# 【命名】vendor 默认从 URL 末段取名，而 m3u8 末段几乎都是 index/playlist/720p/
#   一串 hash，没意义；且它的 sanitize 只认 ASCII，中文会变成一堆下划线。
#   所以命名在这里定：末段有意义就用，否则用 m3u8_时间戳；--name 可指定（支持中文，
#   因为直接当 vendor 的 -o 传进去，不走它的 sanitize）。算好的完整路径用 -o 交给 vendor。
#
# 【剪贴板】m3u8 链接长、几乎必带 ?token=，手敲加引号很烦；? 和 & 又是 shell 在
#   把参数交给 dog 前就处理掉的（bili 里踩过）。所以不带 URL 时从剪贴板读，展示确认。
#
# 【定位 lib/dl】brew 装完布局少一层 bin/，不能数 dirname 层数（bili 里踩过），
#   在两个候选位置里挑真正含 vendor 脚本的那个。
#
# 【中文输出用 ${var}】bash 3.2 在 UTF-8 locale 下裸 $var 紧跟多字节会吞字，见 globals.sh。

_dl_cmd_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DL_LIB=""
for _cand in "$_dl_cmd_dir/../lib/dl" "$_dl_cmd_dir/../../lib/dl"; do
    if [ -f "$_cand/vendor/m3u8_to_mp4.py" ]; then
        DL_LIB="$(cd "$_cand" && pwd)"
        break
    fi
done
if [ -z "$DL_LIB" ]; then
    dog_error "找不到 lib/dl（已查 $_dl_cmd_dir 的上一级和上两级）"
    dog_error "若是 brew 安装，试 dog upgrade 重装"
    exit 1
fi
M3U8="$DL_LIB/vendor/m3u8_to_mp4.py"

usage() {
    cat <<'HELP'
dog dl —— 下载 m3u8(HLS) 视频为 mp4

用法
  dog dl                          从剪贴板读 m3u8 链接（推荐，省得给长链接加引号）
  dog dl <m3u8链接> [选项]
  dog dl -n <m3u8链接>            只打印将执行的 ffmpeg 命令，不下载

选项
  -o <目录>        输出目录，默认当前目录
  --name <文件名>   指定输出文件名（可含中文；默认从链接推导，推不出用时间戳）
  --referer <url>  设置 Referer（很多 m3u8 有防盗链，必须带）
  --cookies <文件>  Netscape cookie 文件
  -n               dry-run，只打印 ffmpeg 命令
  -h, --help       显示本帮助

说明
  直接给链接时带 ? 或 & 要加引号：dog dl 'https://x/i.m3u8?token=abc'
  从剪贴板读则不用管引号。
  文件名：链接末段是 index/playlist/分辨率/hash 这类无意义的，会自动用
  m3u8_年月日_时分秒.mp4；想要有意义的名字用 --name。
HELP
}

url=""
outdir="."
name=""
referer=""
cookies=""
dry_run=false

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -o) outdir="$2"; shift 2 ;;
        --name) name="$2"; shift 2 ;;
        --referer) referer="$2"; shift 2 ;;
        --cookies) cookies="$2"; shift 2 ;;
        -n) dry_run=true; shift ;;
        -*) dog_error "未知参数: $1"; usage >&2; exit 1 ;;
        *)
            if [ -n "$url" ]; then
                dog_error "只支持一个链接"; usage >&2; exit 1
            fi
            url="$1"; shift ;;
    esac
done

# ── 没给链接：从剪贴板读 m3u8，展示确认 ───────────────────────
if [ -z "$url" ] && command -v pbpaste >/dev/null 2>&1; then
    clip=$(pbpaste 2>/dev/null | tr -d '\r' \
           | grep -oE 'https?://[^[:space:]]*\.m3u8[^[:space:]]*' | head -1)
    if [ -n "$clip" ]; then
        dog_log "从剪贴板读到:"
        print_color "$CYAN" "  ${clip}"
        printf "使用这个链接？[回车=是 / n=手动输入]: "
        read -r _ans
        case "$_ans" in
            [Nn]*) ;;
            *) url="$clip" ;;
        esac
    else
        dog_log "剪贴板里没有 m3u8 链接"
    fi
fi

if [ -z "$url" ]; then
    printf "请粘贴 m3u8 链接（直接回车取消）: "
    read -r url
    url=$(printf '%s' "$url" | tr -d '\r')
    [ -z "$url" ] && { dog_error "已取消"; exit 1; }
fi

if ! printf '%s' "$url" | grep -qE '\.m3u8'; then
    dog_error "这不像 m3u8 链接（不含 .m3u8）: ${url}"
    exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
    dog_error "未找到 ffmpeg，请先安装: brew install ffmpeg"
    exit 1
fi

# ── 决定文件名 ──────────────────────────────────────────────
# 末段（去 query、去 .m3u8）无意义时用时间戳。无意义 = 空 / 常见占位词 /
# 纯分辨率(720p) / 像 hash(全 hex 且较长)。
if [ -z "$name" ]; then
    base="${url%%\?*}"      # 去掉 ?query
    base="${base##*/}"      # 取末段
    base="${base%.m3u8}"    # 去扩展名
    meaningless=0
    case "$(printf '%s' "$base" | tr 'A-Z' 'a-z')" in
        ''|index|playlist|master|main|media|video|stream|chunklist|out|output|hls|live)
            meaningless=1 ;;
    esac
    printf '%s' "$base" | grep -qiE '^[0-9]{2,4}p?$'  && meaningless=1   # 480 / 720p
    printf '%s' "$base" | grep -qiE '^[0-9a-f]{12,}$' && meaningless=1   # 长 hex hash
    if [ "$meaningless" -eq 1 ]; then
        name="m3u8_$(date +%Y%m%d_%H%M%S)"
        [ "$dry_run" = false ] && dog_log "链接末段无有意义名字，用时间戳命名（--name 可自定）"
    else
        name="$base"
    fi
fi
name="${name%.mp4}.mp4"
dest="${outdir%/}/${name}"

# ── 组装并调用 vendor ───────────────────────────────────────
cmd=(python3 "$M3U8" "$url" -o "$dest")
[ -n "$referer" ] && cmd+=(--referer "$referer")
[ -n "$cookies" ] && cmd+=(--cookie-file "$cookies")

if [ "$dry_run" = true ]; then
    # 逐参数转义，这样打印出来的命令能直接复制运行（URL 的 ?& 不会被 shell 截断）
    _show=""
    for _a in "${cmd[@]}"; do _show="$_show $(printf '%q' "$_a")"; done
    echo "将执行:${_show}"
    echo "输出到: ${dest}"
    exit 0
fi

if [ -e "$dest" ]; then
    dog_error "本地已存在: ${dest}"
    dog_log "换个名字用 --name，或换目录用 -o"
    exit 1
fi

mkdir -p "$outdir" 2>/dev/null
dog_log "下载: ${url}"
dog_log "输出: ${dest}"
echo

if "${cmd[@]}"; then
    echo
    if [ -f "$dest" ]; then
        dog_success "完成 -> ${dest}  ($(du -h "$dest" 2>/dev/null | cut -f1 | tr -d ' '))"
    else
        dog_success "完成 -> ${dest}"
    fi
else
    rc=$?
    dog_error "下载失败（退出码 ${rc}）"
    dog_log "若是防盗链（403/拿不到流），多半要带 --referer（视频所在网页地址）"
    exit "$rc"
fi
