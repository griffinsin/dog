#!/bin/bash

# Load global variables and functions
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# Flutter project cleanup command implementation
dog_log "开始清理 Flutter 项目..."

# 检查当前目录是否是Git仓库
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    dog_log "执行 flutter clean..."
    flutter clean
    
    dog_log "删除所有 .lock 文件..."
    dog_log "find . -name '*.lock' -type f -print -exec rm -rf {} \;"
    find . -name '*.lock' -type f -print -exec rm -rf {} \;
    
    dog_log "执行 flutter pub get..."
    flutter pub get
    
    dog_success "Flutter 项目清理完成！"
else
    dog_error "当前目录不是一个Git仓库，操作未执行。"
fi
