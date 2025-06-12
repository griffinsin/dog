#!/bin/bash

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# 清理 Mac 系统命令实现
dog_log "开始清理 Mac 系统..."

# 检查 mac-cleanup 是否已安装
if ! command -v mac-cleanup &>/dev/null; then
    dog_log "mac-cleanup 未安装，正在安装..."
    
    # 添加仓库
    dog_log "添加 fwartner/tap 仓库..."
    brew tap fwartner/tap
    
    # 安装 mac-cleanup
    dog_log "安装 mac-cleanup..."
    brew install fwartner/tap/mac-cleanup
    
    # 检查安装是否成功
    if ! command -v mac-cleanup &>/dev/null; then
        dog_error "mac-cleanup 安装失败，无法继续清理操作"
        exit 1
    else
        dog_success "mac-cleanup 安装成功"
    fi
fi

# 运行 mac-cleanup
dog_log "运行 mac-cleanup 清理系统..."
mac-cleanup

dog_success "Mac 系统清理完成"
