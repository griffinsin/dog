#!/bin/bash

# Load global variables and functions
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# hello command implementation
dog_log "Hello, World!"
dog_success "hello command executed successfully"
