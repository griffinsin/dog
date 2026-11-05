#!/bin/bash

# Description: 删除安卓手机内的 .bundle 文件（列出、确认后删除）

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# ───────────────────────── 给维护者 ─────────────────────────
#
# 配套 dog bundle/send 的清理命令：bundle 产物经 send 推到手机(默认 /sdcard/Download)，
# 搬运完就成了垃圾，本命令扫出来删掉。
#
# 【删除是不可逆操作，必须先列后确认】扫描目录里的 *.bundle，编号列出，用户选中后
#   再次确认才真删；-y 可跳过确认（给脚本/批量用）。绝不静默批删。
#
# 【只删 .bundle，只在指定目录，不递归】范围写死得很窄：默认 /sdcard/Download，
#   只匹配扩展名 .bundle，不碰子目录、不碰别的类型 —— 删手机文件不容许「宽泛匹配」。
#
# 【adb 调用都 </dev/null】adb 吞 stdin，交互里会抢读用户后续输入（recv 里详述）。
#
# 【手机侧路径加引号】走 adb shell 的 ls/rm 一律用 shq_remote 包单引号，文件名带
#   空格也不会被手机端 sh 拆开。
#
# 【中文输出用 ${var}】bash 3.2 UTF-8 locale 下裸 $var 紧跟多字节会吞字，见 globals.sh。

usage() {
    cat <<'HELP'
dog deletebundle —— 删除安卓手机内的 .bundle 文件

用法
  dog deletebundle                     扫描 /sdcard/Download，列出 .bundle 选择删除
  dog deletebundle -d <手机目录>        指定扫描目录
  dog deletebundle -s <序列号>          指定 adb 设备
  dog deletebundle -y                   跳过确认（配合选择使用需谨慎）
  dog deletebundle -h, --help           显示本帮助

选择
  列出后按序号选：1 / 1,3 / 1-3，或输入 all 全选，回车取消。
  删除前会再确认一次（-y 跳过）。

说明
  只删扩展名为 .bundle 的文件，只在指定目录内，不递归、不碰其它类型。
  删除不可逆，请看清列表再确认。
HELP
}

selected_device=""
scan_dir="/sdcard/Download"
assume_yes=false

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -s)
            shift
            if [ -z "$1" ] || [[ "$1" == -* ]]; then
                dog_error "参数 -s 需要设备序列号"; usage >&2; exit 1
            fi
            selected_device="$1"; shift ;;
        -d)
            shift
            if [ -z "$1" ] || [[ "$1" == -* ]]; then
                dog_error "参数 -d 需要手机目录"; usage >&2; exit 1
            fi
            scan_dir="$1"; shift ;;
        -y) assume_yes=true; shift ;;
        -*) dog_error "未知参数: $1"; usage >&2; exit 1 ;;
        *) dog_error "不支持的参数: $1"; usage >&2; exit 1 ;;
    esac
done

scan_dir="${scan_dir%/}"

# 手机端安全引用
shq_remote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# 解析 1 / 1,3 / 1-3 选择为去重有序序号
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

dog_ensure_adb "删除操作" || exit 1
dog_select_adb_device "删除 .bundle" "$selected_device" || exit 1
selected_device="$DOG_SELECTED_ADB_DEVICE"

dog_log "设备: ${selected_device}"
dog_log "扫描: ${scan_dir}/*.bundle"
echo

# 列出 .bundle：ls -lt 按时间倒序，awk 过滤扩展名 .bundle，TAB 分隔防文件名空格
B_NAME=(); B_SIZE=(); B_DATE=()
while IFS=$'\t' read -r sz dt nm; do
    [ -z "$nm" ] && continue
    B_SIZE[${#B_SIZE[@]}]="$sz"
    B_DATE[${#B_DATE[@]}]="$dt"
    B_NAME[${#B_NAME[@]}]="$nm"
done < <(adb -s "$selected_device" shell "ls -lt $(shq_remote "$scan_dir")" </dev/null 2>/dev/null | tr -d '\r' | awk '
    function human(n) {
        if (n+0 == 0) return "0";
        split("B K M G T", u, " ");
        i = 1; while (n >= 1024 && i < 5) { n /= 1024; i++ }
        return sprintf((i==1 ? "%d%s" : "%.1f%s"), n, u[i]) }
    /^total/ {next}
    /^-/ {
        name=""; for (i=8; i<=NF; i++) name = name (i>8 ? " " : "") $i;
        if (name !~ /\.bundle$/) next;
        printf "%s\t%s\t%s\n", human($5), $6" "$7, name }')

total=${#B_NAME[@]}
if [ "$total" -eq 0 ]; then
    dog_log "没有找到 .bundle 文件: ${scan_dir}"
    exit 0
fi

print_color "$CYAN" "${scan_dir}  (共 ${total} 个 .bundle，按修改时间倒序)"
i=0
while [ "$i" -lt "$total" ]; do
    printf "  %3d) %8s  %s  %s\n" "$((i + 1))" "${B_SIZE[$i]}" "${B_DATE[$i]}" "${B_NAME[$i]}"
    i=$((i + 1))
done
echo

# 选择
while true; do
    printf "选择要删除的 [如 1 / 1,3 / 1-3 / all，回车取消]: "
    read -r sel
    [ -z "$sel" ] && { dog_error "已取消"; exit 1; }
    case "$(printf '%s' "$sel" | tr 'A-Z' 'a-z')" in
        all|a) idxs=""; i=1; while [ "$i" -le "$total" ]; do idxs="$idxs $i"; i=$((i+1)); done; break ;;
        *) if idxs=$(parse_sel "$sel" "$total"); then break; fi
           dog_error "无效选择，请重新输入" ;;
    esac
done

# 待删清单
to_delete=()
for n in $idxs; do to_delete[${#to_delete[@]}]="${B_NAME[$((n - 1))]}"; done

echo
print_color "$YELLOW" "将删除以下 ${#to_delete[@]} 个文件（手机上，不可恢复）："
for nm in "${to_delete[@]}"; do echo "  ${scan_dir}/${nm}"; done
echo

# 确认
if [ "$assume_yes" = false ]; then
    printf "确认删除？[y/N]: "
    read -r ans
    case "$ans" in [Yy]*) ;; *) dog_error "已取消"; exit 1 ;; esac
fi

ok=0; failed=0
for nm in "${to_delete[@]}"; do
    rp="${scan_dir}/${nm}"
    if adb -s "$selected_device" shell "rm -f $(shq_remote "$rp")" </dev/null >/dev/null 2>&1; then
        dog_success "已删除: ${nm}"
        ok=$((ok + 1))
    else
        dog_error "删除失败: ${nm}"
        failed=$((failed + 1))
    fi
done

echo
dog_log "完成：成功 ${ok}，失败 ${failed}"
[ "$failed" -gt 0 ] && exit 1
exit 0
