#!/bin/bash

# Description: 打开 Application Support/JetBrains

# Load global variables and functions
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# Open JetBrains folder command implementation
dog_log "正在打开 JetBrains 配置文件夹..."

# Open JetBrains folder
open ~/Library/Application\ Support/JetBrains

dog_success "JetBrains 配置文件夹已打开"
