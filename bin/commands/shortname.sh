#!/bin/bash

# Description: 批量简化文件名（提取年月等级N与seg信息）

# Load global variables and functions
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

usage() {
    echo "用法: dog shortname [-p 目录]"
    echo "  -p  指定要处理的目录（默认当前目录）"
    echo ""
    echo "规则:"
    echo "  输入:  YYYY年M(M)月日语N1..N5...-segXX.<任意后缀>"
    echo "  输出:  YYYY-MM-N?-segXX.<原后缀>"
}

TARGET_DIR="."

while getopts ":p:h" opt; do
    case "$opt" in
        p)
            TARGET_DIR="$OPTARG"
            ;;
        h)
            usage
            exit 0
            ;;
        :)
            dog_error "参数 -$OPTARG 需要值"
            usage
            exit 1
            ;;
        \?)
            dog_error "未知参数: -$OPTARG"
            usage
            exit 1
            ;;
    esac
done
shift $((OPTIND - 1))

if [ $# -ne 0 ]; then
    dog_error "不支持额外参数"
    usage
    exit 1
fi

if [ ! -d "$TARGET_DIR" ]; then
    dog_error "目录不存在: $TARGET_DIR"
    exit 1
fi

processed=0
renamed=0
skipped_no_match=0
skipped_exists=0
skipped_same=0

for f in "$TARGET_DIR"/*; do
    [ -e "$f" ] || continue
    [ -f "$f" ] || continue

    processed=$((processed + 1))

    base="$(basename "$f")"

    if [[ "$base" =~ ^([0-9]{4})年([0-9]{1,2})月日语(N[1-5]).*-(seg[0-9]+)(\.[^./]+)$ ]]; then
        y="${BASH_REMATCH[1]}"
        m_raw="${BASH_REMATCH[2]}"
        n="${BASH_REMATCH[3]}"
        seg="${BASH_REMATCH[4]}"
        ext="${BASH_REMATCH[5]}"

        m=$(printf "%02d" "$m_raw")
        new_base="${y}-${m}-${n}-${seg}${ext}"
        new_path="${TARGET_DIR%/}/${new_base}"

        if [ "$f" = "$new_path" ]; then
            skipped_same=$((skipped_same + 1))
            continue
        fi

        if [ -e "$new_path" ]; then
            skipped_exists=$((skipped_exists + 1))
            dog_error "目标已存在，跳过: $new_base"
            continue
        fi

        if mv -n -- "$f" "$new_path"; then
            renamed=$((renamed + 1))
            dog_log "$base -> $new_base"
        else
            dog_error "重命名失败: $base"
        fi
    else
        skipped_no_match=$((skipped_no_match + 1))
    fi

done

dog_success "处理完成"
dog_log "总文件数: $processed"
dog_log "成功重命名: $renamed"
dog_log "跳过（不匹配规则）: $skipped_no_match"
dog_log "跳过（目标已存在）: $skipped_exists"
dog_log "跳过（已是目标名）: $skipped_same"
