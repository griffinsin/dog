#!/bin/bash

# Description: 启动 Android Studio 并打开当前目录

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# as 命令实现
dog_log "正在打开 Android Studio..."
open -a "Android Studio" .
dog_success "已启动 Android Studio 并打开当前目录"
