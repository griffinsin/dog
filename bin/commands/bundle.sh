#!/bin/bash

# Description: 将当前 git 工程的完整历史导出为单个 .bundle 文件

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# ───────────────────────── 给维护者 ─────────────────────────
#
# git bundle 把一个仓库的全部历史(所有分支/标签)打进单个文件，离线可搬运、
# 可校验。接收方用 `git clone xxx.bundle 目标目录` 就能本地解包成完整仓库，
# 全程不碰网络 —— bundle 在 clone 时扮演「远程」的角色。
#
# 【不生成 restore.sh】原始脚本会额外写一个 restore.sh 再打成 zip，但那只是
#   `git clone` 的三行包装，git 本身没这东西、也非必需。这里只产出干净的单个
#   .bundle，还原命令在成功提示里直接给出，少一个要维护的生成物。
#
# 【--all 含全部历史】打包的是所有 ref 的完整提交历史，历史里曾经提交过的敏感
#   信息(.env/密钥)也会一并带走 —— 分发前请自行留意，bundle 不会因为现在删了就不含。
#
# 【只含已提交的】工作区里未提交/未跟踪的改动不进 bundle。有脏改动时提醒一句，
#   免得对方还原后发现「少东西」。
#
# 【定位仓库】用 git rev-parse --show-toplevel 从当前目录向上找仓库根；找不到
#   就报错退出(不是 git 仓库)。后续都用 git -C "$repo_root" 操作，避免在子目录里跑偏。
#
# 【中文输出用 ${var}】bash 3.2 UTF-8 locale 下裸 $var 紧跟多字节会吞字，见 globals.sh。

usage() {
    cat <<'HELP'
dog bundle —— 把当前 git 工程的完整历史导出为单个 .bundle 文件

用法
  dog bundle                在当前 git 工程根生成 bundle，存到 ~/Downloads
  dog bundle -o <目录>       改变输出目录（默认 ~/Downloads）
  dog bundle -h, --help     显示本帮助

说明
  必须在一个 git 仓库内运行（当前目录或其上级是 git 工程），否则报错退出。
  产物：<仓库名>_<时间戳>.bundle，含所有分支/标签的完整历史。
  完成后在访达中定位选中该文件。

还原（接收方，纯本地、无需网络）
  git clone <仓库名>_<时间戳>.bundle 目标目录
HELP
}

out_dir="$HOME/Downloads"

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -o)
            shift
            if [ -z "$1" ] || [[ "$1" == -* ]]; then
                dog_error "参数 -o 需要一个目录"; usage; exit 1
            fi
            out_dir="$1"; shift ;;
        -*) dog_error "未知参数: $1"; usage; exit 1 ;;
        *) dog_error "不支持的参数: $1"; usage; exit 1 ;;
    esac
done

# ── 定位当前 git 工程 ──
if ! command -v git >/dev/null 2>&1; then
    dog_error "未找到 git"
    exit 1
fi

repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$repo_root" ]; then
    dog_error "当前目录不是 git 仓库（当前目录及其上级都不是 git 工程）"
    dog_log "请 cd 到目标 git 工程目录后再运行 dog bundle"
    exit 1
fi

repo_name=$(basename "$repo_root")
branch=$(git -C "$repo_root" symbolic-ref --short HEAD 2>/dev/null || git -C "$repo_root" rev-parse --short HEAD 2>/dev/null)

dog_log "仓库: ${repo_root}"
dog_log "分支: ${branch:-未知}"

# 有未提交/未跟踪改动时提醒：bundle 只含已提交历史
if [ -n "$(git -C "$repo_root" status --porcelain 2>/dev/null)" ]; then
    print_color "$YELLOW" "注意：工作区有未提交/未跟踪的改动，bundle 只包含已提交的历史，这些改动不会被导出"
fi

# ── 生成 bundle ──
mkdir -p "$out_dir" 2>/dev/null
ts=$(date +%Y%m%d_%H%M%S)
dest="${out_dir%/}/${repo_name}_${ts}.bundle"

dog_log "打包中，请稍候..."
if ! git -C "$repo_root" bundle create "$dest" --all; then
    dog_error "bundle 生成失败（空仓库？——没有任何提交时无法打包）"
    rm -f "$dest" 2>/dev/null
    exit 1
fi

# ── 校验完整性（纯本地）──
if ! git -C "$repo_root" bundle verify "$dest" >/dev/null 2>&1; then
    dog_error "bundle 校验未通过，文件可能不完整，已删除: ${dest}"
    rm -f "$dest" 2>/dev/null
    exit 1
fi

if [ ! -s "$dest" ]; then
    dog_error "bundle 文件为空或未生成: ${dest}"
    exit 1
fi

ref_count=$(git -C "$repo_root" bundle list-heads "$dest" 2>/dev/null | wc -l | tr -d ' ')
size=$(du -h "$dest" 2>/dev/null | cut -f1 | tr -d ' ')

dog_success "完成！${dest}  (${size}，含 ${ref_count} 个分支/标签)"
echo
dog_log "还原（接收方，纯本地、无需网络）："
print_color "$CYAN" "  git clone \"$(basename "$dest")\" 目标目录"
echo

open -R "$dest" >/dev/null 2>&1 || dog_log "无法自动在访达中定位该文件"
