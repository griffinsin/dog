#!/bin/bash

# Description: 为音频/视频文件设置封面图片

# Load global variables and functions
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

usage() {
    echo "用法: dog setcover <音视频文件路径> <图片文件路径>"
    echo "  两个参数可任意顺序传入，命令会自动识别图片与音视频文件。"
    echo "  支持的图片格式: jpg, jpeg, png, webp"
    echo "  支持的音视频格式: m4a, mp4, m4v, mov, mp3"
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    exit 0
fi

if [ $# -ne 2 ]; then
    dog_error "需要且仅需要 2 个参数。"
    usage
    exit 1
fi

A="$1"
B="$2"

if [ ! -f "$A" ]; then
    dog_error "文件不存在: $A"
    exit 1
fi

if [ ! -f "$B" ]; then
    dog_error "文件不存在: $B"
    exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
    dog_error "未安装 ffmpeg 或 ffmpeg 不在 PATH 中。"
    dog_log "安装: brew install ffmpeg"
    exit 1
fi

lower_ext() {
    local name="$1"
    local ext="${name##*.}"
    echo "${ext}" | tr '[:upper:]' '[:lower:]'
}

is_image_ext() {
    case "$1" in
        jpg|jpeg|png|webp) return 0 ;;
        *) return 1 ;;
    esac
}

is_media_ext() {
    case "$1" in
        m4a|mp4|m4v|mov|mp3) return 0 ;;
        *) return 1 ;;
    esac
}

A_EXT=$(lower_ext "$A")
B_EXT=$(lower_ext "$B")

IMAGE_PATH=""
MEDIA_PATH=""
MEDIA_EXT=""

if is_image_ext "$A_EXT" && is_media_ext "$B_EXT"; then
    IMAGE_PATH="$A"
    MEDIA_PATH="$B"
    MEDIA_EXT="$B_EXT"
elif is_image_ext "$B_EXT" && is_media_ext "$A_EXT"; then
    IMAGE_PATH="$B"
    MEDIA_PATH="$A"
    MEDIA_EXT="$A_EXT"
else
    dog_error "文件格式不支持，或无法判断哪个是音视频文件、哪个是图片文件。"
    dog_log "参数1: $A (.$A_EXT)"
    dog_log "参数2: $B (.$B_EXT)"
    usage
    exit 1
fi

MEDIA_DIR=$(dirname "$MEDIA_PATH")
MEDIA_BASE=$(basename "$MEDIA_PATH")
MEDIA_NAME_NOEXT="${MEDIA_BASE%.*}"

TMP_OUT="${MEDIA_DIR}/${MEDIA_NAME_NOEXT}.setcover.tmp.${MEDIA_EXT}"

if [ -e "$TMP_OUT" ]; then
    rm -f "$TMP_OUT"
fi

dog_log "音视频文件: $MEDIA_PATH"
dog_log "图片文件: $IMAGE_PATH"

dog_log "正在写入封面..."

if [[ "$MEDIA_EXT" == "mp3" ]]; then
    ffmpeg -y \
        -i "$MEDIA_PATH" \
        -i "$IMAGE_PATH" \
        -map 0:a \
        -map 1:v \
        -c copy \
        -id3v2_version 3 \
        -metadata:s:v title="Album cover" \
        -metadata:s:v comment="Cover (front)" \
        "$TMP_OUT"
else
    ffmpeg -y \
        -i "$MEDIA_PATH" \
        -i "$IMAGE_PATH" \
        -map 0 \
        -map 1 \
        -c copy \
        -disposition:v attached_pic \
        "$TMP_OUT"
fi

if [ $? -ne 0 ]; then
    dog_error "ffmpeg 执行失败。"
    rm -f "$TMP_OUT" 2>/dev/null || true
    exit 1
fi

mv -f "$TMP_OUT" "$MEDIA_PATH"

dog_success "封面设置完成: $MEDIA_PATH"
