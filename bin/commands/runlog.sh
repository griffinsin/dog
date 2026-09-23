#!/bin/bash

# Description: 运行 Flutter 工程并在新窗口按关键字过滤日志

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# 一键运行 + 按关键字过滤日志。
#
#   当前窗口（A）：flutter run 2>&1 | tee <日志文件>  —— 完整输出，选设备、r / R / q 都在这里
#   新开窗口（B）：只显示命中关键字的行，标题为「B · 设备名 · 关键字」
#
# 关键字要取日志正文里的内容。不要用 'flutter:' 这种平台前缀：
# iOS 是 "flutter: xxx"，Android 是 "I/flutter (pid): xxx"，换平台就匹配不上。
#
# 停止 flutter run 用 q 或 Ctrl+C，不要用 Ctrl+Z。
# Ctrl+Z 只是把进程冻住，冻住的 devicectl / lldb 会一直占着设备，
# 下一次运行就会永远停在 "Installing and launching..."。
# 本命令启动前会自动清理这类挂起（状态 T）的进程。
#
# ───────────────────────── 给维护者 ─────────────────────────
#
# 【运行环境】只支持 macOS + 系统自带 Terminal.app。
#   - B 窗口靠 osascript 驱动 Terminal.app 打开。首次运行时系统会弹窗询问是否允许
#     控制 Terminal，拒绝后 B 打不开（A 照常运行）。换 iTerm2 要重写 AppleScript 那段。
#   - 原始脚本是 zsh，搬进 dog 时改写为 bash（bin/dog 是 bash 且用 source 执行子命令）。
#     zsh 的 ${(q)x} 换成 printf '%q'（bash 3.2 没有 ${x@Q}），
#     ${device% in (debug|profile|release) mode*} 换成 BASH_REMATCH 正则——
#     bash 的参数展开不支持 (a|b) 这种交替，直接搬会静默失效。
#   - 工程目录就是当前目录：本命令约定你先 cd 到 Flutter 工程再执行。
#
# 【为什么是 tee + tail，而不是 flutter logs】
#   flutter logs 没有过滤参数，而且会丢日志：Android 上只放行 flutter 等少数 tag
#   （源码 AdbLogReader._allowedTags），app 进程内插件用自有 tag 打的 native 日志全没；
#   iOS（Xcode 26 / CoreDevice）要依赖 flutter run 建立的连接，单独跑可能一行都没有。
#   所以只能让 flutter run 自己的输出落盘，再由 B 读这个文件过滤。
#   用文件而不用命名管道：没人读时文件不会让 A 阻塞，也能随时另开终端换关键字重新过滤。
#
# 【为什么 B 要等选定设备后才打开】
#   窗口标题要带设备名，而设备要在 A 里选完才知道。B 从日志第一行读，晚开不会漏日志；
#   还没选设备就退出（Ctrl+C / 没有设备）时 B 根本不会打开。
#   设备名取自 flutter run 的这一行输出（见 LAUNCH_RE）：
#     Launching lib/main.dart on <设备名> in debug mode...
#   这是 flutter 的输出文案，不是公开接口。flutter 升级后如果它变了，表现是
#   「A 正常运行但 B 一直不出现」，不会报错——出现这种情况先检查这一行。
#
# 【这些细节不能删，删了只会表现为「B 没日志」，不会报错】
#   - 2>&1：flutter run 有一部分输出走 stderr，不合并就进不了日志文件。
#   - grep --line-buffered：grep 的输出进 Terminal 前会先攒一批，不加就不是实时显示。
#   - grep -F：关键字按普通文字匹配，[ ] . * 这些符号不会被当成正则。
#   - grep --：关键字以 - 开头时，不会被 grep 当成选项。
#   - tail -F（大写）：文件被删掉重建（换了 inode）后会跟到新文件；小写 -f 会一直盯着
#     已删除的旧文件。清空（: > 文件）两者都能处理。
#   - OPTIND=1：bin/dog 用 source 执行子命令，OPTIND 是同一个 shell 的全局变量，
#     不手动重置的话第二次解析会从上次的位置继续。
#
# 【日志文件】放在 $TMPDIR（macOS 下每用户隔离，权限 drwx------）而不是 /tmp。
#   /tmp 下用 : > 建出来的文件是 644，同机器其他账户可读，而完整日志可能含连接令牌、
#   分享链接原文。文件名带 PID，同时跑多个互不覆盖；另建 .latest 软链指向最近一次，
#   方便随时另开终端换关键字重新过滤。
#
# 【安全】完整日志可能含连接令牌、分享链接原文。不要整份外发，只发 B 过滤后的片段。

_tmp_base="${TMPDIR:-/tmp}"
_tmp_base="${_tmp_base%/}"
LOG_FILE="$_tmp_base/dog_runlog.$$"
LOG_LATEST="$_tmp_base/dog_runlog.latest"

# flutter run 选定设备后打出的那一行：Launching lib/main.dart on <设备名> in debug mode...
LAUNCH_RE='^Launching [^ ]+ on .* in (debug|profile|release) mode'
DEVICE_RE='^Launching [^ ]+ on (.+) in (debug|profile|release) mode'

