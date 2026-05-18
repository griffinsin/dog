#!/bin/bash

# Description: UMI 环境切换并生成 Dart defines

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

usage() {
    echo "用法: dog umi"
    echo "  -h, --help    显示帮助信息"
    echo ""
    echo "执行:"
    echo "  sh ../../scripts/env_change.sh"
    echo "  sh ios/scripts/generate_dart_defines.sh"
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

env_script="../../scripts/env_change.sh"
defines_script="ios/scripts/generate_dart_defines.sh"

dog_log "开始执行 UMI 环境更新..."

if [ ! -f "$env_script" ]; then
    dog_error "脚本不存在: $env_script"
    exit 1
fi

if [ ! -f "$defines_script" ]; then
    dog_error "脚本不存在: $defines_script"
    exit 1
fi

dog_log "执行 sh $env_script..."
if ! sh "$env_script"; then
    dog_error "env_change.sh 执行失败"
    exit 1
fi

dog_log "执行 sh $defines_script..."
if ! sh "$defines_script"; then
    dog_error "generate_dart_defines.sh 执行失败"
    exit 1
fi

dog_success "UMI 环境更新完成"
