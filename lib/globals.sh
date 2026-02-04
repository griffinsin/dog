#!/bin/bash

# 全局变量
DOG_VERSION="1.0.52"

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