usage() {
    echo "用法: dog runlog [-n] '关键字' [flutter run 的额外参数...]"
    echo "  关键字        必填，按普通文字匹配，[ ] 等符号不需要转义"
    echo "  其余参数      原样传给 flutter run，例如 dog runlog 'Critical' --release"
    echo "  -n           只打印将要执行的命令，不开窗口、不清理进程、不运行"
    echo "  -h           显示帮助信息"
    echo ""
    echo "关键字以 - 开头时，先写 -- 隔开：dog runlog -- '-xxx'"
    echo ""
    echo "当前窗口跑 flutter run（选设备、r / R / q 都在这里），"
    echo "选定设备后自动新开一个窗口，只显示命中关键字的行。"
    echo "需先 cd 到 Flutter 工程目录再执行。"
}

# bash 3.2 没有 ${x@Q}，用 printf %q 做 shell 转义（等价于 zsh 的 ${(q)x}）
shq() { printf '%q' "$1"; }

dry_run=false
OPTIND=1   # 见上方【这些细节不能删】
while getopts ":nh" opt; do
    case $opt in
        n) dry_run=true ;;
        h) usage; exit 0 ;;
        \?) dog_error "未知选项 -$OPTARG"; usage >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

keyword="${1:-}"
if [ -z "$keyword" ]; then
    dog_error "缺少关键字"
    usage >&2
    exit 1
fi
shift

if ! command -v flutter >/dev/null 2>&1; then
    dog_error "未找到 flutter 命令，请先安装或配置 Flutter"
    exit 1
fi

if [ ! -f "pubspec.yaml" ]; then
    dog_error "当前目录不是 Flutter 工程（没有 pubspec.yaml）"
    dog_log "请先 cd 到 Flutter 工程目录再执行"
    exit 1
fi

CMD_B="tail -n +1 -F $(shq "$LOG_FILE") | grep --line-buffered -F -- $(shq "$keyword")"

if [ "$dry_run" = true ]; then
    extra=""
    for a in "$@"; do extra="$extra $(shq "$a")"; done
    echo "A（当前窗口）: flutter run$extra 2>&1 | tee $(shq "$LOG_FILE")"
    echo "B（选定设备后新开）: $CMD_B"
    exit 0
fi

# 等日志里出现选定设备那一行，取出设备名，再开 B 窗口。
# 用轮询而不是 tail -F：这个函数跑在后台，A 退出时直接 kill 它即可，
# 不会留下没人收拾的 tail 子进程。
open_filter_window_when_device_known() {
    local line device
    while true; do
        line=$(grep -m1 -E "$LAUNCH_RE" "$LOG_FILE" 2>/dev/null) && break
        sleep 0.5
    done

    device="$line"
    if [[ "$line" =~ $DEVICE_RE ]]; then
        device="${BASH_REMATCH[1]}"
    fi

    # 命令与标题经 argv 传给 AppleScript，不必再做一层 AppleScript 字符串转义
    osascript - "$CMD_B" "B · $device · $keyword" <<'APPLESCRIPT' >/dev/null
on run argv
  tell application "Terminal"
    set t to do script (item 1 of argv)
    set custom title of t to (item 2 of argv)
  end tell
end run
APPLESCRIPT
}

# 清理之前 Ctrl+Z 留下的挂起进程。
# 只动「当前用户 + 状态 T + 可执行文件名精确命中」的进程：
# 早期版本匹配的是完整命令行，Ctrl+Z 挂起的 `vim lib/flutter_xxx.dart` 会被 kill -9，
# 未保存内容直接丢失。改成只看 comm（可执行文件路径，不含参数）的 basename。
me=$(id -un)
stale=$(ps -U "$me" -o pid=,stat=,comm= 2>/dev/null | awk '
    $2 ~ /^T/ {
        path = $3
        for (i = 4; i <= NF; i++) path = path " " $i
        n = split(path, p, "/")
        exe = p[n]
        if (exe == "flutter" || exe == "dart" || exe == "devicectl" ||
            exe == "lldb"    || exe == "lldb-rpc-server")
            print $1 "\t" exe
    }')
# 外加本命令自己留下的 tee —— 靠日志文件名特征识别，不会误伤别人的 tee
stale_tee=$(ps -U "$me" -o pid=,stat=,command= 2>/dev/null \
            | awk '$2 ~ /^T/ && /dog_runlog/ {print $1 "\ttee(dog_runlog)"}')
[ -n "$stale_tee" ] && stale="${stale:+$stale$'\n'}$stale_tee"

if [ -n "$stale" ]; then
    dog_log "清理挂起（Ctrl+Z）的进程:"
    echo "$stale" | while IFS=$'\t' read -r p n; do echo "  $p  $n"; done
    echo "$stale" | cut -f1 | xargs kill -9 2>/dev/null || true
fi

# 清空上一次的日志：否则等待循环会读到上一次的设备名，B 也会先刷出旧内容。
# umask 077 放在子 shell 里，不影响 dog 后续行为。
( umask 077; : > "$LOG_FILE" )
ln -sfn "$LOG_FILE" "$LOG_LATEST" 2>/dev/null || true

open_filter_window_when_device_known &
watcher=$!
# A 退出（q / Ctrl+C / 构建失败）时结束等待循环；还没选设备就退出的话 B 不会打开
trap 'kill $watcher 2>/dev/null || true' EXIT INT TERM

dog_log "选定设备后会自动打开过滤窗口 B（关键字 [$keyword]）"
dog_log "完整日志: $LOG_FILE"
dog_log "         $LOG_LATEST -> 最近一次"
echo

flutter run "$@" 2>&1 | tee "$LOG_FILE"
exit "${PIPESTATUS[0]}"
