#!/bin/bash

# Description: 下载 B 站视频/选集/合集，交互选择范围与画质

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# 定位 lib/bili：仓库里和 brew 装完后的布局不一样，必须两种都兼容。
#   仓库:     <root>/bin/commands/bili.sh   -> <root>/lib/bili
#   brew 装后: <prefix>/commands/bili.sh     -> <prefix>/lib/bili      （少了 bin/ 一层）
# 其他命令只用 dirname×3 找 globals.sh，而 Formula 会把那一行重写成绝对路径，
# 所以它们靠重写能跑；bili 是第一个引用 lib/ 下其他文件的命令，数层数必然算错。
# 这里不数层数，直接看哪个候选目录真实存在。
_bili_cmd_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BILI_LIB=""
# 判定用「目标文件是否存在」而不是「目录是否存在」：目录可能是旧版留下的空壳。
for _cand in "$_bili_cmd_dir/../lib/bili" "$_bili_cmd_dir/../../lib/bili"; do
    if [ -f "$_cand/bili_tool.py" ] && [ -f "$_cand/vendor/bili_get.py" ]; then
        BILI_LIB="$(cd "$_cand" && pwd)"
        break
    fi
done
if [ -z "$BILI_LIB" ]; then
    dog_error "找不到 lib/bili（已查 $_bili_cmd_dir 的上一级和上两级）"
    dog_error "若是 brew 安装，试 dog upgrade 重装"
    exit 1
fi
BILI_TOOL="$BILI_LIB/bili_tool.py"          # dog 自己的：探测 + 扫码登录
BILI_GET="$BILI_LIB/vendor/bili_get.py"     # 外部快照，统一下载入口
COOKIE_DEFAULT="$HOME/.config/dog/bili_cookies.txt"

# ───────────────────────── 给维护者 ─────────────────────────
#
# 【目录分工】
#   lib/bili/bili_tool.py    dog 自己的 Python：probe（探测）+ login/check（扫码登录）
#   lib/bili/vendor/*.py     从 ~/dev/scripts 逐字节复制的外部快照，**不要在这里改**
#   lib/bili/vendor/BILIBILI-NOTES.md   那套代码的说明书，下面多处判断以它为依据
#
#   vendor/ 里 4 个脚本（bili_get / bili_dl / bili_season / bili_space_list）一行未改，
#   可以直接 cmp 对 ~/dev/scripts 验证漂移：
#       for f in bili_get bili_dl bili_season bili_space_list; do
#         cmp ~/dev/scripts/$f.py lib/bili/vendor/$f.py; done
#   要改逻辑就去 ~/dev/scripts 改，再复制回来。它们靠 __file__ 相对路径互相调用
#   （bili_get -> bili_season -> bili_dl），所以必须整组放在同一目录。
#
# 【为什么画质菜单必须先探测】
#   BILIBILI-NOTES.md 第五节：accept_description 列的是视频「存在」的画质，
#   dash.video 里才是你「实际能取到」的，两者经常不一致。实测同一视频
#   声明到 1080P，匿名只能取到 480P。照固定表列菜单的话，用户选 1080P 会被
#   静默降级，不报错。所以菜单只列 bili_probe.py 返回的 Q 行。
#
# 【为什么要有扫码登录】
#   720P 以上被登录门槛挡着，而 SESSDATA 是 httpOnly、JS 读不到，
#   过去只能靠浏览器扩展导出。官方 web 扫码登录接口能完全在终端走完，
#   不用密码、不碰验证码。cookie 落盘时强制 0600——它等同于登录凭证。
#
# 【风控】笔记第一节：-352 不能硬闯，冷却几十分钟到几小时。
#   本命令一次探测 5 个接口（首页/nav/wbi_view/pagelist/playurl），彼此留 0.6s。
#   都不是空间列表那类高危接口。-y 跳过交互但不减少探测次数。

usage() {
    cat <<'HELP'
dog bili —— 下载 B 站视频 / 视频选集 / 合集

用法
  dog bili [URL或BV号] [选项]        不给则从剪贴板读
  dog bili --login | --whoami | --logout

最常用：先 cd 到目标目录，复制好链接，然后直接跑
  dog bili
它会从剪贴板取链接（剪贴板里没有就提示你粘贴），然后依次问两件事：

  ① 下载范围（菜单随视频类型变，直接回车=全部）
       合集    1) 只下当前这个视频  2) 整个合集 N 个  3) 指定范围
       多分P   1) 只下当前分P       2) 全部 N 个分P   3) 指定范围
       单个视频  不问，直接下
  ② 画质（直接回车=最高可用）
       只列「实际能取到」的，不照固定表硬列。未登录通常只有 480P/360P，
       并会提示站点声明存在哪些更高画质。

