#!/bin/bash

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# hello 命令实现
dog_log "你好，世界！"
dog_success "hello 命令执行成功"
