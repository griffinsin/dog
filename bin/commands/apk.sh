#!/bin/bash

# Description: 安装 APK 到安卓手机

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

usage() {
    echo "用法: dog apk [-s 设备序列号] [--no-replace] [-d] [-g] <apk文件路径>"
    echo "  -s <serial>     指定 adb 设备序列号"
    echo "  --no-replace    不使用覆盖安装（默认使用 -r 覆盖安装）"
    echo "  -d              允许版本降级安装"
    echo "  -g              安装后授予运行时权限"
    echo "  -h, --help      显示帮助信息"
}

selected_device=""
apk_path=""
replace=true
allow_downgrade=false
grant_permissions=false

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -s)
            shift
            if [ -z "$1" ] || [[ "$1" == -* ]]; then
                dog_error "参数 -s 需要设备序列号"
                usage
                exit 1
            fi
            selected_device="$1"
            shift
            ;;
        --no-replace)
            replace=false
            shift
            ;;
        -d)
            allow_downgrade=true
            shift
            ;;
        -g)
            grant_permissions=true
            shift
            ;;
        -*)
            dog_error "未知参数: $1"
            usage
            exit 1
            ;;
        *)
            if [ -n "$apk_path" ]; then
                dog_error "只支持安装一个 APK 文件"
                usage
                exit 1
            fi
            apk_path="$1"
            shift
            ;;
    esac
done

if [ -z "$apk_path" ]; then
    dog_error "缺少 APK 文件路径"
    usage
    exit 1
fi

if [ ! -f "$apk_path" ]; then
    dog_error "APK 文件不存在: $apk_path"
    exit 1
fi

apk_ext="${apk_path##*.}"
apk_ext="$(echo "$apk_ext" | tr '[:upper:]' '[:lower:]')"
if [ "$apk_ext" != "apk" ]; then
    dog_error "文件不是 APK: $apk_path"
    exit 1
fi

dog_log "开始安装 APK 到安卓手机..."

dog_ensure_adb "安装操作" || exit 1
dog_select_adb_device "安装到" "$selected_device" || exit 1
selected_device="$DOG_SELECTED_ADB_DEVICE"

install_args=()
if [ "$replace" = true ]; then
    install_args+=("-r")
fi
if [ "$allow_downgrade" = true ]; then
    install_args+=("-d")
fi
if [ "$grant_permissions" = true ]; then
    install_args+=("-g")
fi

dog_log "使用设备: $selected_device"
dog_log "APK 文件: $apk_path"
if [ ${#install_args[@]} -gt 0 ]; then
    dog_log "安装参数: ${install_args[*]}"
fi

if adb -s "$selected_device" install "${install_args[@]}" "$apk_path"; then
    dog_success "APK 安装成功"
else
    dog_error "APK 安装失败"
    exit 1
fi
