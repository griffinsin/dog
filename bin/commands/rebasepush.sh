#!/bin/bash

# Description: Git 安全强制推送当前分支

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

usage() {
    echo "用法: dog rebasepush"
    echo "  -h, --help    显示帮助信息"
    echo ""
    echo "执行:"
    echo "  git push --force-with-lease"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        *)
            dog_error "不支持的参数: $1"
            usage
            exit 1
            ;;
    esac
done

dog_log "准备执行安全强制推送..."

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    dog_error "当前目录不是 Git 仓库"
    exit 1
fi

current_branch=$(git branch --show-current)
if [ -n "$current_branch" ]; then
    dog_log "当前分支: $current_branch"
fi

dog_log "执行 git push --force-with-lease..."
if git push --force-with-lease; then
    dog_success "推送完成"
else
    dog_error "推送失败"
    exit 1
fi
