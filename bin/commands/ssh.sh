#!/bin/bash

# Load global variables and functions
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# SSH key generation command implementation
dog_log "开始生成 SSH 密钥..."

# Get key suffix
read -p "输入密钥名称后缀 (完整密钥名将是 id_ed25519_[您的输入]): " key_suffix
key_name="id_ed25519_$key_suffix"
key_path="$HOME/.ssh/$key_name"

# Generate the SSH key
read -p "输入与您的 GitHub 账户关联的电子邮件: " email
dog_log "正在生成 SSH 密钥..."
ssh-keygen -t ed25519 -C "$email" -f "$key_path"

# Start the ssh-agent in the background
dog_log "启动 ssh-agent..."
eval "$(ssh-agent -s)"

# Add the SSH key to the ssh-agent
dog_log "将 SSH 密钥添加到 ssh-agent..."
ssh-add "$key_path"

# Copy the SSH key to the clipboard
dog_log "将公钥复制到剪贴板..."
pbcopy < "$key_path.pub"

dog_success "SSH 密钥已生成并添加到 ssh-agent。公钥已复制到剪贴板。"