跳过交互
  dog bili BVxxx -y                  全部 + 最高可用画质，全程不问
  dog bili BVxxx --this              只下当前这一个
  dog bili BVxxx --all               整个合集 / 全部分P
  dog bili BVxxx --pick 2-5          指定范围（也可 1-10,15）
  dog bili BVxxx --all -q 32         指定画质 id
  dog bili BVxxx -o ~/Videos/美文     指定输出目录
  dog bili BVxxx --list              只看内容，不下载
  dog bili BVxxx -n                  只打印将执行的命令，不下载

账号（720P 以上必须登录）
  dog bili --login                   手机 B站 App 扫码，首次会提示装 qrencode
  dog bili --whoami                  查看当前登录态
  dog bili --logout                  删除本地 cookie
  cookie 存在 ~/.config/dog/bili_cookies.txt，权限 600

URL 怎么传（? 和 & 是 shell 的特殊字符，由 shell 先处理，脚本救不了）
  dog bili                           推荐：从剪贴板读，不经过 shell，无需引号
  dog bili BVxxx                     BV 号没有特殊字符，不用引号
  dog bili 'https://...?p=7'         直接给 URL 必须加引号
  URL 里的 ?p=N 会被识别，「只下当前」据此定位到第 N 个分P

文件命名
  合集成员（单独下或整批下）   {序号}-{视频标题}.mp4   序号两条路径一致，排序正确
  多分P视频                   {分P号}-{分P标题}.mp4
  独立单个视频                {视频标题}.mp4

重跑是安全的：文件已存在会预检跳过，不重复下载；中断的分片下次续传。

选项
  -o <目录>      输出目录（默认当前目录）
  -q <画质id>    80=1080P 64=720P 32=480P 16=360P
  --pick <范围>  指定范围，如 1-10,15
  --all          下载全部
  --this         只下当前这一个
  -y             不交互，全部用默认
  -n             只打印将执行的命令
  --list         只列出内容
  --cookies <f>  指定 cookie 文件
  --codec <c>    avc(默认) | hev | av0
  -h, --help     显示本帮助
HELP
}

ensure_qrencode() {
    command -v qrencode >/dev/null 2>&1 && return 0
    dog_error "扫码登录需要 qrencode 来在终端画二维码"
    printf "是否现在安装？(brew install qrencode) [Y/n] "
    read -r yn
    case "$yn" in
        [Nn]*) return 1 ;;
    esac
    brew install qrencode || return 1
    command -v qrencode >/dev/null 2>&1
}

outdir="."
quality=""
pick=""
scope=""
assume_yes=false
dry_run=false
list_only=false
cookies=""
codec="avc"
url=""
action="download"

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --login)  action="login";  shift ;;
        --logout) action="logout"; shift ;;
        --whoami) action="whoami"; shift ;;
        -o) outdir="$2"; shift 2 ;;
        -q) quality="$2"; shift 2 ;;
        --pick) pick="$2"; scope="pick"; shift 2 ;;
        --all)  scope="all";  shift ;;
        --this) scope="this"; shift ;;
        -y) assume_yes=true; shift ;;
        -n) dry_run=true; shift ;;
        --list) list_only=true; shift ;;
        --cookies) cookies="$2"; shift 2 ;;
        --codec) codec="$2"; shift 2 ;;
        -*) dog_error "未知选项 $1"; usage >&2; exit 1 ;;
        *) url="$1"; shift ;;
    esac
done

[ -z "$cookies" ] && cookies="$COOKIE_DEFAULT"

# ───────────────────────── 账号相关动作 ─────────────────────────

case "$action" in
    login)
        ensure_qrencode || { dog_error "没有 qrencode，无法扫码登录"; exit 1; }
        python3 "$BILI_TOOL" login -o "$cookies"
        exit $?
        ;;
    whoami)
        if [ ! -f "$cookies" ]; then
            dog_log "未登录（没有 cookie 文件: $cookies）"
            dog_log "画质上限 480P。运行 dog bili --login 扫码登录"
            exit 1
        fi
        uname_out=$(python3 "$BILI_TOOL" check -o "$cookies" 2>/dev/null)
        if [ -n "$uname_out" ]; then
            dog_success "已登录: $uname_out"
            exit 0
        fi
        dog_error "cookie 存在但已失效，请重新 dog bili --login"
        exit 1
        ;;
    logout)
        if [ -f "$cookies" ]; then
            rm -f "$cookies" && dog_success "已删除 cookie: $cookies"
        else
            dog_log "本来就没有 cookie 文件"
        fi
        exit 0
        ;;
