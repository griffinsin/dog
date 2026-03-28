#!/bin/bash

# Description: dog升级版本

# Load global variables and functions
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# Upgrade command implementation
dog_log "开始升级 dog 工具..."

# Uninstall current version
dog_log "卸载当前版本..."
brew uninstall dog 2>/dev/null || dog_log "当前未安装 dog"

# Untap and retap the repository
dog_log "移除并重新添加 tap 仓库..."
brew untap griffinsin/dog 2>/dev/null || dog_log "当前未添加 tap 仓库"
brew tap griffinsin/dog

# Install the latest version
dog_log "安装最新版本..."
brew install griffinsin/dog/dog

# Success message
dog_success "dog 工具已成功升级到最新版本！"
