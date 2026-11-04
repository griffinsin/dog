#!/bin/bash

# Description: 手机截屏并保存到电脑（安卓 + iPhone，自动识别已连接设备）

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# ───────────────────────── 给维护者 ─────────────────────────
#
# 一个命令管两类手机：安卓走 adb，iPhone 走 Xcode 的 devicectl。
#
# 【设备发现】
#   安卓：adb devices，取状态为 device 的序列号；型号用 getprop 补一下更好认。
#   iPhone：xcrun devicectl list devices --json-output。注意这个列表是「本机配对过
#     的全部设备」，含手表/iPad/没在跟前的手机/本机模拟器，不能直接用！必须按两条
#     过滤：deviceType=="iPhone" 且 tunnelState=="connected"。实测里真机 USB 插上
#     是 transport=wired/tunnel=connected，模拟器是 sameMachine/disconnected，不在
#     场的是 None/unavailable —— 只有 connected 才真能截。tunnelState 是 JSON 里才
#     可靠的字段，文本输出的 State 列对有线/网络都显示 available，不可靠，所以必须
#     解析 JSON（devicectl 官方也只支持 --json-output 这一种脚本接口）。
#
# 【只有一台真机就免选】两类合一个列表统一编号；总数==1 直接截，>1 才让用户选。
#
# 【iPhone 截屏需 Xcode 27+】capture 子命令是 27 才有的（26.x 没有、更早的被删过）。
#   检测不到 capture 就不列 iPhone，只管安卓，并提示一句，不报错退出。
#
# 【依赖隔离】adb 只在有安卓时需要，xcrun/python3 只在找 iPhone 时需要。任一缺失
#   只是让对应那类设备不出现，另一类照常工作 —— 别硬性要求两样都装。
#
# 【adb 吃 stdin】adb 子命令统一 </dev/null，否则会吞掉终端输入（recv 里踩过）。
#
# 【中文输出用 ${var}】bash 3.2 UTF-8 locale 下裸 $var 紧跟多字节会吞字，见 globals.sh。

usage() {
    cat <<'HELP'
dog ss —— 手机截屏到电脑（安卓 + iPhone 自动识别）

用法
  dog ss                只连一台时直接截；多台时列出来让你选
  dog ss -s <设备ID>     指定设备：安卓序列号 或 iPhone 的 UDID/名称
  dog ss -h, --help     显示本帮助

说明
  存到 ~/Downloads/screenshot_年月日_时分秒.png（恒带时间戳，连拍不覆盖），
  截完在访达中定位选中。
  安卓走 adb，iPhone 走 Xcode 的 devicectl（截 iPhone 需 Xcode 27+）。
  只连一台设备时无需选择，直接截屏。
HELP
}

output_dir="$HOME/Downloads"
filename="screenshot"
want_id=""

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -s)
            shift
            if [ -z "$1" ] || [[ "$1" == -* ]]; then
                dog_error "参数 -s 需要设备 ID（安卓序列号或 iPhone UDID/名称）"
                usage; exit 1
            fi
            want_id="$1"; shift ;;
        -*) dog_error "未知参数: $1"; usage; exit 1 ;;
        *) dog_error "不支持的参数: $1"; usage; exit 1 ;;
    esac
done

# ── 统一设备表（bash 3.2 无关联数组，用三个并行数组）──
dev_platform=()   # android | ios
dev_id=()         # 安卓序列号 / iPhone identifier
dev_name=()       # 展示名

# 发现安卓设备
if command -v adb >/dev/null 2>&1; then
    while IFS=$'\t' read -r serial state; do
        [ "$state" = "device" ] || continue
        model=$(adb -s "$serial" shell getprop ro.product.model </dev/null 2>/dev/null | tr -d '\r')
        dev_platform+=("android")
        dev_id+=("$serial")
        dev_name+=("${model:-Android} (${serial})")
    done < <(adb devices 2>/dev/null | sed '1d')
fi

