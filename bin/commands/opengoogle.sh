#!/bin/bash

# Load global variables and functions
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# Open Google development folder command implementation
dog_log "正在打开 Google 开发文件夹..."

# Open Google folder
open ~/Library/Application\ Support/Google

dog_success "Google 开发文件夹已打开"
