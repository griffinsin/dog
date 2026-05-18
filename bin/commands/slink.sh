#!/bin/bash

# Description: 恢复 UMI 环境链接

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

usage() {
    echo "用法: dog slink"
    echo "  -h, --help    显示帮助信息"
    echo ""
    echo "执行:"
    echo "  sh ../../scripts/env_restore.sh"
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

restore_script="../../scripts/env_restore.sh"

dog_log "开始恢复 UMI 环境链接..."

if [ ! -f "$restore_script" ]; then
    dog_error "脚本不存在: $restore_script"
    exit 1
fi

dog_log "执行 sh $restore_script..."
if ! sh "$restore_script"; then
    dog_error "env_restore.sh 执行失败"
    exit 1
fi

dog_success "UMI 环境链接恢复完成"
