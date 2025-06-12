#!/bin/bash

# 全局变量
DOG_VERSION="1.0.44"

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

print_color() {
	local color_code="$1"
	local text="$2"
	printf "\033[${color_code}m${text}\033[0m"
}
