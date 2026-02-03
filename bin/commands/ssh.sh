#!/bin/bash

# Load global variables and functions
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# SSH key generation command implementation
dog_log "开始生成 SSH 密钥..."

# Get key suffix
read -p "输入密钥名称后缀 (完整密钥名将是 id_ed25519_[您的输入]): " key_suffix
key_name="id_ed25519_$key_suffix"
key_path="$HOME/.ssh/$key_name"

# Check if key already exists
if [ -f "$key_path" ]; then
    echo "错误: SSH 密钥 $key_name 已存在"
    echo "如需覆盖现有密钥，请先删除: rm $key_path $key_path.pub"
    exit 1
fi

# Ensure .ssh directory exists with correct permissions
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Generate the SSH key
while true; do
    read -p "输入与您的 GitHub 账户关联的电子邮件: " email
    if [ -n "$email" ] && [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        break
    else
        echo "错误: 请输入有效的电子邮件地址"
    fi
done

dog_log "正在生成 SSH 密钥..."
if ! ssh-keygen -t ed25519 -C "$email" -f "$key_path" -N ""; then
    dog_error "SSH 密钥生成失败"
    exit 1
fi

# Set correct permissions for SSH keys
chmod 600 "$key_path"
chmod 644 "$key_path.pub"

# Create SSH config if it doesn't exist
config_file="$HOME/.ssh/config"
if [ ! -f "$config_file" ]; then
    dog_log "创建 SSH 配置文件..."
    cat > "$config_file" << EOF
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/$key_name
  IdentitiesOnly yes
  AddKeysToAgent yes
  UseKeychain yes
EOF
    chmod 644 "$config_file"
else
    # Check if the key is already configured
    if ! grep -q "IdentityFile ~/.ssh/$key_name" "$config_file" 2>/dev/null; then
        dog_log "将新密钥添加到现有 SSH 配置文件..."
        # Add GitHub configuration for this key if not present
        if ! grep -q "Host github.com" "$config_file" 2>/dev/null; then
            cat >> "$config_file" << EOF

Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/$key_name
  IdentitiesOnly yes
  AddKeysToAgent yes
  UseKeychain yes
EOF
        fi
    fi
fi

# Check if ssh-agent is already running
if [ -z "$SSH_AUTH_SOCK" ]; then
    dog_log "启动 ssh-agent..."
    if ! eval "$(ssh-agent -s)"; then
        dog_error "ssh-agent 启动失败"
        exit 1
    fi
    
    # Add ssh-agent to shell profile for persistence (zsh is default on modern macOS)
    if [ -f "$HOME/.zshrc" ] && ! grep -q 'ssh-agent' "$HOME/.zshrc" 2>/dev/null; then
        echo 'eval "$(ssh-agent -s)"' >> "$HOME/.zshrc"
        dog_log "已添加 ssh-agent 到 .zshrc"
    elif ! [ -f "$HOME/.zshrc" ]; then
        echo 'eval "$(ssh-agent -s)"' >> "$HOME/.zshrc"
        dog_log "已创建并添加 ssh-agent 到 .zshrc"
    fi
else
    dog_log "ssh-agent 已在运行"
fi

# Add the SSH key to the ssh-agent (macOS specific)
dog_log "将 SSH 密钥添加到 ssh-agent..."
if ssh-add --apple-use-keychain "$key_path"; then
    dog_success "SSH 密钥已成功添加到 ssh-agent"
else
    dog_error "添加 SSH 密钥到 ssh-agent 失败"
    exit 1
fi

# Copy the SSH key to the clipboard
dog_log "将公钥复制到剪贴板..."
if command -v pbcopy &>/dev/null; then
    pbcopy < "$key_path.pub"
    dog_success "公钥已复制到剪贴板"
else
    echo "警告: pbcopy 不可用，请手动复制以下公钥内容:"
    echo "----------------------------------------"
    cat "$key_path.pub"
    echo "----------------------------------------"
fi

dog_success "SSH 密钥已生成并添加到 ssh-agent。"

# Display next steps
echo ""
echo "下一步操作:"
echo "1. 将公钥添加到 GitHub:"
echo "   - 访问 https://github.com/settings/keys"
echo "   - 点击 'New SSH key'"
echo "   - 粘贴公钥内容"
echo ""
echo "2. 测试连接:"
echo "   ssh -T git@github.com"
echo ""
echo "3. 密钥文件位置:"
echo "   私钥: $key_path"
echo "   公钥: $key_path.pub"