esac

# ───────────────────────── 下载流程 ─────────────────────────

# ── 没给 URL：从剪贴板读，再退化为提示粘贴 ─────────────────────
#
# 为什么要这么做：URL 里的 ? 和 & 是 shell 在把参数交给 dog 之前就处理掉的，
# 脚本里无论怎么写都救不回来 ——
#   ...BVxxx?p=7       zsh 报 no matches found，命令根本没执行
#   ...?p=7&t=30       & 被当成后台符号，命令截断，&t=30 丢失
# zsh 的 noglob 能救 ? 但救不了 &（实测），做成包装函数是半修还给人错觉。
# 根本办法是别让 URL 经过 shell：剪贴板和 read 都不经 shell 解析。
if [ -z "$url" ]; then
    if command -v pbpaste >/dev/null 2>&1; then
        clip=$(pbpaste 2>/dev/null | tr -d '\r' | head -1)
        if printf '%s' "$clip" | grep -qE 'BV[0-9A-Za-z]{10}'; then
            url="$clip"
            dog_log "从剪贴板读到: $url"
        fi
    fi
fi

if [ -z "$url" ]; then
    # 回显识别结果前先说明来源，不静默拿一个用户没预期的东西去下载
    if command -v pbpaste >/dev/null 2>&1; then
        dog_log "剪贴板里没有 B 站链接或 BV 号"
    fi
    printf "请粘贴 URL 或 BV 号（直接回车取消）: "
    read -r url
    url=$(printf '%s' "$url" | tr -d '\r')
    if [ -z "$url" ]; then
        dog_error "已取消"
        exit 1
    fi
fi

if ! printf '%s' "$url" | grep -qE 'BV[0-9A-Za-z]{10}'; then
    dog_error "识别不到 BV 号: $url"
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    dog_error "未找到 python3"
    exit 1
fi
if ! command -v ffmpeg >/dev/null 2>&1 && [ "$list_only" = false ]; then
    dog_error "未找到 ffmpeg，请先安装: brew install ffmpeg"
    exit 1
fi

cookie_arg=()
[ -f "$cookies" ] && cookie_arg=(--cookies "$cookies")

# URL 里带 ?p=3 时，「只下当前这个」应该指第 3 个分P 而不是第 1 个。
# 用 bash 自带正则而不是 sed：.zshrc 里有 coreutils/gnubin，sed/grep 到底是
# GNU 还是 BSD 随 shell 上下文变化，\+ 这类 GNU 专有语法在 BSD sed 下静默不匹配
# （BILIBILI-NOTES.md 第九节记过反向的同类坑：stat -f%z 被 GNU stat 接走）。
cur_page=1
if [[ "$url" =~ [?\&]p=([0-9]+) ]]; then
    cur_page="${BASH_REMATCH[1]}"
fi

dog_log "探测中..."
probe=$(python3 "$BILI_TOOL" probe "$url" "${cookie_arg[@]}" 2>&1)
probe_rc=$?

err=$(printf '%s\n' "$probe" | awk -F'\t' '$1=="ERR"{print $2}')
if [ -n "$err" ]; then
    dog_error "$err"
    exit 1
fi
if [ $probe_rc -ne 0 ]; then
    dog_error "探测失败:"
    printf '%s\n' "$probe" >&2
    exit 1
fi

g() { printf '%s\n' "$probe" | awk -F'\t' -v k="$1" '$1==k{print $2; exit}'; }
kind=$(g KIND); title=$(g TITLE); up=$(g UP); npages=$(g PAGES)
logged=$(g LOGGED); season_title=$(g SEASON_TITLE); season_count=$(g SEASON_COUNT)
season_index=$(g SEASON_INDEX); season_width=$(g SEASON_WIDTH)
qdecl=$(g QDECL)

printf '%s\n' "$probe" | awk -F'\t' '$1=="WARN"{print "  ! "$2}' >&2

