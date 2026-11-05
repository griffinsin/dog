#!/bin/bash

# Description: 把 .bundle 文件在当前目录还原成完整 git 仓库

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# ───────────────────────── 给维护者 ─────────────────────────
#
# dog bundle 的逆操作：对一个 .bundle 执行本地 `git clone`，在当前目录展开成带
# 完整历史的仓库。全程不碰网络 —— clone 时 bundle 扮演「远程」的角色。
#
# 【校验用 list-heads，不用 verify】实测 `git bundle verify` 在「非仓库目录」里
#   会返回非 0(它需要一个仓库来做 prerequisite 检查)，拿它当校验门会误杀。
#   `git bundle list-heads` 在非仓库目录下正常工作、坏文件会失败，正好当有效性探针。
#
# 【目标目录名】默认从文件名推导：去掉 .bundle，再去掉 dog bundle 加的
#   _YYYYMMDD_HHMMSS 时间戳后缀，得回原仓库名(demo_20261105_120600.bundle -> demo)。
#   不符合该模式就用去扩展名后的整名。可用第二个参数显式指定。
#
# 【已存在非空目录】交给 git clone 报错即可(它的提示很清楚)，但先行检查能给更友好的话。
#
# 【删 origin】clone 完成后 git 会把 origin 指向那个 .bundle 路径；该文件通常会被
#   搬走/删掉，留着只会让日后 git pull 报错。还原成「独立仓库」更符合预期，故移除。
#
# 【中文输出用 ${var}】bash 3.2 UTF-8 locale 下裸 $var 紧跟多字节会吞字，见 globals.sh。

usage() {
    cat <<'HELP'
dog unbundle —— 把 .bundle 文件在当前目录还原成完整 git 仓库

用法
  dog unbundle <文件.bundle>            在当前目录还原，目录名自动按文件名推导
  dog unbundle <文件.bundle> <目标目录>  还原到指定目录名
  dog unbundle -h, --help              显示本帮助

说明
  纯本地操作、无需网络（bundle 自包含全部历史）。
  目标目录默认由文件名推导（去掉 .bundle 和时间戳后缀）。
  若目标目录已存在且非空，会报错中止，不覆盖。
HELP
}

input=""
target=""

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -*) dog_error "未知参数: $1"; usage; exit 1 ;;
        *)
            if [ -z "$input" ]; then input="$1"
            elif [ -z "$target" ]; then target="$1"
            else dog_error "参数过多: $1"; usage; exit 1
            fi
            shift ;;
    esac
done

if ! command -v git >/dev/null 2>&1; then
    dog_error "未找到 git"; exit 1
fi

if [ -z "$input" ]; then
    dog_error "请提供要还原的 .bundle 文件"
    usage; exit 1
fi

if [ ! -f "$input" ]; then
    dog_error "文件不存在: ${input}"; exit 1
fi

# 有效性探针（非仓库目录下可用）
if ! git bundle list-heads "$input" >/dev/null 2>&1; then
    dog_error "不是有效的 bundle 文件（或已损坏）: ${input}"; exit 1
fi

# 推导目标目录名
if [ -z "$target" ]; then
    base=$(basename "$input")
    name="${base%.bundle}"
    if [[ "$name" =~ ^(.+)_[0-9]{8}_[0-9]{6}$ ]]; then
        name="${BASH_REMATCH[1]}"
    fi
    target="$name"
fi

if [ -e "$target" ] && [ -n "$(ls -A "$target" 2>/dev/null)" ]; then
    dog_error "目标目录已存在且非空: ${target}"
    dog_log "换个目录名：dog unbundle \"${input}\" 其他目录名"
    exit 1
fi

ref_count=$(git bundle list-heads "$input" 2>/dev/null | wc -l | tr -d ' ')
dog_log "还原: ${input}"
dog_log "目标: $(pwd)/${target}  (含 ${ref_count} 个分支/标签)"

if ! git clone "$input" "$target"; then
    dog_error "还原失败"
    exit 1
fi

# 断开指向 bundle 文件的 origin，还原成独立仓库
git -C "$target" remote remove origin >/dev/null 2>&1

dog_success "完成！已还原到: $(pwd)/${target}"
dog_log "进入目录：cd \"${target}\""
