#!/bin/bash

# Load global variables and functions
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# JetBrain unlock command implementation
dog_log "开始解锁 JetBrains 产品..."

# Create mace directory and clone/update repository
mkdir -p "${HOME}/.mace"
git -C "${HOME}/.mace" clone https://github.com/Griffinsin/treasury.git 2>/dev/null || (cd "${HOME}/.mace/treasury" && git pull)

# Create jetbrainUnlock directory and copy files
mkdir -p "${HOME}/.jetbrainUnlock" && cp -r "${HOME}/.mace/treasury/jetbrainunlock/"* "${HOME}/.jetbrainUnlock/"

# Run install/uninstall scripts
for script in uninstall.sh install.sh; do
    if [ -f "${HOME}/.jetbrainUnlock/scripts/$script" ]; then
        dog_log "执行 $script 脚本..."
        sh "${HOME}/.jetbrainUnlock/scripts/$script"
    fi
done

# Copy activation code to clipboard
if [ -f "${HOME}/.jetbrainUnlock/激活码.txt" ]; then
    pbcopy < "${HOME}/.jetbrainUnlock/激活码.txt"
    dog_success "激活码已经复制到粘贴板，可以粘贴到 JetBrains 软件中了。"
else
    dog_error "未找到激活码文件！"
fi
