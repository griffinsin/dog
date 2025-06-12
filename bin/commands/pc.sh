#!/bin/bash

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# pc 命令实现
dog_log "正在打开 PyCharm..."
open -a "PyCharm" .
dog_success "已启动 PyCharm 并打开当前目录"
