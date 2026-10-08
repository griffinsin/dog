#!/bin/bash

# 全局变量
DOG_VERSION="1.0.82"

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
	# 文本必须作为 printf 的「参数」而不是拼进格式串：
	# 拼进格式串时文本里的 % 会被当成格式符吃掉。实测 dog img 里的
	#   print_color "$BLUE" "magick input.png -resize 50% output.png"
	# 会输出 "...-resize 500utput.png"（% o 被解释成八进制转换），
	# 而 dog img 的用途恰恰是给出一行可直接复制的命令。
	# 同理文本里的 \n 之类也会被当转义解释。
	local color_code="$1"
	local text="$2"
	printf "\033[%sm%s\033[0m\n" "$color_code" "$text"
}

print_color_with_var() {
	# 把「带颜色的提示文本」和「变量值」分成两行输出，绕开 bash 3.2 的多字节 bug。
	#
	# 真正的病因（2026-10 查明，此前这里写的是「变量名包含特殊字符」，是错的）：
	#   macOS 自带 bash 3.2.57 在 UTF-8 locale 下，双引号字符串里**裸 $var 后面
	#   紧跟多字节字符**时，变量内容会消失，后面那个字符还被吃掉一个字节。
	#     LANG=C.UTF-8 bash -c 'x=abc; echo "前（$x）后"'   -> 前（??后
	#     LANG=C.UTF-8 bash -c 'x=abc; echo "前（${x}）后"' -> 前（abc）后   正确
	#   当年看到的 "PyCharm2025.1 被截断成乱码" 就是这个 —— 和变量名里有没有点号
	#   无关，是调用方写成了 "...$app（完成）" 这种裸变量紧贴全角括号的形式。
	#   触发条件：bash 3.x + UTF-8 locale + 裸 $var + 紧跟非 ASCII 字符。
	#   ${var} 形式免疫，printf "%s" 传参也免疫；zsh 和新版 bash 都没这问题。
	#
	# 所以更简单的办法是调用方把 $var 写成 ${var}，不一定要用本函数。
	# 本函数保留是因为「提示语一行、值另起一行带 ➜」这个排版本身也更好读。
	#
	# 注意：验证中文显示效果必须在真实 locale 下，例如
	#     zsh -lic 'dog xxx'
	# 某些执行环境是 LC_CTYPE=C，恰好绕过这个 bug，看不出问题。
	#
	# 参数：
	# $1 - 颜色代码（如 $GREEN, $RED, $YELLOW 等）
	# $2 - 提示文本（不带变量名）
	# $3 - 需要显示的变量值
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
	printf "\033[%sm%s\033[0m\n" "$color_code" "$prefix"
	printf "➜ %s\n" "$variable"
}
