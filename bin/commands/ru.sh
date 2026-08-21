#!/bin/bash

# Description: Flutter 拉取依赖并重新生成代码

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

usage() {
    echo "用法: dog ru [-d]"
    echo "  -d            深度更新 apps/im_app"
    echo "  -h, --help    显示帮助信息"
    echo ""
    echo "默认执行:"
    echo "  flutter pub get"
    echo "  dart run build_runner build --delete-conflicting-outputs"
    echo ""
    echo "深度更新执行:"
    echo "  cd \$(git rev-parse --show-toplevel)/apps/im_app"
    echo "  flutter pub get"
    echo "  清理 pubspec.lock 中 git 依赖对应的 build 目录"
    echo "  dart run build_runner build --delete-conflicting-outputs"
}

deep_update=false

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -d)
            deep_update=true
            shift
            ;;
        *)
            dog_error "不支持的参数: $1"
            usage
            exit 1
            ;;
    esac
done

dog_log "开始更新 Flutter 依赖并重新生成代码..."

if ! command -v flutter >/dev/null 2>&1; then
    dog_error "未找到 flutter 命令，请先安装或配置 Flutter"
    exit 1
fi

if ! command -v dart >/dev/null 2>&1; then
    dog_error "未找到 dart 命令，请先安装或配置 Dart"
    exit 1
fi

run_build_runner() {
    dog_log "执行 build_runner..."
    if ! dart run build_runner build --delete-conflicting-outputs; then
        dog_error "build_runner 执行失败"
        exit 1
    fi
}

if [ "$deep_update" = true ]; then
    dog_log "开始深度更新 apps/im_app..."

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        dog_error "当前目录不是 Git 仓库，无法定位 apps/im_app"
        exit 1
    fi

    repo_root=$(git rev-parse --show-toplevel)
    app_dir="$repo_root/apps/im_app"

    if [ ! -d "$app_dir" ]; then
        dog_error "目录不存在: $app_dir"
        exit 1
    fi

    if [ ! -f "$app_dir/pubspec.lock" ]; then
        dog_error "文件不存在: $app_dir/pubspec.lock"
        exit 1
    fi

    dog_log "进入目录: $app_dir"
    cd "$app_dir" || exit 1

    dog_log "执行 flutter pub get..."
    if ! flutter pub get; then
        dog_error "flutter pub get 执行失败"
        exit 1
    fi

    dog_log "清理 git 依赖对应的 build 目录..."
    cleaned_count=0
    while IFS= read -r dep_name; do
        [ -n "$dep_name" ] || continue
        rm -rf -- "build/$dep_name"
        cleaned_count=$((cleaned_count + 1))
    done < <(awk '/^  [^ ]+:$/{n=substr($1,1,length($1)-1)} /^    source: git$/{print n}' pubspec.lock | sort -u)
    dog_log "已清理 build 目录数量: $cleaned_count"

    run_build_runner
    dog_success "Flutter 深度更新和代码生成完成"
    exit 0
fi

dog_log "执行 flutter pub get..."
if ! flutter pub get; then
    dog_error "flutter pub get 执行失败"
    exit 1
fi

run_build_runner

dog_success "Flutter 依赖更新和代码生成完成"
