#!/bin/bash

# Description: 发送文件或目录到安卓手机

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

usage() {
    echo "用法: dog send [-s 设备序列号] [-d 手机目标目录] [--no-open] <本地文件或目录>"
    echo "  -s <serial>       指定 adb 设备序列号"
    echo "  -d <remote_dir>   指定手机目标目录，默认 /sdcard/Download/"
    echo "  --no-open         发送后不自动打开文件"
    echo "  -h, --help        显示帮助信息"
}

selected_device=""
remote_dir="/sdcard/Download/"
open_after_send=true
local_path=""

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
        -d)
            shift
            if [ -z "$1" ] || [[ "$1" == -* ]]; then
                dog_error "参数 -d 需要手机目标目录"
                usage
                exit 1
            fi
            remote_dir="$1"
            shift
            ;;
        --no-open)
            open_after_send=false
            shift
            ;;
        -*)
            dog_error "未知参数: $1"
            usage
            exit 1
            ;;
        *)
            if [ -n "$local_path" ]; then
                dog_error "只支持发送一个本地文件或目录"
                usage
                exit 1
            fi
            local_path="$1"
            shift
            ;;
    esac
done

if [ -z "$local_path" ]; then
    dog_error "缺少本地文件或目录"
    usage
    exit 1
fi

if [ ! -e "$local_path" ]; then
    dog_error "本地路径不存在: $local_path"
    exit 1
fi

dog_log "开始发送文件到安卓手机..."

if ! command -v adb &> /dev/null; then
    dog_error "adb 未安装，正在尝试安装..."
    dog_log "执行: brew install --cask android-platform-tools"
    brew install --cask android-platform-tools

    if ! command -v adb &> /dev/null; then
        dog_error "adb 安装失败，无法继续发送操作"
        exit 1
    fi
fi

device_lines=$(adb devices | awk 'NR > 1 && $2 == "device" {print $1}')

if [ -z "$device_lines" ]; then
    dog_error "未检测到连接的安卓设备，请确保您的设备已连接并启用了 USB 调试"
    exit 1
fi

devices=()
while IFS= read -r serial; do
    [ -n "$serial" ] && devices+=("$serial")
done <<< "$device_lines"

if [ -n "$selected_device" ]; then
    found=false
    for serial in "${devices[@]}"; do
        if [ "$serial" = "$selected_device" ]; then
            found=true
            break
        fi
    done

    if [ "$found" = false ]; then
        dog_error "未找到指定设备: $selected_device"
        dog_log "当前可用设备:"
        for serial in "${devices[@]}"; do
            echo "  $serial"
        done
        exit 1
    fi
elif [ ${#devices[@]} -eq 1 ]; then
    selected_device="${devices[0]}"
else
    dog_log "检测到多个安卓设备，请选择要发送到的设备:"
    PS3="请选择设备 (输入数字): "
    select serial in "${devices[@]}"; do
        if [ -n "$serial" ]; then
            selected_device="$serial"
            break
        else
            dog_error "无效选择，请重新选择"
        fi
    done
fi

remote_dir="${remote_dir%/}"
local_base="$(basename "$local_path")"
remote_path="${remote_dir}/${local_base}"

dog_log "使用设备: $selected_device"
dog_log "本地路径: $local_path"
dog_log "手机目录: $remote_dir"

if ! adb -s "$selected_device" shell mkdir -p "$remote_dir"; then
    dog_error "无法创建手机目标目录: $remote_dir"
    exit 1
fi

if adb -s "$selected_device" push "$local_path" "$remote_dir/"; then
    dog_success "发送成功: $remote_path"
else
    dog_error "发送失败"
    exit 1
fi

if [ -d "$local_path" ]; then
    dog_log "发送的是目录，跳过自动打开"
    exit 0
fi

adb -s "$selected_device" shell am broadcast \
    -a android.intent.action.MEDIA_SCANNER_SCAN_FILE \
    -d "file://${remote_path}" >/dev/null 2>&1 || true

if [ "$open_after_send" = false ]; then
    exit 0
fi

mime_type="application/octet-stream"
if command -v file >/dev/null 2>&1; then
    detected_mime=$(file --mime-type -b "$local_path" 2>/dev/null)
    if [ -n "$detected_mime" ]; then
        mime_type="$detected_mime"
    fi
fi

dog_log "尝试在手机上打开文件..."
if adb -s "$selected_device" shell am start \
    -a android.intent.action.VIEW \
    -d "file://${remote_path}" \
    -t "$mime_type" >/dev/null 2>&1; then
    dog_success "已请求手机打开文件"
else
    dog_log "无法自动打开文件，文件已发送到: $remote_path"
fi
