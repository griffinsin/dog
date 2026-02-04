#!/bin/bash

# Description: Mac电脑屏幕损坏如何使用外部显示器

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# Mac 屏幕镜像切换快捷键信息
dog_log "显示 Mac 屏幕镜像切换快捷键信息..."

echo ""
echo "===== Mac 屏幕镜像切换快捷键 ====="
echo ""
echo "当 Mac 屏幕出现问题时，可以使用以下快捷键切换到扩展屏幕镜像模式："
echo ""
echo "同时按下 Command 键和亮度减少键(F1)，保持按住约 2 秒钟"
echo "屏幕将自动切换为主屏幕镜像模式"
echo ""
echo "这对于 Mac 屏幕损坏但需要使用外接显示器的情况特别有用"
echo ""
echo "=========================="
echo ""

dog_success "屏幕镜像切换快捷键信息已显示"
