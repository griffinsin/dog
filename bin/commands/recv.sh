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
# 【所有 adb 调用都要 </dev/null】adb 会从 stdin 读取并把它吞掉。
#   交互模式里打印目录菜单时要调 4 次 adb 查「N 项」，不重定向的话这 4 次
#   就把用户后面要输入的内容（或管道里的测试输入）全吃掉，表现是
#   「菜单刚打出来就自己选了默认值、然后直接取消」，不报错。实测：
#     printf 'A\nB\n' | bash -c 'adb shell "echo x">/dev/null; read -r a; echo "[$a]"'  -> []
#     加 </dev/null 之后                                                                 -> [A]
#   真实终端里同样会抢读 tty，可能吞掉你的按键，不只是测试问题。
#
# 【中文输出用 ${var} 不用 $var】macOS 自带 bash 3.2 在 UTF-8 locale 下，
#   裸 $var 紧跟多字节字符会吞掉变量内容，详见 lib/globals.sh 里的说明。

usage() {
    cat <<'HELP'
dog recv —— 从安卓手机取回文件或目录到电脑（send 的反方向）

用法
  dog recv                        交互：选目录 -> 按序号选文件（推荐）
  dog recv [-s 序列号] [-o 本地目录] [-f] <手机路径>
  dog recv -l [手机目录]            只列出目录内容，不取回

交互模式（不带手机路径时进入）
  先从 4 个常用目录里按序号选一个（或手动输入路径），
  再从文件列表里按序号选，列表按修改时间倒序——刚截的图、刚录的屏就在第 1 条。
  选择支持 1 / 1,3 / 1-3 这几种写法，和 dog bili 的 --pick 一致。

示例
  dog recv                                     全程按序号选
  dog recv /sdcard/Download/a.pdf              已知路径，直接取到当前目录
  dog recv -o ~/Desktop /sdcard/DCIM/Camera/   取整个目录到桌面
  dog recv -l /sdcard/DCIM/Camera              只看不取

选项
  -s <序列号>    指定 adb 设备；多台设备连接时不指定会提示选择
  -o <本地目录>  保存位置，默认当前目录
  -f             本地已存在同名文件时覆盖（默认拒绝，不静默覆盖）
  -l             只列目录，不取回
  -h, --help     显示本帮助

说明
  直接给手机路径时，带空格的要加引号：dog recv '/sdcard/Download/a b.apk'
  交互模式按序号选，不存在这个问题。
HELP
}

# 把路径包成手机端 sh 可安全解析的单引号串（路径里的单引号也处理掉）
shq_remote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# 常用目录表。实测这 4 个目录下都没有子目录，所以不需要目录导航逻辑；
# 万一以后出现子目录，列表会标出 [目录]，选中它就是整个取回（adb pull 原生支持）。
COMMON_LABELS=("下载" "相机" "截图" "录屏")
COMMON_PATHS=("/sdcard/Download" "/sdcard/DCIM/Camera" "/sdcard/DCIM/Screenshots" "/sdcard/DCIM/Screen recordings")

# 解析 "1" / "1,3" / "1-3" / "2-" 这类选择，输出去重后的有序序号。
# 语法与 dog bili 的 --pick 保持一致，用户只需记一套。
parse_sel() {
    local spec max out a b i chunk
    spec=$(printf '%s' "$1" | tr -d ' ' | tr ',' ' ')
    max="$2"; out=""
    for chunk in $spec; do
        case "$chunk" in
            *-*) a="${chunk%%-*}"; b="${chunk##*-}"
                 [ -z "$a" ] && a=1
                 [ -z "$b" ] && b="$max" ;;
            *)   a="$chunk"; b="$chunk" ;;
        esac
        case "$a" in ''|*[!0-9]*) return 1 ;; esac
        case "$b" in ''|*[!0-9]*) return 1 ;; esac
        [ "$a" -gt "$b" ] && return 1
        i="$a"
        while [ "$i" -le "$b" ]; do
            if [ "$i" -ge 1 ] && [ "$i" -le "$max" ]; then
                case " $out " in *" $i "*) ;; *) out="$out $i" ;; esac
            fi
            i=$((i + 1))
        done
    done
    [ -z "$out" ] && return 1
    printf '%s' "$out"
}

