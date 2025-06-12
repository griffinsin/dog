#!/bin/bash

# Load global variables and functions
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# 文件查找命令实现
dog_log "开始查找文件..."

search_term="$1"

if [ -z "$search_term" ]; then
    dog_error "用法: dog find <搜索词>"
    exit 1
fi

dog_log "如果要查找所有子目录 find . -name \"*$search_term*\" "
dog_log "如果仅查找当前目录 find . -name *$search_term* "

# 使用 find 命令来查找当前目录下所有文件名包含指定字符串的文件
find . -name "*$search_term*"

dog_success "查找完成"
