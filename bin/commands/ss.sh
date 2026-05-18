#!/bin/bash

# Description: 安卓手机截屏

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

usage() {
    echo "用法: dog ss [-t] [-s 设备序列号]"
    echo "  -t              使用时间戳文件名"
    echo "  -s <serial>     指定 adb 设备序列号"
    echo "  -h, --help      显示帮助信息"
}

# 初始化变量
use_timestamp=false
output_dir="$HOME/Downloads"
filename="screenshot"
selected_device=""

# 处理所有参数
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -t)
            use_timestamp=true
            dog_log "启用时间戳文件名"
            shift
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
        -*)
            dog_error "未知参数: $1"
            usage
            exit 1
            ;;
        *)
            dog_error "不支持的参数: $1"
            usage
            exit 1
            shift
            ;;
    esac
done

# 安卓手机截屏命令实现
dog_log "开始截取安卓手机屏幕..."

# 如果启用时间戳，则添加时间戳到文件名
if [ "$use_timestamp" = true ]; then
    timestamp=$(date +"%Y%m%d_%H%M%S")
    filename="${filename}_${timestamp}"
fi

# 检查 adb 是否已安装
if ! command -v adb &> /dev/null; then
    dog_error "adb 未安装，正在尝试安装..."
    
    # 直接使用 brew 安装 adb
    dog_log "执行: brew install --cask android-platform-tools"
    brew install --cask android-platform-tools
    
    # 再次检查 adb 是否已安装
    if ! command -v adb &> /dev/null; then
        dog_error "adb 安装失败，无法继续截屏操作"
        exit 1
    fi
fi

# 检查是否有连接且可用的安卓设备
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
    dog_log "检测到多个安卓设备，请选择要截屏的设备:"
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

dog_log "使用设备: $selected_device"

# 执行截屏命令
dog_log "正在截取屏幕..."
output_path="${output_dir}/${filename}.png"
device_screenshot_path="/sdcard/${filename}.png"

# 使用 adb 截屏并保存到设备
if adb -s "$selected_device" shell screencap -p "$device_screenshot_path"; then
    # 将截图从设备拉取到电脑
    if adb -s "$selected_device" pull "$device_screenshot_path" "$output_path"; then
        # 删除设备上的临时截图
        adb -s "$selected_device" shell rm "$device_screenshot_path"
        dog_success "截屏成功！保存到: $output_path"
        open -R "$output_path" >/dev/null 2>&1 || dog_log "无法自动在 Finder 中定位截图文件"
    else
        dog_error "无法从设备拉取截图"
        exit 1
    fi
else
    dog_error "截屏失败，请检查设备连接和权限"
    exit 1
fi
