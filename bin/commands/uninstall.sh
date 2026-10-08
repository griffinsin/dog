#!/bin/bash

# Description: 卸载 dog 并清理它创建的数据

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# ───────────────────────── 给维护者 ─────────────────────────
#
# 这个命令是「干净卸载」：把 dog 自己装的和自己创建的东西清掉，不多不少。
#
# 【只删 dog 自己创建的，别人的东西一律不碰】
#   - ~/.ssh/* 绝不动：dog ssh/setssh 会在这里生成密钥，但那是用户真实使用的
#     SSH 私钥，删了会让人登不上服务器。卸载工具去删用户的密钥是灾难。
#   - ~/.zshrc 不动：dog 本身不往里写东西（brew 的 PATH 由 brew 管）。
#   - ~/Downloads、~/Videos 等下载产物不动：那是用户的文件，不是 dog 的。
#   - ~/.mace 下只清 dev_settings（dog is 克隆的），不整个删 —— 同目录还有
#     mace / homebrew-mace / treasury 等别的工具的东西。
#
# 【为什么默认要清 ~/.config/dog】
#   里面是 bili_cookies.txt，即 B 站登录凭证。它比什么都该清 —— 把登录态留在
#   别人的机器上是真实的账号风险。
#
# 【不做「反取证」】
#   卸载能清掉的只是 dog 自己的文件。brew 的安装日志、shell 历史（你敲过的
#   dog 命令）、Spotlight 索引等都属于那台机器、不归 dog 管，本命令不去碰它们，
#   也不声称卸载后「查不到用过」。诚实的卸载 != 抹除使用痕迹。
#
# 【自删安全】bin/dog 是 source 执行子命令，脚本已在内存里；brew uninstall 把
#   磁盘文件删掉也不影响当前这次执行跑完。

