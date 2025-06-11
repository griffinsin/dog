#!/bin/bash

# 全局变量
DOG_VERSION="1.0.3"

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