if [ "$kind" = "season" ]; then
    label="合集"
elif [ "$kind" = "pages" ]; then
    label="视频选集"
else
    label="单个视频"
fi
echo
print_color "$CYAN" "识别结果：$label"
echo "  标题: $title"
echo "  UP:   $up"
case "$kind" in
    season)
        echo "  合集『$season_title』共 $season_count 个视频"
        [ "$npages" -gt 1 ] 2>/dev/null && echo "  （当前这个视频自身还有 $npages 个分P）"
        ;;
    pages) echo "  共 $npages 个分P" ;;
esac
if [ "$logged" = "1" ]; then
    print_color "$GREEN" "  已登录"
else
    print_color "$YELLOW" "  未登录 —— 画质上限 480P（dog bili --login 可扫码登录）"
fi
echo

if [ "$list_only" = true ]; then
    exec python3 "$BILI_GET" "$url" --list "${cookie_arg[@]}" --codec "$codec"
fi

# ── 菜单1：下载范围 ──────────────────────────────────────────
if [ "$assume_yes" = true ] && [ -z "$scope" ]; then
    scope="all"
fi

if [ -z "$scope" ] && [ "$kind" != "single" ]; then
    if [ "$kind" = "season" ]; then
        one_desc="只下当前这个视频「$title」"
        all_desc="下载整个合集『$season_title』共 $season_count 个视频"
        range_hint="按合集顺序，第几个视频"
    else
        one_desc="只下当前这个分P（P$cur_page）"
        all_desc="下载全部 $npages 个分P"
        range_hint="分P号"
    fi
    print_color "$CYAN" "下载范围："
    echo "  1) $one_desc"
    echo "  2) $all_desc"
    echo "  3) 指定范围（$range_hint，如 1-10,15）"
    while true; do
        printf "请选择 [1/2/3] (默认 2): "
        read -r ans
        [ -z "$ans" ] && ans=2
        case "$ans" in
            1) scope="this"; break ;;
            2) scope="all";  break ;;
            3)
                printf "输入范围（%s）: " "$range_hint"
                read -r pick
                if [ -z "$pick" ]; then
                    dog_error "范围不能为空"
                    continue
                fi
                scope="pick"; break ;;
            *) dog_error "无效选择" ;;
        esac
    done
    echo
fi
[ -z "$scope" ] && scope="all"

# ── 菜单2：画质 ─────────────────────────────────────────────
qlines=$(printf '%s\n' "$probe" | awk -F'\t' '$1=="Q"{print $2"\t"$3"\t"$4"\t"$5}')

if [ -z "$quality" ] && [ -n "$qlines" ]; then
    if [ "$assume_yes" = true ]; then
        quality=$(printf '%s\n' "$qlines" | head -1 | cut -f1)
    else
        print_color "$CYAN" "可用画质（实际能取到的）："
        i=0
        while IFS=$'\t' read -r qid qname qres qcodec; do
            i=$((i + 1))
            printf "  %d) %-10s %-12s %s\n" "$i" "$qname" "$qres" "$qcodec"
        done <<< "$qlines"
        nq=$i
        if [ -n "$qdecl" ] && [ "$logged" != "1" ]; then
            print_color "$YELLOW" "  站点声明存在：$qdecl"
            print_color "$YELLOW" "  更高画质需登录 —— dog bili --login"
        fi
        while true; do
            printf "请选择画质 [1-%d] (默认 1，最高): " "$nq"
            read -r ans
            [ -z "$ans" ] && ans=1
            if printf '%s' "$ans" | grep -qE '^[0-9]+$' && [ "$ans" -ge 1 ] && [ "$ans" -le "$nq" ]; then
                quality=$(printf '%s\n' "$qlines" | sed -n "${ans}p" | cut -f1)
                break
            fi
            dog_error "无效选择"
        done
        echo
    fi
fi

# ── 组装并执行 ──────────────────────────────────────────────
cmd=(python3 "$BILI_GET" "$url" -o "$outdir" --codec "$codec")
[ ${#cookie_arg[@]} -gt 0 ] && cmd+=("${cookie_arg[@]}")
[ -n "$quality" ] && cmd+=(-q "$quality")

case "$scope" in
    this)
        if [ "$kind" = "season" ]; then
            cmd+=(--this-only)
        else
            cmd+=(--pick "$cur_page")
        fi
        ;;
    pick) cmd+=(--pick "$pick") ;;
esac

