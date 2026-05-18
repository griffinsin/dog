#!/bin/bash

# Description: 打开 Chrome 安卓网页调试页面

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

usage() {
    echo "用法: dog cinspect [-s 设备序列号] [--no-open]"
    echo "  -s <serial>   指定要调试的 adb 设备序列号（用于提示确认）"
    echo "  --no-open     只显示提示，不自动打开 Chrome"
    echo "  -h, --help    显示帮助信息"
}

open_chrome=true
inspect_url="chrome://inspect/#devices"
selected_device=""

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
        --no-open)
            open_chrome=false
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
            ;;
    esac
done

dog_log "Android Chrome 网页调试提示"
echo ""
echo "1. 在 Android 手机上开启开发者选项和 USB 调试"
echo "2. 使用 USB 连接手机和电脑，并在手机上允许调试授权"
echo "3. 在手机 Chrome 中打开需要调试的网页"
echo "4. 在电脑 Chrome 中打开:"
print_color "$BLUE" "$inspect_url"
echo "5. 在页面中找到设备和目标网页，点击 inspect 开始调试"
echo ""

if command -v adb &> /dev/null; then
    if dog_select_adb_device "调试" "$selected_device"; then
        selected_device="$DOG_SELECTED_ADB_DEVICE"
        dog_log "目标设备序列号: $selected_device"
        dog_log "请在 Chrome inspect 页面中找到这个设备"
    else
        dog_log "暂未选择设备；你仍然可以打开 Chrome inspect 页面查看连接状态"
    fi
else
    dog_log "adb 不可用，跳过设备选择；你仍然可以打开 Chrome inspect 页面查看连接状态"
fi
echo ""

if [ "$open_chrome" = true ]; then
    dog_log "正在打开 Chrome 调试页面..."
    if open -a "Google Chrome" "$inspect_url"; then
        dog_success "已打开 Chrome 调试页面"
    else
        dog_error "无法自动打开 Google Chrome"
        dog_log "请手动打开: $inspect_url"
        exit 1
    fi
else
    dog_success "提示显示完成"
fi
