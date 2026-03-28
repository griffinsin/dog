#!/bin/bash

# Description: 安装 Android Debug Bridge (ADB) 工具

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# 安装 Android Debug Bridge (adb) 命令实现
dog_log "开始安装 Android Debug Bridge (adb)..."

dog_log "安装 adb"
dog_log "brew install --cask android-platform-tools"

# 执行安装命令
if brew install --cask android-platform-tools; then
    dog_success "adb 安装成功！"
    dog_log "您现在可以使用 adb 命令了"
    
    # 显示 adb 版本信息
    dog_log "adb 版本信息："
    adb version
else
    dog_error "adb 安装失败，请检查错误信息并重试"
fi