# ── 单个完整视频：下完用「视频标题」重命名 ──────────────────────
#
# vendor/bili_dl.py 按「分P标题」命名（1-<分P标题>.mp4），而单P视频的分P标题
# 常常是 UP 的原始文件名，例如 1-studio_video_1773562639855.mp4
# （BILIBILI-NOTES.md 第八节记了这个坑）。vendor/bili_season.py 已经在整合集
# 路径里做了扁平化改名，但 --this-only / 单个视频是直接走 bili_dl.py 的，绕过了它。
# 这里在 bash 侧补上，不动 vendor。
#
# 只在「本次下载就代表一个完整视频」时改名：
#   kind=single                          本来就只有 1 个分P
#   kind=season + 只下当前 + PAGES=1     合集里的单P视频
# 多分P视频的分P标题是有意义的区分标识，不能都改成同一个视频标题；
# kind=season + 全部 走的是 bili_season.py，它自己已经处理。
rename_single=false
if [ "$kind" = "single" ]; then
    rename_single=true
elif [ "$kind" = "season" ] && [ "$scope" = "this" ] && [ "$npages" = "1" ]; then
    rename_single=true
fi

# 合集成员单独下载时要带上它在合集里的序号，和 vendor/bili_season.py 的
# {序号}-{标题} 对齐，否则单独下的和整合集下的混在同一目录会排错序 ——
# 实测没有前缀时第 1 集会排到最后（BILIBILI-NOTES.md 第八节记了排序陷阱）。
# 序号来自 probe 的 SEASON_INDEX，取自 wbi/view 已返回的 episodes 列表，
# 不额外调接口；多 section 的合集 probe 不给序号，这里自然退化成无前缀。
# kind=single 不属于任何合集，确实没有序列，保持无前缀。
flat=""
if [ "$rename_single" = true ]; then
    _base="$(python3 "$BILI_TOOL" safename "$title")"
    if [ -n "$season_index" ]; then
        _tag=$(printf "%0${season_width:-1}d" "$season_index")
        flat="$outdir/${_tag}-${_base}.mp4"
    else
        flat="$outdir/${_base}.mp4"
    fi
fi

if [ "$dry_run" = true ]; then
    # 逐个 printf %q 转义：URL 里的 ? & 不转义的话，这行打印出来的命令
    # 复制去跑会被 shell 截断 —— -n 的意义就是给一条真能跑的命令
    _show=""
    for _a in "${cmd[@]}"; do _show="$_show $(printf '%q' "$_a")"; done
    echo "将执行:${_show}"
    [ -n "$flat" ] && echo "下完重命名为: $(printf '%q' "$flat")"
    exit 0
fi

# 预检必须在下载前：改名后 bili_dl.py 的「文件已存在就跳过」会失效
# （它找的是 1-<分P标题>.mp4），不预检的话重跑会整个重新下一遍。
# vendor/bili_season.py 也是这个顺序。
if [ -n "$flat" ] && [ -e "$flat" ]; then
    dog_log "已存在，跳过: $flat"
    exit 0
fi

# 用时间戳标记而不是前后快照对比：已存在被 bili_dl 跳过的文件 mtime 是旧的，
# 天然不会被误判成本次产物。find -newer 是 POSIX，不依赖 GNU 扩展。
marker=""
if [ -n "$flat" ]; then
    mkdir -p "$outdir"
    marker="$outdir/.dog_bili_marker.$$"
    : > "$marker"
fi

dog_log "执行: ${cmd[*]}"
echo
"${cmd[@]}"
rc=$?

if [ -n "$marker" ]; then
    if [ $rc -eq 0 ]; then
        produced=$(find "$outdir" -maxdepth 1 -type f -name '*.mp4' -newer "$marker" 2>/dev/null)
        count=$(printf '%s' "$produced" | grep -c . )
        if [ "$count" = "1" ] && [ "$produced" != "$flat" ]; then
            if [ -e "$flat" ]; then
                dog_error "目标名已存在，保留原名: $(basename "$produced")"
            else
                mv "$produced" "$flat" && dog_log "重命名: $(basename "$produced") -> $(basename "$flat")"
            fi
        fi
    fi
    rm -f "$marker"
fi

if [ $rc -eq 0 ]; then
    dog_success "完成 -> $(cd "$outdir" 2>/dev/null && pwd || echo "$outdir")"
else
    dog_error "下载失败（退出码 $rc）"
fi
exit $rc
