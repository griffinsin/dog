#!/bin/bash

# Load global variables and functions
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh
# Load shared command functions
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/command_functions.sh

# Flutter project cleanup command implementation
dog_log "开始清理 Flutter 项目..."

# 调用共享函数库中的清理函数
if run_pubclean; then
    dog_success "Flutter 项目清理完成！"
else
    dog_error "Flutter 项目清理失败！"
fi
