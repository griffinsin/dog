#!/bin/bash

# Description: Flutter 拉取依赖并重新生成代码

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

usage() {
    echo "用法: dog rebaseupdate"
    echo "  -h, --help    显示帮助信息"
    echo ""
    echo "执行:"
    echo "  flutter pub get"
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

dog_success "Flutter 依赖更新和代码生成完成"