# 读取一个手机目录，填充 LIST_NAME / LIST_SIZE / LIST_DATE / LIST_ISDIR 四个数组。
# 用 awk 先整理成 TAB 分隔再交给 bash 读：文件名可能带空格，TAB 不会出现在文件名里。
# ls -lt 按修改时间倒序（实测该机 toybox 0.8.11 支持 -t，带空格的目录也正常）。
LIST_NAME=(); LIST_SIZE=(); LIST_DATE=(); LIST_ISDIR=()
load_listing() {
    local dev="$1" dir="$2" t sz dt nm
    LIST_NAME=(); LIST_SIZE=(); LIST_DATE=(); LIST_ISDIR=()
    while IFS=$'\t' read -r t sz dt nm; do
        [ -z "$nm" ] && continue
        LIST_ISDIR[${#LIST_ISDIR[@]}]="$t"
        LIST_SIZE[${#LIST_SIZE[@]}]="$sz"
        LIST_DATE[${#LIST_DATE[@]}]="$dt"
        LIST_NAME[${#LIST_NAME[@]}]="$nm"
    done < <(adb -s "$dev" shell "ls -lt $(shq_remote "$dir")" </dev/null 2>/dev/null | tr -d '\r' | awk '
        function human(n) {
            if (n+0 == 0) return "0";
            split("B K M G T", u, " ");
            i = 1; while (n >= 1024 && i < 5) { n /= 1024; i++ }
            return sprintf((i==1 ? "%d%s" : "%.1f%s"), n, u[i]) }
        /^total/ {next}
        /^[-dl]/ {
            isdir = (substr($1,1,1)=="d") ? "d" : "f";
            name=""; for (i=8; i<=NF; i++) name = name (i>8 ? " " : "") $i;
            if (name == "" ) next;
            printf "%s\t%s\t%s\t%s\n", isdir, (isdir=="d" ? "-" : human($5)), $6" "$7, name; next }')
}

print_listing() {
    local i n
    n=${#LIST_NAME[@]}
    i=0
    while [ "$i" -lt "$n" ]; do
        printf "  %3d) %-6s %8s  %s  %s\n" "$((i + 1))" \
            "$([ "${LIST_ISDIR[$i]}" = d ] && echo '[目录]' || echo '')" \
            "${LIST_SIZE[$i]}" "${LIST_DATE[$i]}" "${LIST_NAME[$i]}"
        i=$((i + 1))
    done
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
    adb -s "$selected_device" shell "ls -l $(shq_remote "$remote_path")" </dev/null 2>&1 \
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

# ── 交互模式：没给手机路径时，全程按序号选 ────────────────────
# 手机侧路径没法 tab 补全，手敲最烦的恰恰是 /sdcard/DCIM/Screen recordings
# 这种带空格的；按序号选把引号问题一并消灭了。
interactive=false
picked_names=()

if [ -z "$remote_path" ]; then
    interactive=true
    dog_select_adb_device "取回" "$selected_device" || exit 1
    selected_device="$DOG_SELECTED_ADB_DEVICE"

    # 选目录：4 个常用目录 + 手动输入
    print_color "$CYAN" "选择目录:"
    i=0
    while [ "$i" -lt "${#COMMON_PATHS[@]}" ]; do
        cnt=$(adb -s "$selected_device" shell "ls -1 $(shq_remote "${COMMON_PATHS[$i]}") 2>/dev/null | wc -l" </dev/null 2>/dev/null | tr -d '\r' | tr -d ' ')
        [ -z "$cnt" ] && cnt=0
        printf "  %d) %-5s %-32s %s 项\n" "$((i + 1))" "${COMMON_LABELS[$i]}" "${COMMON_PATHS[$i]}" "$cnt"
        i=$((i + 1))
    done
    manual=$((${#COMMON_PATHS[@]} + 1))
    printf "  %d) 手动输入路径\n" "$manual"

    while true; do
        printf "请选择 [1-%d] (默认 1): " "$manual"
        read -r ans
        [ -z "$ans" ] && ans=1
        case "$ans" in
            ''|*[!0-9]*) dog_error "无效选择"; continue ;;
        esac
        if [ "$ans" -ge 1 ] && [ "$ans" -le "${#COMMON_PATHS[@]}" ]; then
            remote_path="${COMMON_PATHS[$((ans - 1))]}"
            break
        elif [ "$ans" -eq "$manual" ]; then
            printf "输入手机目录路径: "
            read -r remote_path
            [ -z "$remote_path" ] && { dog_error "已取消"; exit 1; }
            break
        fi
        dog_error "无效选择"
    done
    echo

    # 列文件，按序号选
    load_listing "$selected_device" "$remote_path"
    total=${#LIST_NAME[@]}
    if [ "$total" -eq 0 ]; then
        dog_error "目录为空或不可读: ${remote_path}"
        exit 1
    fi
    print_color "$CYAN" "${remote_path}  (按修改时间倒序，共 ${total} 项)"
    print_listing
    echo

    while true; do
        printf "选择要取回的 [如 1 / 1,3 / 1-3，回车取消]: "
        read -r sel
        [ -z "$sel" ] && { dog_error "已取消"; exit 1; }
        if idxs=$(parse_sel "$sel" "$total"); then
            break
        fi
        dog_error "无效选择，请重新输入"
    done

    for n in $idxs; do
        picked_names[${#picked_names[@]}]="${LIST_NAME[$((n - 1))]}"
    done
    echo
else
    dog_select_adb_device "取回" "$selected_device" || exit 1
    selected_device="$DOG_SELECTED_ADB_DEVICE"
fi

if [ ! -d "$outdir" ]; then
    dog_log "本地目录不存在，创建: ${outdir}"
    mkdir -p "$outdir" || { dog_error "无法创建目录: ${outdir}"; exit 1; }
fi

# 取回一个手机路径。两种模式共用：交互模式按选中的文件逐个调，直接模式调一次。
# 返回 0 成功 / 1 失败 / 2 跳过（本地已存在且未加 -f）
pull_one() {
    local rp="$1" base dest is_dir n

    if ! adb -s "$selected_device" shell "ls -d $(shq_remote "$rp")" </dev/null >/dev/null 2>&1; then
        dog_error "手机上找不到: ${rp}"
        dog_log "用 dog recv -l <目录> 确认路径"
        return 1
    fi

    if adb -s "$selected_device" shell "[ -d $(shq_remote "$rp") ]" </dev/null 2>/dev/null; then
        is_dir=true
    else
        is_dir=false
    fi

    base="$(basename "${rp%/}")"
    dest="${outdir%/}/${base}"

    if [ -e "$dest" ] && [ "$force" = false ]; then
        dog_error "本地已存在，跳过: ${dest}"
        dog_log "要覆盖请加 -f，或用 -o 换个目录"
        return 2
    fi

    dog_log "取回: ${rp}"
    if adb -s "$selected_device" pull "$rp" "$dest" </dev/null; then
        if [ "$is_dir" = true ]; then
            n=$(find "$dest" -type f 2>/dev/null | wc -l | tr -d ' ')
            dog_success "-> ${dest}  (${n} 个文件, $(du -sh "$dest" 2>/dev/null | cut -f1 | tr -d ' '))"
        else
            dog_success "-> ${dest}  ($(du -h "$dest" 2>/dev/null | cut -f1 | tr -d ' '))"
        fi
        return 0
    fi
    dog_error "取回失败: ${rp}"
    return 1
}

dog_log "设备: ${selected_device}"
echo

ok=0; failed=0; skipped=0

if [ "$interactive" = true ]; then
    base_dir="${remote_path%/}"
    for name in "${picked_names[@]}"; do
        pull_one "${base_dir}/${name}"
        case $? in
            0) ok=$((ok + 1)) ;;
            2) skipped=$((skipped + 1)) ;;
            *) failed=$((failed + 1)) ;;
        esac
        echo
    done
    if [ $((ok + failed + skipped)) -gt 1 ]; then
        dog_log "完成: 成功 ${ok}，跳过 ${skipped}，失败 ${failed} -> $(cd "$outdir" 2>/dev/null && pwd || echo "$outdir")"
    fi
else
    pull_one "$remote_path"
    case $? in
        0) ;;
        *) exit 1 ;;
    esac
fi

[ "$failed" -gt 0 ] && exit 1
exit 0
