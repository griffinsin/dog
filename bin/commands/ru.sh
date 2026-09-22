#!/bin/bash

# Description: Flutter 拉取依赖并重新生成代码

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

usage() {
    echo "用法: dog ru"
    echo "  -h, --help    显示帮助信息"
    echo ""
    echo "执行:"
    echo "  ROOT=\$(git rev-parse --show-toplevel)"
    echo "  bash \"\$ROOT/scripts/bootstrap_dev.sh\""
    echo "  cd \"\$ROOT/apps/im_app\""
    echo "  flutter pub get"
    echo "  rm -rf .dart_tool/build"
    echo "  dart run build_runner build --delete-conflicting-outputs"
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

dog_log "开始更新 Flutter 依赖并重新生成代码..."

if ! command -v flutter >/dev/null 2>&1; then
    dog_error "未找到 flutter 命令，请先安装或配置 Flutter"
    exit 1
fi

if ! command -v dart >/dev/null 2>&1; then
    dog_error "未找到 dart 命令，请先安装或配置 Dart"
    exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    dog_error "当前目录不是 Git 仓库，无法定位 apps/im_app"
    exit 1
fi

repo_root=$(git rev-parse --show-toplevel)
bootstrap_script="$repo_root/scripts/bootstrap_dev.sh"
app_dir="$repo_root/apps/im_app"

if [ ! -f "$bootstrap_script" ]; then
    dog_error "脚本不存在: $bootstrap_script"
    exit 1
fi

if [ ! -d "$app_dir" ]; then
    dog_error "目录不存在: $app_dir"
    exit 1
fi

dog_log "执行 bash $bootstrap_script..."
if ! bash "$bootstrap_script"; then
    dog_error "bootstrap_dev.sh 执行失败"
    exit 1
fi

dog_log "进入目录: $app_dir"
cd "$app_dir" || exit 1

dog_log "执行 flutter pub get..."
if ! flutter pub get; then
    dog_error "flutter pub get 执行失败"
    exit 1
fi

dog_log "清理 .dart_tool/build..."
rm -rf -- ".dart_tool/build"

dog_log "执行 build_runner..."
if ! dart run build_runner build --delete-conflicting-outputs; then
    dog_error "build_runner 执行失败"
    exit 1
fi

dog_success "Flutter 依赖更新和代码生成完成"
