#!/bin/bash

# Load global variables and functions
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# 文件查找命令实现
dog_log "开始查找文件..."

# 检查是否有 -c 参数（区分大小写）
case_sensitive=false
if [ "$1" = "-c" ]; then
    case_sensitive=true
    shift
    dog_log "启用区分大小写搜索"
fi

search_term="$1"

if [ -z "$search_term" ]; then
    dog_error "用法: dog find [-c] <搜索词>"
    dog_error "  -c: 区分大小写搜索（默认不区分大小写）"
    exit 1
fi

# 根据是否区分大小写使用不同的 find 命令选项
if [ "$case_sensitive" = true ]; then
    dog_log "执行区分大小写搜索: find . -name \"*$search_term*\" "
    find . -name "*$search_term*"
else
    dog_log "执行不区分大小写搜索: find . -iname \"*$search_term*\" "
    find . -iname "*$search_term*"
fi

dog_success "查找完成"
