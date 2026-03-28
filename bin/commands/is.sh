#!/bin/bash

# Description: 导入开发环境快捷键和代码片段 (importsettings的简写)

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# importsettings 命令实现
dog_log "开始导入开发环境设置..."

# 克隆或更新 dev_settings 仓库
if [ ! -d "$HOME/.mace/dev_settings" ]; then
    dog_log "从 https://github.com/Griffinsin/dev_settings.git 克隆仓库到 ~/.mace/dev_settings..."
    mkdir -p "$HOME/.mace"
    if git clone "https://github.com/Griffinsin/dev_settings.git" "$HOME/.mace/dev_settings"; then
        dog_success "仓库成功克隆到 ~/.mace/dev_settings。"
    else
        dog_error "无法克隆仓库到 ~/.mace/dev_settings。请检查网络连接。"
        exit 1
    fi
else
    dog_log "目录 ~/.mace/dev_settings 已存在。尝试更新仓库..."
    cd "$HOME/.mace/dev_settings"
    # 确保远程 URL 设置为 HTTPS
    git remote set-url origin https://github.com/Griffinsin/dev_settings.git
    if git pull; then
        dog_success "仓库更新成功。"
    else
        dog_error "无法更新仓库。请检查网络连接和权限。"
        exit 1
    fi
fi

# 遍历 JetBrains IDEs
for app in "${jetbrains_apps[@]}"; do
    # 使用通配符匹配 JetBrains 文件夹中的版本化目录
    for config_dir in "$HOME/Library/Application Support/JetBrains/${app}"*; do
        if [ -d "$config_dir" ]; then
            dog_log "复制设置到 $app..."
            mkdir -p "$config_dir/keymaps"
            mkdir -p "$config_dir/templates"
            cp -r "$HOME/.mace/dev_settings/keymaps"/* "$config_dir/keymaps" 2>/dev/null || true
            cp -r "$HOME/.mace/dev_settings/templates"/* "$config_dir/templates" 2>/dev/null || true
            print_color_with_var "$GREEN" "设置已复制到" "$app"
        fi
    done
done

# 单独处理 Android Studio
for config_dir in "$HOME/Library/Application Support/Google/AndroidStudio"*; do
    if [ -d "$config_dir" ]; then
        dog_log "复制设置到 Android Studio..."
        mkdir -p "$config_dir/keymaps"
        mkdir -p "$config_dir/templates"
        cp -r "$HOME/.mace/dev_settings/keymaps"/* "$config_dir/keymaps" 2>/dev/null || true
        cp -r "$HOME/.mace/dev_settings/templates"/* "$config_dir/templates" 2>/dev/null || true
        print_color "$GREEN" "设置已复制到 Android Studio。"
    else
        dog_log "未找到 Android Studio 配置目录。"
    fi
done

# 处理 Xcode CodeSnippets
xcode_snippets_dir="$HOME/Library/Developer/Xcode/UserData/CodeSnippets"
if [ -d "$HOME/.mace/dev_settings/CodeSnippets" ]; then
    dog_log "复制 CodeSnippets 到 Xcode..."
    mkdir -p "$xcode_snippets_dir"
    cp -r "$HOME/.mace/dev_settings/CodeSnippets"/* "$xcode_snippets_dir" 2>/dev/null || true
    print_color "$GREEN" "CodeSnippets 已复制到 Xcode。"
else
    dog_log "在 dev_settings 中未找到 CodeSnippets 目录。"
fi

dog_success "开发环境设置导入完成"
