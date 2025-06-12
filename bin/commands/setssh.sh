#!/bin/bash

# Load global variables and functions
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# Set SSH key for current Git repository command implementation
dog_log "开始为当前 Git 仓库设置 SSH 密钥..."

# 检查当前目录是否是Git仓库
if git rev-parse --git-dir >/dev/null 2>&1; then
    dog_log "当前目录是一个Git仓库。"

    # 列出~/.ssh目录下所有的私钥文件
    dog_log "可用的SSH密钥文件："
    key_files=$(find ~/.ssh -type f ! -name "*.pub" ! -name "config" ! -name "known_hosts")
    select key_path in $key_files; do
        if [ -n "$key_path" ]; then
            # 设置选定的SSH密钥
            git config core.sshCommand "ssh -i $key_path -F /dev/null"
            dog_log "git config core.sshCommand \"ssh -i $key_path -F /dev/null\""
            dog_success "已设置SSH密钥：$key_path"
            break
        else
            dog_error "无效选择。"
        fi
    done
else
    dog_error "当前目录不是一个Git仓库。"
fi
