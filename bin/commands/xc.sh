#!/bin/bash

# Description: Xcode 打开工程

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# xc 命令实现 - 智能打开 Xcode 项目
dog_log "正在搜索 Xcode 项目..."

# 首先查找 .xcworkspace 文件（优先级更高）
workspace_files=(*.xcworkspace)

# 如果找到 .xcworkspace 文件
if [ -d "${workspace_files[0]}" ]; then
    dog_log "找到 workspace: ${workspace_files[0]}"
    dog_log "正在打开 Xcode..."
    open "${workspace_files[0]}"
    dog_success "已使用 Xcode 打开 workspace: ${workspace_files[0]}"
    exit 0
fi

# 如果没有找到 .xcworkspace，查找 .xcodeproj 文件
project_files=(*.xcodeproj)

# 如果找到 .xcodeproj 文件
if [ -d "${project_files[0]}" ]; then
    dog_log "找到项目: ${project_files[0]}"
    dog_log "正在打开 Xcode..."
    open "${project_files[0]}"
    dog_success "已使用 Xcode 打开项目: ${project_files[0]}"
    exit 0
fi

# 如果既没有找到 .xcworkspace 也没有找到 .xcodeproj
dog_error "当前目录下没有找到 Xcode 项目 (.xcworkspace 或 .xcodeproj)"
echo "请确保您在包含 Xcode 项目的目录中运行此命令"
echo "或者尝试使用以下命令直接打开 Xcode:"
print_color "$BLUE" "open -a Xcode"
exit 1