usage() {
    cat <<'HELP'
dog uninstall —— 卸载 dog 并清理它创建的数据

用法
  dog uninstall            列出将清理的内容，确认后执行
  dog uninstall -n         只列出，不删除（dry-run）
  dog uninstall -y         不询问直接执行
  dog uninstall --purge    连同 ~/.mace/dev_settings 一起清（默认会单独询问）

清理范围
  - Homebrew 包 dog 及其 tap griffinsin/dog
  - ~/.config/dog/            dog 自己的配置（含 B 站登录 cookie，建议清）
  - dog runlog 的临时日志      $TMPDIR/dog_runlog.*、/tmp/dog_runlog.*
  - ~/.mace/dev_settings      dog is 克隆的设置仓库（你的私人数据，单独询问）

不会碰（不是 dog 装的，或属于你的真实数据）
  - ~/.ssh/*                  真实 SSH 密钥
  - ~/.zshrc                  dog 不往里写
  - ~/Downloads、~/Videos 等   你下载的文件

说明
  卸载只清 dog 自己的文件。brew 日志、shell 历史、系统索引属于这台机器本身，
  不归 dog 管，本命令不碰，也不保证卸载后「看不出用过」。
HELP
}

dry_run=false
assume_yes=false
purge=false

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -n|--dry-run) dry_run=true; shift ;;
        -y|--yes) assume_yes=true; shift ;;
        --purge) purge=true; shift ;;
        -*) dog_error "未知参数: $1"; usage >&2; exit 1 ;;
        *) dog_error "uninstall 不接受位置参数: $1"; usage >&2; exit 1 ;;
    esac
done

config_dir="$HOME/.config/dog"
dev_settings="$HOME/.mace/dev_settings"
tmp_base="${TMPDIR:-/tmp}"; tmp_base="${tmp_base%/}"

# 收集将要清理的项，逐条显示。brew 相关用 brew 自己查，避免写死路径。
have_brew=false
command -v brew >/dev/null 2>&1 && have_brew=true

brew_installed=false
if [ "$have_brew" = true ] && brew list dog >/dev/null 2>&1; then
    brew_installed=true
fi
tap_present=false
if [ "$have_brew" = true ] && brew tap 2>/dev/null | grep -qx 'griffinsin/dog'; then
    tap_present=true
fi

# runlog 临时日志（当前用户的，用通配收集，可能一个都没有）
runlog_files=()
for f in "$tmp_base"/dog_runlog.* /tmp/dog_runlog.*; do
    [ -e "$f" ] && runlog_files+=("$f")
done

print_color "$CYAN" "将清理以下内容："
echo
if [ "$brew_installed" = true ]; then
    echo "  [brew] 卸载包 dog（$(brew --cellar dog 2>/dev/null)）"
else
    echo "  [brew] 包 dog 未通过 brew 安装，跳过"
fi
if [ "$tap_present" = true ]; then
    echo "  [brew] 移除 tap griffinsin/dog"
fi
if [ -e "$config_dir" ]; then
    echo "  [配置] ${config_dir}  （含 B 站登录 cookie）"
else
    echo "  [配置] ${config_dir} 不存在，跳过"
fi
if [ "${#runlog_files[@]}" -gt 0 ]; then
    echo "  [临时] runlog 日志 ${#runlog_files[@]} 个"
fi
if [ -e "$dev_settings" ]; then
    if [ "$purge" = true ]; then
        echo "  [数据] ${dev_settings}  （--purge：一并清理）"
    else
        echo "  [数据] ${dev_settings}  （你的私人数据，稍后单独询问）"
    fi
fi
echo
print_color "$YELLOW" "不会碰：~/.ssh 密钥、~/.zshrc、~/Downloads 等你的文件"
echo

if [ "$dry_run" = true ]; then
    dog_log "dry-run：以上内容未删除"
    exit 0
fi

if [ "$assume_yes" = false ]; then
    printf "确认执行卸载？[y/N]: "
    read -r ans
    case "$ans" in
        [Yy]*) ;;
        *) dog_error "已取消"; exit 1 ;;
    esac
fi

# ── 先清数据，再卸 brew（brew 卸载会删掉本脚本文件，放最后）──

if [ -e "$config_dir" ]; then
    if rm -rf -- "$config_dir"; then
        dog_success "已删除配置: ${config_dir}"
    else
        dog_error "删除失败: ${config_dir}"
    fi
fi

if [ "${#runlog_files[@]}" -gt 0 ]; then
    rm -f -- "${runlog_files[@]}" 2>/dev/null \
        && dog_success "已清理 ${#runlog_files[@]} 个 runlog 临时日志"
fi

# dev_settings 是用户私人数据，默认单独确认（--purge 或 -y 跳过询问）
if [ -e "$dev_settings" ]; then
    do_dev=false
    if [ "$purge" = true ] || [ "$assume_yes" = true ]; then
        do_dev=true
    else
        printf "一并删除 %s？这是你用 dog is 同步的个人设置 [y/N]: " "$dev_settings"
        read -r ans2
        case "$ans2" in [Yy]*) do_dev=true ;; esac
    fi
    if [ "$do_dev" = true ]; then
        rm -rf -- "$dev_settings" \
            && dog_success "已删除: ${dev_settings}" \
            || dog_error "删除失败: ${dev_settings}"
    else
        dog_log "保留: ${dev_settings}"
    fi
fi

if [ "$tap_present" = true ]; then
    brew untap griffinsin/dog >/dev/null 2>&1 \
        && dog_success "已移除 tap griffinsin/dog" \
        || dog_log "移除 tap 失败或已不存在"
fi

if [ "$brew_installed" = true ]; then
    dog_log "正在 brew uninstall dog ..."
    if brew uninstall dog >/dev/null 2>&1; then
        dog_success "已卸载 brew 包 dog"
    else
        dog_error "brew uninstall dog 失败，请手动执行"
    fi
fi

echo
dog_success "dog 已清理完成"
dog_log "提示：brew 安装日志、shell 历史等属于本机，不在 dog 清理范围内"
