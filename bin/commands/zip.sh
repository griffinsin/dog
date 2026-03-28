#!/bin/bash

# Load global variables and functions
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

usage() {
    echo "Usage: dog zip [-p path] [-n count] <prefix>"
    echo "  -p    Target directory path (default: current directory)"
    echo "  -n    Number of files per zip (default: 20)"
    echo "  prefix  Required zip filename prefix"
}

TARGET_DIR="."
BATCH_SIZE=20

while getopts ":p:n:h" opt; do
    case "$opt" in
        p)
            TARGET_DIR="$OPTARG"
            ;;
        n)
            BATCH_SIZE="$OPTARG"
            ;;
        h)
            usage
            exit 0
            ;;
        :) 
            dog_error "Option -$OPTARG requires an argument."
            usage
            exit 1
            ;;
        \?)
            dog_error "Unknown option: -$OPTARG"
            usage
            exit 1
            ;;
    esac
done
shift $((OPTIND - 1))

PREFIX="$1"
if [ -z "$PREFIX" ]; then
    dog_error "Missing required prefix argument."
    usage
    exit 1
fi

if [ ! -d "$TARGET_DIR" ]; then
    dog_error "Target path is not a directory: $TARGET_DIR"
    exit 1
fi

if ! [[ "$BATCH_SIZE" =~ ^[0-9]+$ ]] || [ "$BATCH_SIZE" -le 0 ]; then
    dog_error "Invalid -n value (must be a positive integer): $BATCH_SIZE"
    exit 1
fi

dog_log "Preparing to zip files"
dog_log "Target directory: $TARGET_DIR"
dog_log "Prefix: $PREFIX"
dog_log "Files per zip: $BATCH_SIZE"

files=()
while IFS= read -r -d '' file_path; do
    base_name=$(basename "$file_path")
    files+=("$base_name")
done < <(find "$TARGET_DIR" -maxdepth 1 -type f ! -name "*.zip" -print0)

if [ ${#files[@]} -eq 0 ]; then
    dog_error "No files to zip in directory: $TARGET_DIR"
    exit 1
fi

total_files=${#files[@]}
dog_log "Found $total_files file(s) to zip"

zip_index=1
start=0

while [ $start -lt $total_files ]; do
    zip_name="${PREFIX}-${zip_index}.zip"

    batch=()
    i=0
    while [ $i -lt $BATCH_SIZE ] && [ $((start + i)) -lt $total_files ]; do
        batch+=("${files[$((start + i))]}")
        i=$((i + 1))
    done

    dog_log "Creating zip: $TARGET_DIR/$zip_name (files: ${#batch[@]})"

    (
        cd "$TARGET_DIR" || exit 1
        zip -q "$zip_name" "${batch[@]}"
    )

    if [ $? -ne 0 ]; then
        dog_error "Failed to create zip: $TARGET_DIR/$zip_name"
        exit 1
    fi

    dog_success "Created zip: $TARGET_DIR/$zip_name"

    start=$((start + BATCH_SIZE))
    zip_index=$((zip_index + 1))
done

dog_success "Done. Created $((zip_index - 1)) zip file(s)."
