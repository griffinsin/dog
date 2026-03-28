#!/bin/bash

# Description: 打开 Xcode/UserData

# Load global variables and functions
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# Open Xcode UserData folder command implementation
dog_log "正在打开 Xcode UserData 文件夹..."

# Open Xcode UserData folder
open ~/Library/Developer/Xcode/UserData

dog_success "Xcode UserData 文件夹已打开"
