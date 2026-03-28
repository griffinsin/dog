#!/bin/bash

# Description: 用指定的ssh来clone工程

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# clonewithssh 命令实现
dog_log "使用指定 SSH 密钥克隆 Git 仓库"

# 检查参数
if [ $# -lt 1 ]; then
    dog_error "缺少 Git 仓库 URL"
    echo "用法: dog clonewithssh <git-repo-url>"
    echo "示例: dog clonewithssh git@github.com:username/repo.git"
    exit 1
fi

# 获取 Git 仓库 URL
REPO_URL="$1"
dog_log "仓库 URL: $REPO_URL"

# 提取仓库名称作为目录名
REPO_NAME=$(basename "$REPO_URL" .git)
dog_log "仓库名称: $REPO_NAME"

# 列出 ~/.ssh 目录下所有的私钥文件
dog_log "可用的 SSH 密钥文件:"
key_files=$(find ~/.ssh -type f ! -name "*.pub" ! -name "config" ! -name "known_hosts" ! -name ".DS_Store" ! -name "*.old")

# 检查是否找到了任何 SSH 密钥
if [ -z "$key_files" ]; then
    dog_error "未找到任何 SSH 密钥。请先生成 SSH 密钥。"
    echo "生成 SSH 密钥的命令:"
    print_color "$BLUE" "ssh-keygen -t ed25519 -C \"your_email@example.com\""
    exit 1
fi

# 显示可用的 SSH 密钥并让用户选择
selected_key=""
PS3="请选择要使用的 SSH 密钥 (输入数字): "
select key_path in $key_files; do
    if [ -n "$key_path" ]; then
        selected_key="$key_path"
        dog_log "已选择 SSH 密钥: $selected_key"
        break
    else
        dog_error "无效选择。请重新选择。"
    fi
done

# 使用选定的 SSH 密钥克隆仓库
dog_log "正在使用选定的 SSH 密钥克隆仓库..."
GIT_SSH_COMMAND="ssh -i $selected_key -F /dev/null" git clone "$REPO_URL"

# 检查克隆是否成功
if [ $? -ne 0 ]; then
    dog_error "克隆仓库失败。请检查 SSH 密钥和仓库 URL。"
    exit 1
fi

# 进入克隆的仓库目录
cd "$REPO_NAME" || exit 1

# 为克隆的仓库设置 SSH 密钥
dog_log "为仓库设置 SSH 密钥..."
git config core.sshCommand "ssh -i $selected_key -F /dev/null"

dog_success "仓库克隆成功，并已设置 SSH 密钥: $selected_key"
echo "仓库目录: $(pwd)"
