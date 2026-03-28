#!/bin/bash

# Description: 图片压缩指南

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# img 命令实现
dog_log "ImageMagick 使用指南"
echo ""

echo "安装 ImageMagick:"
print_color "$BLUE" "brew install imagemagick"
echo ""
echo ""

echo "压缩图片质量:"
print_color "$BLUE" "magick input.jpg -quality 85 output.jpg"
echo ""
echo ""

echo "调整图片大小:"
print_color "$BLUE" "magick input.png -resize 50% output.png"
echo ""

dog_success "ImageMagick 使用指南显示完成"
