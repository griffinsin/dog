#!/bin/bash

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# 重置 Mac 密码指南
dog_log "显示 Mac 密码重置指南..."

echo ""
echo "===== Mac 密码重置指南 ====="
echo ""
echo "1. 重启 Mac 并同时按下 Command+R，进入恢复模式。"
echo ""
echo "2. 进入「菜单栏-实用程序-终端」，输入命令「resetpassword」回车运行，调出密码重置工具。"
echo ""
echo "3. 选择包含密码的启动磁盘卷宗、需重设密码的用户账户；输入并确认新的用户密码，点击「重设」。"
echo ""
echo "4. 重启完成后，使用新密码登录即可。"
echo ""
echo "=========================="
echo ""

dog_success "密码重置指南已显示"
