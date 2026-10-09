#!/bin/bash

# Description: 下载 m3u8(HLS) 视频为 mp4

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# ───────────────────────── 给维护者 ─────────────────────────
#
# m3u8 下载的核心就是 ffmpeg 一行：ffmpeg -c copy -i <url> out.mp4。ffmpeg 自己
# 处理 HLS，没有签名/合并/风控那些难点，所以这里直接调 ffmpeg，不像 bili 那样
# 需要 vendor 脚本。（初版曾复制 m3u8_to_mp4.py 进来当中间商，纯属多余，还因
# .gitignore 的 vendor/ 规则漏打包出过残包，已撤。）
#
# ffmpeg 行为照搬自那份脚本，保持一致：
#   -n 不覆盖；-headers 用 CRLF 拼 Referer/Origin/Cookie；-c copy -bsf:a aac_adtstoasc。
#
# 【文件名全自动】用户不用输。m3u8 末段几乎都是 index/playlist/720p/hash，没意义，
#   这种就用 m3u8_年月日_时分秒.mp4（可排序、不重名）；少数末段像样的就用末段。
#   想自定义才用 --name（支持中文）。
#
# 【剪贴板】m3u8 链接长、几乎必带 ?token=，而 ? 和 & 是 shell 在把参数交给 dog 前
#   就处理掉的（bili 里踩过）。不带 URL 时从剪贴板读并展示确认。
#
# 【中文输出用 ${var}】bash 3.2 UTF-8 locale 下裸 $var 紧跟多字节会吞字，见 globals.sh。

usage() {
    cat <<'HELP'
dog dl —— 下载 m3u8(HLS) 视频为 mp4（文件名自动，不用你操心）

用法
  dog dl                          从剪贴板读 m3u8 链接（推荐）
  dog dl <m3u8链接>
  dog dl <m3u8链接> --referer <网页地址>    有防盗链时带上

选项
  --referer <url>  设置 Referer（很多 m3u8 有防盗链，报 403 就加这个）
  -o <目录>        输出目录，默认当前目录
  --name <文件名>   自定义文件名（默认自动，可含中文）
  --cookies <文件>  Netscape cookie 文件
  -n               dry-run，只打印将执行的 ffmpeg 命令
  -h, --help       显示本帮助

说明
  文件名默认自动：链接里推不出有意义的名字就用 m3u8_年月日_时分秒.mp4。
  直接给链接时带 ? 或 & 要加引号；从剪贴板读则不用管。
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
        case "$_ans" in [Nn]*) ;; *) url="$clip" ;; esac
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

# ── 文件名全自动 ────────────────────────────────────────────
if [ -z "$name" ]; then
    base="${url%%\?*}"; base="${base##*/}"; base="${base%.m3u8}"
    meaningless=0
    case "$(printf '%s' "$base" | tr 'A-Z' 'a-z')" in
        ''|index|playlist|master|main|media|video|stream|chunklist|out|output|hls|live)
            meaningless=1 ;;
    esac
    printf '%s' "$base" | grep -qiE '^[0-9]{2,4}p?$'  && meaningless=1   # 480 / 720p
    printf '%s' "$base" | grep -qiE '^[0-9a-f]{12,}$' && meaningless=1   # 长 hex hash
    if [ "$meaningless" -eq 1 ]; then
        name="m3u8_$(date +%Y%m%d_%H%M%S)"
    else
        name="$base"
    fi
fi
name="${name%.mp4}.mp4"
dest="${outdir%/}/${name}"

# ── 组装 ffmpeg（照搬 m3u8_to_mp4.py 的行为）────────────────
# Origin 从 Referer 推导：scheme://host，用 bash 参数展开，不碰 sed 方言
origin=""
if [ -n "$referer" ]; then
    _rest="${referer#*://}"
    origin="${referer%%://*}://${_rest%%/*}"
fi

# Netscape cookie 文件 -> "name=value; name2=value2"
cookie=""
if [ -n "$cookies" ] && [ -f "$cookies" ]; then
    cookie=$(awk -F'\t' '!/^#/ && NF>=7 {printf "%s=%s; ", $6, $7}' "$cookies" | sed 's/; $//')
fi

# -headers 需要 CRLF 分隔、整体一个参数
hdr=""
[ -n "$referer" ] && hdr="${hdr}Referer: ${referer}"$'\r\n'
[ -n "$origin" ]  && hdr="${hdr}Origin: ${origin}"$'\r\n'
[ -n "$cookie" ]  && hdr="${hdr}Cookie: ${cookie}"$'\r\n'

ff=(ffmpeg -n -hide_banner -loglevel warning -stats)
[ -n "$hdr" ] && ff+=(-headers "$hdr")
ff+=(-i "$url" -c copy -bsf:a aac_adtstoasc "$dest")

if [ "$dry_run" = true ]; then
    _show=""
    for _a in "${ff[@]}"; do _show="$_show $(printf '%q' "$_a")"; done
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

if "${ff[@]}"; then
    echo
    if [ -f "$dest" ]; then
        dog_success "完成 -> ${dest}  ($(du -h "$dest" 2>/dev/null | cut -f1 | tr -d ' '))"
    else
        dog_success "完成 -> ${dest}"
    fi
else
    rc=$?
    dog_error "下载失败（退出码 ${rc}）"
    dog_log "若报 403 / 拿不到流，多半是防盗链，加 --referer <视频所在网页地址> 再试"
    exit "$rc"
fi
