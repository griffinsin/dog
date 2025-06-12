#!/bin/bash

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# uploadsettings 命令实现
dog_log "开始上传开发环境设置..."

# 设置仓库目录
repo_dir="$HOME/.mace/dev_settings"
dog_log "同步设置从 JetBrains IDEs 到 $repo_dir..."

# 检查仓库目录是否存在
if [ ! -d "$repo_dir" ]; then
    dog_error "$repo_dir 目录不存在，请先运行 'dog importsettings' 命令初始化仓库"
    exit 1
fi

# 设置远程 URL 为 SSH 格式以便推送
cd "$repo_dir"
git remote set-url origin git@github.com:Griffinsin/dev_settings.git

# 遍历 JetBrains IDEs
for app in "${jetbrains_apps[@]}"; do
    # 使用通配符匹配 JetBrains 文件夹中的版本化目录
    for config_dir in "$HOME/Library/Application Support/JetBrains/${app}"*; do
        if [ -d "$config_dir" ]; then
            for sub_dir in keymaps templates; do
                if [ -d "$config_dir/$sub_dir" ]; then
                    dog_log "同步 $sub_dir 从 $config_dir 到 $repo_dir..."
                    rm -rf "$repo_dir/$sub_dir" # 清空目标目录
                    mkdir -p "$repo_dir/$sub_dir"
                    cp -r "$config_dir/$sub_dir"/* "$repo_dir/$sub_dir/" 2>/dev/null || true

                    # 检查更改并提交
                    cd "$repo_dir"
                    if [ -n "$(git status --porcelain)" ]; then
                        git add .
                        git commit -m "更新 $sub_dir 从 $app"
                        git push origin main
                        print_color "$GREEN" "$app 的 $sub_dir 更改已成功上传。"
                        exit 0 # 成功提交后退出函数
                    else
                        print_color "$GREEN" "$app 的 $sub_dir 没有需要提交的更改。"
                    fi
                else
                    print_color "$RED" "$app 中未找到 $sub_dir 目录。"
                fi
            done
        else
            print_color "$RED" "未找到 $app 配置目录。"
        fi
    done
done

# 处理 Android Studio
dog_log "同步设置从 Android Studio 到 $repo_dir..."
for config_dir in "$HOME/Library/Application Support/Google/AndroidStudio"*; do
    if [ -d "$config_dir" ]; then
        for sub_dir in keymaps templates; do
            if [ -d "$config_dir/$sub_dir" ]; then
                dog_log "同步 $sub_dir 从 $config_dir 到 $repo_dir..."
                rm -rf "$repo_dir/$sub_dir" # 清空目标目录
                mkdir -p "$repo_dir/$sub_dir"
                cp -r "$config_dir/$sub_dir"/* "$repo_dir/$sub_dir/" 2>/dev/null || true

                # 检查更改并提交
                cd "$repo_dir"
                if [ -n "$(git status --porcelain)" ]; then
                    git add .
                    git commit -m "更新 $sub_dir 从 Android Studio"
                    git push origin main
                    print_color "$GREEN" "Android Studio 的 $sub_dir 更改已成功上传。"
                    exit 0 # 成功提交后退出函数
                else
                    print_color "$GREEN" "Android Studio 的 $sub_dir 没有需要提交的更改。"
                fi
            else
                print_color "$RED" "Android Studio 中未找到 $sub_dir 目录。"
            fi
        done
    else
        dog_log "未找到 Android Studio 配置目录。"
    fi
done

# 处理 Xcode CodeSnippets
xcode_snippets_dir="$HOME/Library/Developer/Xcode/UserData/CodeSnippets"
if [ -d "$xcode_snippets_dir" ]; then
    dog_log "同步 Xcode CodeSnippets 到 $repo_dir..."
    rm -rf "$repo_dir/CodeSnippets" # 清空目标目录
    mkdir -p "$repo_dir/CodeSnippets"
    cp -r "$xcode_snippets_dir"/* "$repo_dir/CodeSnippets/" 2>/dev/null || true

    # 检查更改并提交
    cd "$repo_dir"
    git add -A # 确保 CodeSnippets 中的所有文件都被跟踪
    if [ -n "$(git status --porcelain)" ]; then
        git commit -m "更新 Xcode CodeSnippets"
        git push origin main
        print_color "$GREEN" "Xcode CodeSnippets 已成功上传。"
        exit 0 # 成功提交后退出函数
    else
        print_color "$GREEN" "Xcode CodeSnippets 没有需要提交的更改。"
    fi
else
    dog_log "未找到 Xcode CodeSnippets 目录。"
fi

print_color "$GREEN" "所有 JetBrains IDEs 都没有检测到更改。"
