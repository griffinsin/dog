#!/bin/bash

# Description: 从安卓手机取回文件或目录到电脑

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# ───────────────────────── 给维护者 ─────────────────────────
#
# 和 send.sh 对称：send 是 adb push（电脑->手机），本命令是 adb pull（手机->电脑）。
# 设备检测与多设备选择复用 lib/globals.sh 的 dog_ensure_adb / dog_select_adb_device。
#
# 【手机侧路径必须正确加引号】实测手机 /sdcard/Download 里的文件名带空格和括号，
#   例如 "33e14f346b-...-1781490095 (1).apk"。
#   adb pull 的路径是单个 argv，带空格没问题；但 adb shell 会把参数拼成一个字符串
#   交给手机上的 sh 执行，不加引号就会被拆开。所以凡是走 adb shell 的地方
#   （存在性检查、列目录）都用 shq_remote 包一层单引号。
#
# 【不静默覆盖本地文件】拉取方向和 send 不同：覆盖的是你电脑上的东西。
#   目标已存在时默认拒绝并提示，要覆盖得显式加 -f。
#
# 【中文输出用 ${var} 不用 $var】macOS 自带 bash 3.2 在 UTF-8 locale 下，
#   裸 $var 紧跟多字节字符会吞掉变量内容，详见 lib/globals.sh 里的说明。

usage() {
    cat <<'HELP'
dog recv —— 从安卓手机取回文件或目录到电脑（send 的反方向）

用法
  dog recv [-s 序列号] [-o 本地目录] [-f] <手机路径>
  dog recv -l [手机目录]          列出手机目录内容（默认 /sdcard/Download/）

示例
  dog recv /sdcard/Download/a.pdf              取到当前目录
  dog recv -o ~/Desktop /sdcard/DCIM/Camera/   取整个目录到桌面
  dog recv -l                                  看看 Download 里有什么
  dog recv -l /sdcard/DCIM/Camera              列指定目录

选项
  -s <序列号>    指定 adb 设备；多台设备连接时不指定会提示选择
  -o <本地目录>  保存位置，默认当前目录
  -f             本地已存在同名文件时覆盖（默认拒绝，不静默覆盖）
  -l             列目录模式
  -h, --help     显示本帮助

说明
  手机路径带空格时记得加引号：dog recv '/sdcard/Download/a b.apk'
HELP
}

# 把路径包成手机端 sh 可安全解析的单引号串（路径里的单引号也处理掉）
shq_remote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

selected_device=""
outdir="."
force=false
list_mode=false
remote_path=""

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -s)
            shift
            if [ -z "$1" ] || [[ "$1" == -* ]]; then
                dog_error "参数 -s 需要设备序列号"; usage >&2; exit 1
            fi
            selected_device="$1"; shift ;;
        -o)
            shift
            if [ -z "$1" ] || [[ "$1" == -* ]]; then
                dog_error "参数 -o 需要本地目录"; usage >&2; exit 1
            fi
            outdir="$1"; shift ;;
        -f) force=true; shift ;;
        -l) list_mode=true; shift ;;
        -*) dog_error "未知参数: $1"; usage >&2; exit 1 ;;
        *)
            if [ -n "$remote_path" ]; then
                dog_error "只支持一个手机路径"; usage >&2; exit 1
            fi
            remote_path="$1"; shift ;;
    esac
done

dog_ensure_adb "取回操作" || exit 1

# ── 列目录模式 ──────────────────────────────────────────────
if [ "$list_mode" = true ]; then
    [ -z "$remote_path" ] && remote_path="/sdcard/Download/"
    dog_select_adb_device "列目录" "$selected_device" || exit 1
    selected_device="$DOG_SELECTED_ADB_DEVICE"
    dog_log "设备 ${selected_device}  目录 ${remote_path}"
    echo
    # 名字在最后一列之后，所以从第 8 个字段开始整段取回来，空格不会被拆
    # 字节数转人类可读：这个列表的用途就是帮你挑文件，原始字节数没法比较大小
    adb -s "$selected_device" shell "ls -l $(shq_remote "$remote_path")" 2>&1 \
      | awk 'function human(n) {
               if (n+0 == 0) return "0";
               split("B K M G T", u, " ");
               i = 1; while (n >= 1024 && i < 5) { n /= 1024; i++ }
               return sprintf((i==1 ? "%d%s" : "%.1f%s"), n, u[i]) }
             NR==1 && /^total/ {next}
             /^[-dl]/ {
               isdir = (substr($1,1,1)=="d");
               date = $6" "$7;
               name=""; for(i=8;i<=NF;i++) name=name (i>8?" ":"") $i;
               printf "  %-6s %8s  %s  %s\n", (isdir?"[目录]":""), (isdir?"-":human($5)), date, name; next }
             { print "  "$0 }'
    exit 0
fi

# ── 取回模式 ────────────────────────────────────────────────
if [ -z "$remote_path" ]; then
    dog_error "缺少手机路径"
    dog_log "不知道路径的话先看看： dog recv -l"
    usage >&2
    exit 1
fi

dog_select_adb_device "取回" "$selected_device" || exit 1
selected_device="$DOG_SELECTED_ADB_DEVICE"

# 先确认手机上存在，否则 adb pull 的报错很难看懂
if ! adb -s "$selected_device" shell "ls -d $(shq_remote "$remote_path")" >/dev/null 2>&1; then
    dog_error "手机上找不到: ${remote_path}"
    dog_log "用 dog recv -l <目录> 确认路径"
    exit 1
fi

# 手机上是文件还是目录
if adb -s "$selected_device" shell "[ -d $(shq_remote "$remote_path") ]" 2>/dev/null; then
    remote_is_dir=true
else
    remote_is_dir=false
fi

if [ ! -d "$outdir" ]; then
    dog_log "本地目录不存在，创建: ${outdir}"
    mkdir -p "$outdir" || { dog_error "无法创建目录: ${outdir}"; exit 1; }
fi

base="$(basename "${remote_path%/}")"
dest="${outdir%/}/${base}"

if [ -e "$dest" ] && [ "$force" = false ]; then
    dog_error "本地已存在: ${dest}"
    dog_log "要覆盖请加 -f，或用 -o 换个目录"
    exit 1
fi

dog_log "设备: ${selected_device}"
dog_log "手机: ${remote_path}"
dog_log "本地: ${dest}"
echo

if adb -s "$selected_device" pull "$remote_path" "$dest"; then
    echo
    if [ "$remote_is_dir" = true ]; then
        n=$(find "$dest" -type f 2>/dev/null | wc -l | tr -d ' ')
        dog_success "取回成功: ${dest}  (${n} 个文件, $(du -sh "$dest" 2>/dev/null | cut -f1 | tr -d ' '))"
    else
        dog_success "取回成功: ${dest}  ($(du -h "$dest" 2>/dev/null | cut -f1 | tr -d ' '))"
    fi
else
    dog_error "取回失败"
    exit 1
fi
