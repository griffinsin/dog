#!/bin/bash

# Description: 为音频/视频文件设置封面图片

# Load global variables and functions
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

usage() {
    echo "用法: dog setcover <音视频文件路径> <图片文件路径>"
    echo "  两个参数可任意顺序传入，命令会自动识别图片与音视频文件。"
    echo "  -v  显示详细日志"
    echo "  --no-compress  不压缩图片（不转 JPEG），直接使用原图作为封面"
    echo "  支持的图片格式: jpg, jpeg, png, webp"
    echo "  支持的音视频格式: m4a, mp4, m4v, mov, mp3"
}

VERBOSE=false
NO_COMPRESS=false
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -v)
            VERBOSE=true
            shift
            ;;
        --no-compress)
            NO_COMPRESS=true
            shift
            ;;
        -* )
            dog_error "未知参数: $1"
            usage
            exit 1
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done

if [ ${#ARGS[@]} -ne 2 ]; then
    dog_error "需要 2 个文件路径参数。"
    usage
    exit 1
fi

A="${ARGS[0]}"
B="${ARGS[1]}"

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

vlog() {
    if [ "$VERBOSE" = true ]; then
        dog_log "$1"
    fi
}

COVER_TMP_IMAGE=""
cleanup() {
    if [ -n "$COVER_TMP_IMAGE" ] && [ -f "$COVER_TMP_IMAGE" ]; then
        rm -f "$COVER_TMP_IMAGE" 2>/dev/null || true
    fi
}
trap cleanup EXIT

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
    if [ "$VERBOSE" = true ]; then
        dog_log "参数1: $A (.$A_EXT)"
        dog_log "参数2: $B (.$B_EXT)"
    fi
    usage
    exit 1
fi

IMAGE_EXT=$(lower_ext "$IMAGE_PATH")
COVER_IMAGE_PATH="$IMAGE_PATH"

if [ "$NO_COMPRESS" = false ]; then
    if [[ "$IMAGE_EXT" == "png" || "$IMAGE_EXT" == "webp" ]]; then
        vlog "检测到图片格式为 .$IMAGE_EXT，默认将转为 JPEG（质量 75，不改宽高）"

        tmp_base=$(mktemp -t dog_setcover_cover)
        rm -f "$tmp_base" 2>/dev/null || true
        COVER_TMP_IMAGE="${tmp_base}.jpg"

        if command -v sips >/dev/null 2>&1; then
            if [ "$VERBOSE" = true ]; then
                sips -s format jpeg -s formatOptions 75 "$IMAGE_PATH" --out "$COVER_TMP_IMAGE" >/dev/null
            else
                sips -s format jpeg -s formatOptions 75 "$IMAGE_PATH" --out "$COVER_TMP_IMAGE" >/dev/null 2>&1
            fi

            if [ $? -ne 0 ] || [ ! -f "$COVER_TMP_IMAGE" ]; then
                dog_error "封面图片压缩失败（sips 转换失败）。"
                exit 1
            fi
        else
            # Fallback: use ffmpeg to convert. Quality scale is not the same as JPEG percent;
            # use a reasonable default that typically yields small size.
            if [ "$VERBOSE" = true ]; then
                ffmpeg -y -hide_banner -loglevel warning -i "$IMAGE_PATH" -q:v 5 "$COVER_TMP_IMAGE"
            else
                ffmpeg -y -hide_banner -loglevel error -nostats -i "$IMAGE_PATH" -q:v 5 "$COVER_TMP_IMAGE" >/dev/null 2>&1
            fi

            if [ $? -ne 0 ] || [ ! -f "$COVER_TMP_IMAGE" ]; then
                dog_error "封面图片压缩失败（ffmpeg 转换失败）。"
                exit 1
            fi
        fi

        COVER_IMAGE_PATH="$COVER_TMP_IMAGE"
    fi
else
    vlog "已指定 --no-compress，将直接使用原图作为封面"
fi

MEDIA_DIR=$(dirname "$MEDIA_PATH")
MEDIA_BASE=$(basename "$MEDIA_PATH")
MEDIA_NAME_NOEXT="${MEDIA_BASE%.*}"

TMP_OUT="${MEDIA_DIR}/${MEDIA_NAME_NOEXT}.setcover.tmp.${MEDIA_EXT}"

if [ -e "$TMP_OUT" ]; then
    rm -f "$TMP_OUT"
fi

vlog "音视频文件: $MEDIA_PATH"
vlog "图片文件: $IMAGE_PATH"
if [ "$COVER_IMAGE_PATH" != "$IMAGE_PATH" ]; then
    vlog "封面图片(已压缩): $COVER_IMAGE_PATH"
fi
vlog "正在写入封面..."

if [[ "$MEDIA_EXT" == "mp3" ]]; then
    FFMPEG_ARGS=(
        -y
        -i "$MEDIA_PATH"
        -i "$COVER_IMAGE_PATH"
        -map 0:a
        -map 1:v
        -c copy
        -id3v2_version 3
        -metadata:s:v title="Album cover"
        -metadata:s:v comment="Cover (front)"
        "$TMP_OUT"
    )
else
    FFMPEG_ARGS=(
        -y
        -i "$MEDIA_PATH"
        -i "$COVER_IMAGE_PATH"
        -map 0
        -map 1
        -c copy
        -disposition:v attached_pic
        "$TMP_OUT"
    )
fi

FFMPEG_LOG_FILE=""
if [ "$VERBOSE" = true ]; then
    ffmpeg "${FFMPEG_ARGS[@]}"
    FFMPEG_RC=$?
else
    FFMPEG_LOG_FILE=$(mktemp)
    ffmpeg -hide_banner -loglevel error -nostats "${FFMPEG_ARGS[@]}" 2>"$FFMPEG_LOG_FILE"
    FFMPEG_RC=$?
fi

if [ $FFMPEG_RC -ne 0 ]; then
    if [ "$VERBOSE" = true ]; then
        dog_error "封面设置失败（ffmpeg 执行失败）。"
    else
        reason=$(tail -n 1 "$FFMPEG_LOG_FILE" 2>/dev/null)
        if [ -z "$reason" ]; then
            reason="ffmpeg 执行失败"
        fi
        dog_error "封面设置失败: $reason"
    fi
    rm -f "$TMP_OUT" 2>/dev/null || true
    if [ -n "$FFMPEG_LOG_FILE" ]; then
        rm -f "$FFMPEG_LOG_FILE" 2>/dev/null || true
    fi
    exit 1
fi

if [ -n "$FFMPEG_LOG_FILE" ]; then
    rm -f "$FFMPEG_LOG_FILE" 2>/dev/null || true
fi

mv -f "$TMP_OUT" "$MEDIA_PATH"

dog_success "封面设置完成: $MEDIA_PATH"
