#!/bin/bash

# 全局变量
DOG_VERSION="1.0.69"

# 全局函数
dog_log() {
  echo "[dog] $1"
}

dog_error() {
  echo "[dog 错误] $1" >&2
}

dog_success() {
  echo "[dog 成功] $1"
}

dog_ensure_adb() {
  local action_name="${1:-操作}"

  if command -v adb &> /dev/null; then
    return 0
  fi

  dog_error "adb 未安装，正在尝试安装..."
  dog_log "执行: brew install --cask android-platform-tools"
  brew install --cask android-platform-tools

  if ! command -v adb &> /dev/null; then
    dog_error "adb 安装失败，无法继续${action_name}"
    return 1
  fi

  return 0
}

DOG_SELECTED_ADB_DEVICE=""

dog_select_adb_device() {
  local action_label="${1:-操作}"
  local requested_device="${2:-}"
  local device_lines=""
  local devices=()
  local serial=""
  local found=false

  DOG_SELECTED_ADB_DEVICE=""

  device_lines=$(adb devices | awk 'NR > 1 && $2 == "device" {print $1}')

  if [ -z "$device_lines" ]; then
    dog_error "未检测到连接的安卓设备，请确保您的设备已连接并启用了 USB 调试"
    return 1
  fi

  while IFS= read -r serial; do
    [ -n "$serial" ] && devices+=("$serial")
  done <<< "$device_lines"

  if [ -n "$requested_device" ]; then
    for serial in "${devices[@]}"; do
      if [ "$serial" = "$requested_device" ]; then
        found=true
        break
      fi
    done

    if [ "$found" = false ]; then
      dog_error "未找到指定设备: $requested_device"
      dog_log "当前可用设备:"
      for serial in "${devices[@]}"; do
        echo "  $serial"
      done
      return 1
    fi

    DOG_SELECTED_ADB_DEVICE="$requested_device"
    return 0
  fi

  if [ ${#devices[@]} -eq 1 ]; then
    DOG_SELECTED_ADB_DEVICE="${devices[0]}"
    return 0
  fi

  dog_log "检测到多个安卓设备，请选择要${action_label}的设备:"
  PS3="请选择设备 (输入数字): "
  select serial in "${devices[@]}"; do
    if [ -n "$serial" ]; then
      DOG_SELECTED_ADB_DEVICE="$serial"
      return 0
    else
      dog_error "无效选择，请重新选择"
    fi
  done
}

jetbrains_apps=("PyCharm" "GoLand" "IntelliJ IDEA" "IntelliJ IDEA CE" "WebStorm" "CLion" "PhpStorm" "RubyMine" "DataGrip")

# 颜色定义
RED="31"
GREEN="32"
YELLOW="33"
BLUE="34"
MAGENTA="35"
CYAN="36"
WHITE="37"
RESET="0"

print_color() {
	local color_code="$1"
	local text="$2"
	printf "\033[${color_code}m${text}\033[0m\n"
}

print_color_with_var() {
	# 解决 bash 函数中变量名包含特殊字符时的截断问题
	# 
	# 问题描述：
	# - 某些变量名（如 "PyCharm2025.1"）在 print_color 函数中会被截断为乱码
	# - 这是 bash 在处理包含 ANSI 转义序列和特殊字符的字符串时的边缘情况 bug
	# - 直接在 printf 格式字符串中混合变量和转义序列会导致解析异常
	#
	# 解决方案：
	# - 将输出分为两行：第一行显示带颜色的提示文本，第二行显示变量名
	# - 避免在同一个字符串中混合 ANSI 转义序列和变量内容
	# - 使用箭头符号 "➜" 增强变量名的视觉识别度
	#
	# 参数：
	# $1 - 颜色代码（如 $GREEN, $RED, $YELLOW 等）
	# $2 - 提示文本（不带变量名）
	# $3 - 需要显示的变量名
	#
	# 使用示例：
	# print_color_with_var "$GREEN" "设置已复制到" "$app_name"
	#
	# 输出效果：
	# 设置已复制到 (绿色)
	# ➜ PyCharm2025.1 (普通文本)
	
	local color_code="$1"
	local prefix="$2"
	local variable="$3"
	printf "\033[${color_code}m${prefix}\033[0m\n"
	printf "➜ %s\n" "$variable"
}
