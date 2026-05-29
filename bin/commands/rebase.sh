#!/bin/bash

# Description: 拉取主分支并 rebase 当前分支

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

usage() {
    echo "用法: dog rebase [-b 主分支] [--continue]"
    echo "  -b <branch>    指定主分支，默认 dev"
    echo "  --continue     解决冲突并 git add 后继续 rebase 流程"
    echo "  -h, --help     显示帮助信息"
    echo ""
    echo "执行:"
    echo "  git fetch origin <主分支>"
    echo "  git rebase origin/<主分支>"
    echo "  flutter pub get"
    echo "  dart run build_runner build --delete-conflicting-outputs"
    echo ""
    echo "完成后如需推送，请手动执行:"
    echo "  dog rp"
}

base_branch="dev"
continue_rebase=false

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -b)
            shift
            if [ -z "$1" ] || [[ "$1" == -* ]]; then
                dog_error "参数 -b 需要主分支名称"
                usage
                exit 1
            fi
            base_branch="$1"
            shift
            ;;
        --continue)
            continue_rebase=true
            shift
            ;;
        *)
            dog_error "不支持的参数: $1"
            usage
            exit 1
            ;;
    esac
done

ensure_git_repo() {
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        dog_error "当前目录不是 Git 仓库"
        exit 1
    fi
}

ensure_clean_worktree() {
    if [ -n "$(git status --porcelain)" ]; then
        dog_error "当前工作区不干净，请先提交或暂存当前改动"
        git status --short
        exit 1
    fi
}

ensure_flutter_tools() {
    if ! command -v flutter >/dev/null 2>&1; then
        dog_error "未找到 flutter 命令，请先安装或配置 Flutter"
        exit 1
    fi

    if ! command -v dart >/dev/null 2>&1; then
        dog_error "未找到 dart 命令，请先安装或配置 Dart"
        exit 1
    fi
}

show_conflict_help() {
    dog_error "rebase 遇到冲突，请手动处理冲突"
    conflict_files=$(git diff --name-only --diff-filter=U)
    if [ -n "$conflict_files" ]; then
        dog_log "冲突文件:"
        echo "$conflict_files"
    fi
    echo ""
    echo "处理步骤:"
    echo "  1. 修改冲突文件"
    echo "  2. git add <已解决的文件>"
    echo "  3. dog rebase --continue"
    echo ""
    echo "如需放弃:"
    echo "  git rebase --abort"
}

run_flutter_update() {
    ensure_flutter_tools

    dog_log "执行 flutter pub get..."
    if ! flutter pub get; then
        dog_error "flutter pub get 执行失败"
        exit 1
    fi

    dog_log "执行 build_runner..."
    if ! dart run build_runner build --delete-conflicting-outputs; then
        dog_error "build_runner 执行失败"
        exit 1
    fi
}

finish_rebase_flow() {
    dog_success "rebase 流程完成"
    if [ -n "$(git status --porcelain)" ]; then
        dog_log "当前有未提交改动，请确认后自行提交"
        git status --short
    fi
    dog_log "如需推送，请手动执行: dog rp"
}

ensure_git_repo

current_branch=$(git branch --show-current)
if [ -z "$current_branch" ]; then
    dog_error "当前处于 detached HEAD，无法执行 rebase 流程"
    exit 1
fi

if [ "$continue_rebase" = true ]; then
    dog_log "继续 rebase 流程..."
    if ! GIT_EDITOR=true git rebase --continue; then
        show_conflict_help
        exit 1
    fi
    run_flutter_update
    finish_rebase_flow
    exit 0
fi

ensure_clean_worktree

dog_log "当前分支: $current_branch"
dog_log "主分支: $base_branch"

if [ "$current_branch" = "$base_branch" ]; then
    dog_log "当前已经在主分支，执行 git pull --ff-only origin $base_branch..."
    if ! git pull --ff-only origin "$base_branch"; then
        dog_error "主分支拉取失败"
        exit 1
    fi
else
    dog_log "拉取主分支最新代码: origin/$base_branch..."
    if ! git fetch origin "$base_branch"; then
        dog_error "拉取主分支失败: $base_branch"
        exit 1
    fi

    dog_log "执行 git rebase origin/$base_branch..."
    if ! git rebase "origin/$base_branch"; then
        show_conflict_help
        exit 1
    fi
fi

run_flutter_update
finish_rebase_flow
