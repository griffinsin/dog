#!/bin/bash

# Description: 战网安装卡死问题解决

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# Battle.net 客户端修复指南
dog_log "显示 Battle.net 客户端修复指南..."

echo ""
echo "===== Battle.net 客户端修复指南 ====="
echo ""
echo "当 Battle.net 客户端出现问题时，请按照以下步骤修复："
echo ""
echo "1. 删除 /Users/Shared/ 目录下的 Battle.net 文件夹"
echo "   命令: rm -rf /Users/Shared/Battle.net"
echo ""
echo "2. 从暴雪官网下载 Battle.net 安装程序（美国/英文区域）"
echo "   官方下载地址: https://www.blizzard.com/en-us/download/"
echo ""
echo "3. 打开终端并运行以下命令以指定区域和语言："
echo "   open -a ~/Downloads/Battle.net-Setup.app --args --locale=enUS --region=US --session="
echo ""
echo "4. 按回车键执行命令，Battle.net 将以美国/英文区域设置启动"
echo ""
echo "=========================="
echo ""

dog_success "Battle.net 客户端修复指南已显示"
