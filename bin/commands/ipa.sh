#!/bin/bash

# Description: iOS 应用包管理和安装工具 指南

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# ipa 命令实现
dog_log "ipatool 使用指南"
echo ""

echo "安装 ipatool:"
print_color "$BLUE" "brew tap majd/repo"
echo ""
print_color "$BLUE" "brew install ipatool"
echo ""
echo ""

echo "登录苹果账号:"
print_color "$BLUE" "ipatool auth login --email 你的邮箱 --password 你的密码"
echo ""
echo ""

echo "搜索与下载应用:"
print_color "$BLUE" "ipatool search 应用名称"
echo ""
print_color "$BLUE" "ipatool download -b com.公司.应用标识符"
echo ""
echo ""

dog_log "如果遇到以下错误:"
echo ""
print_color "$RED" "Your Apple ID does not have a license for this app. Download the app on an iOS device to obtain a license."
echo ""
echo "解决方法: 先在 iOS 设备上下载该应用获取许可证，然后再使用 ipatool 下载。"
echo ""

dog_success "ipatool 使用指南显示完成"
