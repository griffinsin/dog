#!/bin/bash

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# 安卓手机截屏命令实现
dog_log "开始截取安卓手机屏幕..."

# 初始化变量
use_timestamp=false
output_dir="$HOME/Downloads"
filename="screenshot"

# 处理所有参数
while [ $# -gt 0 ]; do
    case "$1" in
        -t)
            use_timestamp=true
            dog_log "启用时间戳文件名"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# 如果启用时间戳，则添加时间戳到文件名
if [ "$use_timestamp" = true ]; then
    timestamp=$(date +"%Y%m%d_%H%M%S")
    filename="${filename}_${timestamp}"
fi

# 检查 adb 是否已安装
if ! command -v adb &> /dev/null; then
    dog_error "adb 未安装，正在尝试安装..."
    
    # 获取命令目录
    COMMANDS_DIR=$(dirname "${BASH_SOURCE[0]}")
    
    # 调用 installadb 命令
    dog_log "执行 installadb 命令..."
    source "${COMMANDS_DIR}/installadb.sh"
    
    # 再次检查 adb 是否已安装
    if ! command -v adb &> /dev/null; then
        dog_error "adb 安装失败，无法继续截屏操作"
        exit 1
    fi
fi

# 检查是否有连接的安卓设备
devices=$(adb devices | grep -v "List" | grep -v "^$" | wc -l)
if [ "$devices" -eq 0 ]; then
    dog_error "未检测到连接的安卓设备，请确保您的设备已连接并启用了 USB 调试"
    exit 1
fi

# 执行截屏命令
dog_log "正在截取屏幕..."
output_path="${output_dir}/${filename}.png"

# 使用 adb 截屏并保存到设备
if adb shell screencap -p /sdcard/screenshot.png; then
    # 将截图从设备拉取到电脑
    if adb pull /sdcard/screenshot.png "$output_path"; then
        # 删除设备上的临时截图
        adb shell rm /sdcard/screenshot.png
        dog_success "截屏成功！保存到: $output_path"
    else
        dog_error "无法从设备拉取截图"
        exit 1
    fi
else
    dog_error "截屏失败，请检查设备连接和权限"
    exit 1
fi
