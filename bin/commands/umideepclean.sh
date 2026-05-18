#!/bin/bash

# Description: UMI 深度清理并重新生成

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

usage() {
    echo "用法: dog umideepclean"
    echo "  -h, --help    显示帮助信息"
    echo ""
    echo "执行:"
    echo "  flutter pub global activate melos"
    echo "  melos run bootstrap:dev"
    echo "  melos run gen"
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

dog_log "开始执行 UMI 深度清理..."

if ! command -v flutter >/dev/null 2>&1; then
    dog_error "未找到 flutter 命令，请先安装或配置 Flutter"
    exit 1
fi

dog_log "执行 flutter pub global activate melos..."
if ! flutter pub global activate melos; then
    dog_error "melos 激活失败"
    exit 1
fi

if ! command -v melos >/dev/null 2>&1; then
    dog_error "未找到 melos 命令，请确认 pub global bin 已加入 PATH"
    dog_log "常见路径: ~/.pub-cache/bin"
    exit 1
fi

dog_log "执行 melos run bootstrap:dev..."
if ! melos run bootstrap:dev; then
    dog_error "melos run bootstrap:dev 执行失败"
    exit 1
fi

dog_log "执行 melos run gen..."
if ! melos run gen; then
    dog_error "melos run gen 执行失败"
    exit 1
fi

dog_success "UMI 深度清理完成"