# 发现 iPhone 真机（需 Xcode 27+ 的 capture 子命令 + python3 解析 JSON）
ios_supported=false
if command -v xcrun >/dev/null 2>&1 && [ -x /usr/bin/python3 ]; then
    if xcrun devicectl device capture screenshot --help >/dev/null 2>&1; then
        ios_supported=true
        ios_tmp=$(mktemp)
        if xcrun devicectl list devices --json-output "$ios_tmp" >/dev/null 2>&1; then
            while IFS=$'\t' read -r id name; do
                [ -n "$id" ] || continue
                dev_platform+=("ios")
                dev_id+=("$id")
                dev_name+=("${name:-iPhone}")
            done < <(/usr/bin/python3 - "$ios_tmp" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for d in data.get("result", {}).get("devices", []):
    hw = d.get("hardwareProperties", {}) or {}
    cp = d.get("connectionProperties", {}) or {}
    dp = d.get("deviceProperties", {}) or {}
    # 只认真机 iPhone 且当前隧道已连接（排除手表/iPad/模拟器/不在场设备）
    if hw.get("deviceType") == "iPhone" and cp.get("tunnelState") == "connected":
        ident = d.get("identifier") or ""
        name = dp.get("name") or "iPhone"
        print(ident + "\t" + name)
PY
)
        fi
        rm -f "$ios_tmp"
    fi
fi

total=${#dev_id[@]}

# ── 选定目标设备 ──
sel=-1
if [ -n "$want_id" ]; then
    for i in "${!dev_id[@]}"; do
        if [ "${dev_id[$i]}" = "$want_id" ] || [ "${dev_name[$i]}" = "$want_id" ]; then
            sel=$i; break
        fi
    done
    if [ "$sel" -lt 0 ]; then
        dog_error "未找到已连接的设备: ${want_id}"
        [ "$total" -gt 0 ] && dog_log "当前已连接 ${total} 台，直接 dog ss 可列出选择"
        exit 1
    fi
elif [ "$total" -eq 0 ]; then
    dog_error "未发现已连接的安卓或 iPhone 设备"
    dog_log "安卓：用数据线连接并开启 USB 调试；iPhone：连接并在手机上点「信任」"
    [ "$ios_supported" = false ] && command -v xcrun >/dev/null 2>&1 \
        && dog_log "（当前 Xcode 不支持 iPhone 截屏，需升级到 Xcode 27+）"
    exit 1
elif [ "$total" -eq 1 ]; then
    sel=0
    dog_log "仅一台设备，直接截屏: ${dev_name[0]}"
else
    print_color "$CYAN" "发现 ${total} 台设备，请选择："
    for i in "${!dev_id[@]}"; do
        if [ "${dev_platform[$i]}" = "android" ]; then label="安卓  "; else label="iPhone"; fi
        printf "  [%d] %s  %s\n" "$((i+1))" "${label}" "${dev_name[$i]}"
    done
    printf "请输入序号（直接回车取消）: "
    read -r choice
    [ -z "$choice" ] && { dog_error "已取消"; exit 1; }
    if ! printf '%s' "$choice" | grep -qE '^[0-9]+$' || [ "$choice" -lt 1 ] || [ "$choice" -gt "$total" ]; then
        dog_error "无效的序号: ${choice}"
        exit 1
    fi
    sel=$((choice-1))
fi

platform="${dev_platform[$sel]}"
device_id="${dev_id[$sel]}"
device_label="${dev_name[$sel]}"

# ── 组装输出路径（恒带时间戳，连拍不覆盖）──
filename="${filename}_$(date +%Y%m%d_%H%M%S)"
output_path="${output_dir}/${filename}.png"
mkdir -p "$output_dir" 2>/dev/null

dog_log "设备: ${device_label}"
dog_log "正在截屏..."

# ── 按平台截屏 ──
if [ "$platform" = "android" ]; then
    device_shot="/sdcard/${filename}.png"
    if ! adb -s "$device_id" shell screencap -p "$device_shot" </dev/null; then
        dog_error "截屏失败，请检查设备连接和权限"
        exit 1
    fi
    pull_ok=true
    adb -s "$device_id" pull "$device_shot" "$output_path" </dev/null || pull_ok=false
    # 无论成败都清掉设备上的临时文件，避免残留
    adb -s "$device_id" shell rm "$device_shot" </dev/null >/dev/null 2>&1
    if [ "$pull_ok" != true ]; then
        dog_error "无法从设备拉取截图"
        exit 1
    fi
else
    if ! xcrun devicectl device capture screenshot -d "$device_id" --destination "$output_path" >/dev/null 2>&1; then
        dog_error "iPhone 截屏失败：请确认手机已解锁、已点「信任此电脑」"
        exit 1
    fi
fi

# ── 校验产物并定位 ──
if [ ! -s "$output_path" ]; then
    dog_error "截屏文件为空或未生成: ${output_path}"
    exit 1
fi

dog_success "截屏成功！保存到: ${output_path}  ($(du -h "$output_path" 2>/dev/null | cut -f1 | tr -d ' '))"
open -R "$output_path" >/dev/null 2>&1 || dog_log "无法自动在访达中定位截图文件"
