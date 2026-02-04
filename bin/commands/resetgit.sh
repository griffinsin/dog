#!/bin/bash

# Description: 重置 Git 仓库，删除历史记录并重新初始化

# 加载全局变量和函数
source $(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/lib/globals.sh

# resetgit 命令实现
dog_log "开始重置 Git 仓库..."

# 定义清理函数
cleanup() {
    # 检查临时目录变量是否存在且不为空
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        echo "清理临时目录: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
    exit $1
}

# 捕获信号，确保临时目录被清理
trap 'cleanup 1' INT TERM EXIT

# 重置Git仓库并只保留最新版本的文件
# 用法: dog resetgit [GitHub令牌] [远程URL(可选)]

# 检查参数
if [ $# -lt 1 ]; then
    echo "用法: dog resetgit [GitHub令牌] [远程URL(可选)]"
    echo "示例1: dog resetgit ghp_xxxxxxxxxxxx"
    echo "示例2: dog resetgit ghp_xxxxxxxxxxxx git@github.com:user/repo.git"
    echo "注意: "
    echo "  - GitHub令牌需要有repo权限"
    echo "  - 如果不提供第二个参数，将检查并使用当前目录"
    echo "  - 如果提供远程URL，将在当前目录下执行重置操作"
    echo ""
    echo "GitHub令牌创建步骤:"
    echo "  1. 登录GitHub账户"
    echo "  2. 点击右上角的头像，选择'Settings'(设置)"
    echo "  3. 在左侧菜单中，滚动到底部并点击'Developer settings'(开发者设置)"
    echo "  4. 在左侧菜单中，点击'Personal access tokens'(个人访问令牌)"
    echo "  5. 点击'Tokens (classic)'"
    echo "  6. 点击'Generate new token'按钮，然后选择'Generate new token (classic)'"
    echo "  7. 为令牌提供一个描述性名称，例如'Reset Git Repo Script'"
    echo "  8. 在权限选项中，选择'repo'(完全控制仓库)权限"
    echo "  9. 点击页面底部的'Generate token'(生成令牌)按钮"
    echo "  10. 复制生成的令牌(注意:此令牌只会显示一次，请务必立即复制保存)"
    echo ""
    echo "警告: 此脚本会删除并重新创建您指定的GitHub仓库，请确保您使用的是可以删除的测试仓库。"
    exit 1
fi

GITHUB_TOKEN="$1"
SECOND_ARG="$2"
COMMIT_MESSAGE="reset git"

# 设置当前目录为操作路径
REPO_PATH="$(pwd)"

# 处理参数
if [ -z "$SECOND_ARG" ]; then
    # 没有提供第二个参数，检查当前目录是否是Git仓库
    REMOTE_URL=""
    echo "将在当前目录下执行重置操作: $REPO_PATH"

    if [ ! -d ".git" ]; then
        echo "错误: 当前目录不是Git仓库"
        echo "请提供远程URL作为第二个参数或在Git仓库目录中运行此脚本"
        exit 1
    else
        echo "当前目录是Git仓库，将重置它"
    fi
elif [[ "$SECOND_ARG" == *"github.com"* || "$SECOND_ARG" == *"git@"* ]]; then
    # 第二个参数是远程URL
    REMOTE_URL="$SECOND_ARG"
    echo "使用远程URL: $REMOTE_URL"
    echo "将在当前目录下执行重置操作: $REPO_PATH"
else
    # 第二个参数不是远程URL，报错
    echo "错误: 第二个参数必须是远程URL"
    echo "用法: dog resetgit [GitHub令牌] [远程URL(可选)]"
    exit 1
fi

# 始终重置远程仓库
RESET_REMOTE="true"

# 检查当前目录是否存在
if [ ! -d "$REPO_PATH" ]; then
    echo "错误: 目录 '$REPO_PATH' 不存在"
    exit 1
fi

# 创建临时目录用于保存当前文件
TEMP_DIR=$(mktemp -d)
echo "创建临时目录: $TEMP_DIR"

# 检查临时目录是否创建成功
if [ -z "$TEMP_DIR" ] || [ ! -d "$TEMP_DIR" ]; then
    echo "错误: 无法创建临时目录"
    exit 1
fi

# 复制所有非.git文件到临时目录
echo "复制当前文件到临时目录..."
rsync -a --exclude='.git' "$REPO_PATH/" "$TEMP_DIR/"

# 备份原始仓库名称
REPO_NAME=$(basename "$REPO_PATH")
PARENT_DIR=$(dirname "$REPO_PATH")

# 删除原始仓库
echo "删除原始仓库..."
rm -rf "$REPO_PATH"

# 重新创建目录
mkdir -p "$REPO_PATH"

# 将文件从临时目录复制回来
echo "还原文件到新目录..."
rsync -a "$TEMP_DIR/" "$REPO_PATH/"

# 删除临时目录
echo "清理临时目录..."
rm -rf "$TEMP_DIR"

# 确认临时目录已被清理
if [ -d "$TEMP_DIR" ]; then
    echo "警告: 临时目录未能完全清理，再次尝试..."
    rm -rf "$TEMP_DIR"
fi

# 重置临时目录变量
TEMP_DIR=""

# 如果没有提供远程URL，尝试从原始仓库获取
if [ -z "$REMOTE_URL" ]; then
    echo "从原始仓库获取远程URL..."
    # 保存当前目录
    CURRENT_DIR=$(pwd)
    # 进入原始仓库目录查询远程URL
    cd "$REPO_PATH"
    if [ -d ".git" ]; then
        REMOTE_URL=$(git remote get-url origin 2>/dev/null)
        if [ -n "$REMOTE_URL" ]; then
            echo "从原始仓库获取到远程URL: $REMOTE_URL"
        else
            echo "原始仓库没有远程仓库配置"
        fi
    fi
    # 返回当前目录
    cd "$CURRENT_DIR"
fi

# 初始化新的Git仓库
echo "初始化新的Git仓库..."
cd "$REPO_PATH"
git init

# 添加所有文件并提交
echo "添加所有文件到新仓库..."
git add .
git commit -m "$COMMIT_MESSAGE"

# 如果有远程URL，则添加远程仓库
if [ -n "$REMOTE_URL" ]; then
    echo "添加远程仓库..."
    git remote add origin "$REMOTE_URL"

    # 检查是否需要重置GitHub远程仓库
    if [ "$RESET_REMOTE" = "true" ]; then
        echo "正在重置GitHub远程仓库..."

        # 从远程URL中提取用户名和仓库名
        if [[ "$REMOTE_URL" =~ github.com[:/]([^/]+)/([^/.]+)(\\.git)?$ ]]; then
            GITHUB_USER="${BASH_REMATCH[1]}"
            GITHUB_REPO="${BASH_REMATCH[2]}"

            # 判断URL类型（SSH或HTTPS）
            if [[ "$REMOTE_URL" =~ ^git@ ]]; then
                URL_TYPE="ssh"
            else
                URL_TYPE="https"
            fi

            echo "GitHub用户: $GITHUB_USER"
            echo "GitHub仓库: $GITHUB_REPO"
            echo "URL类型: $URL_TYPE"

            # 获取仓库信息以便稍后重新创建
            echo "获取仓库信息..."
            REPO_INFO=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                "https://api.github.com/repos/$GITHUB_USER/$GITHUB_REPO")

            # 提取仓库描述和可见性
            REPO_DESCRIPTION=$(echo "$REPO_INFO" | grep -o '"description":"[^"]*"' | cut -d '"' -f 4)
            REPO_PRIVATE=$(echo "$REPO_INFO" | grep -o '"private":[a-z]*' | cut -d ':' -f 2)

            echo "仓库描述: $REPO_DESCRIPTION"
            echo "仓库私有状态: $REPO_PRIVATE"

            # 删除远程仓库
            echo "删除远程仓库..."
            DELETE_RESULT=$(curl -s -X DELETE \
                -H "Authorization: token $GITHUB_TOKEN" \
                "https://api.github.com/repos/$GITHUB_USER/$GITHUB_REPO")

            # 等待仓库删除完成
            echo "等待仓库删除完成..."
            sleep 3

            # 初始化新的Git仓库
            echo "初始化新的Git仓库..."
            git init

            # 添加所有文件到新仓库
            echo "添加所有文件到新仓库..."
            git add .

            # 如果没有获取到私有状态，默认为公开仓库
            if [ -z "$REPO_PRIVATE" ]; then
                REPO_PRIVATE="false"
            fi

            # 构建正确的JSON请求体
            if [ -n "$REPO_DESCRIPTION" ]; then
                CREATE_PAYLOAD='{"name":"'"$GITHUB_REPO"'","private":'"$REPO_PRIVATE"',"description":"'"$REPO_DESCRIPTION"'"}'
            else
                CREATE_PAYLOAD='{"name":"'"$GITHUB_REPO"'","private":'"$REPO_PRIVATE"'}'
            fi

            echo "创建请求参数: $CREATE_PAYLOAD"

            echo "正在创建新仓库..."
            CREATE_RESULT=$(curl -s -X POST \
                -H "Authorization: token $GITHUB_TOKEN" \
                -H "Accept: application/vnd.github.v3+json" \
                -H "Content-Type: application/json" \
                "https://api.github.com/user/repos" \
                -d "$CREATE_PAYLOAD")

            # 将响应保存到文件以便调试
            echo "$CREATE_RESULT" > /tmp/github_response.json

            # 检查是否成功创建 - 使用仓库ID来判断
            # 注意：在JSON中，id字段的值前后可能有空格
            REPO_ID=$(echo "$CREATE_RESULT" | grep -o '"id":[^,}]*' | head -1 | cut -d ':' -f 2 | tr -d ' ')

            echo "DEBUG: 检测到的仓库ID: '$REPO_ID'"

            # 检查是否存在仓库ID
            if [ -n "$REPO_ID" ] && [ "$REPO_ID" != "null" ]; then
                # 从响应中提取仓库URL
                NEW_REPO_URL=$(echo "$CREATE_RESULT" | grep -o '"html_url":"[^"]*"' | head -1 | cut -d '"' -f 4)
                if [ -z "$NEW_REPO_URL" ]; then
                    # 根据原始的URL类型生成新的URL
                    if [ "$URL_TYPE" = "ssh" ]; then
                        NEW_REPO_URL="git@github.com:$GITHUB_USER/$GITHUB_REPO.git"
                    else
                        NEW_REPO_URL="https://github.com/$GITHUB_USER/$GITHUB_REPO"
                    fi
                fi
                echo "成功创建新仓库: $NEW_REPO_URL"

                # 更新远程URL（先使用HTTPS进行推送）
                git remote remove origin 2>/dev/null || true

                # 无论原始URL是什么格式，都先使用HTTPS URL进行推送
                # 这样可以使用GitHub令牌进行身份验证
                PUSH_URL="https://$GITHUB_TOKEN@github.com/$GITHUB_USER/$GITHUB_REPO.git"
                git remote add origin "$PUSH_URL"

                # 创建提交
                echo "创建初始提交..."
                # 确保有一个文件可以提交
                if [ ! -f README.md ]; then
                    echo "# 重置的Git仓库" > README.md
                    git add README.md
                fi
                # 设置用户信息以确保可以提交
                git config --local user.email "reset@example.com" || true
                git config --local user.name "Reset Script" || true
                git commit -m "reset git" || true

                # 推送到新仓库
                echo "推送到新仓库..."
                git push -u origin main || git push -u origin master

                # 推送完成后，如果原始URL是SSH格式，则将远程URL设置回原始SSH格式
                if [ "$URL_TYPE" = "ssh" ]; then
                    echo "将远程URL设置回SSH格式..."
                    git remote remove origin
                    git remote add origin "git@github.com:$GITHUB_USER/$GITHUB_REPO.git"
                fi

                echo "GitHub仓库已完全重置（删除并重新创建）!"
                echo "新仓库大小将与全新创建的仓库相同。"
            else
                # 检查是否有错误消息
                ERROR_MSG=$(echo "$CREATE_RESULT" | grep -o '"message":"[^"]*"' | cut -d '"' -f 4)
                if [ -n "$ERROR_MSG" ]; then
                    echo "创建新仓库失败: $ERROR_MSG"
                else
                    echo "创建新仓库失败，请检查GitHub令牌权限。"
                fi
                echo "响应详情:"
                echo "$CREATE_RESULT" | grep -o '"message":"[^"]*"' || echo "$CREATE_RESULT" | head -20
            fi
        else
            echo "无法从远程URL解析GitHub用户名和仓库名"
            echo "推送到远程仓库..."
            git push -f origin master || git push -f origin main
        fi
    else
        echo "推送到远程仓库..."
        git push -f origin master || git push -f origin main
        echo "注意: 远程仓库的历史记录未被重置，只是强制推送了新的内容"
        echo "如需完全重置远程仓库，请提供GitHub令牌并设置重置远程仓库参数为true"
    fi
fi

echo "完成! Git仓库已重置，只保留了最新版本的文件。"
echo "新仓库位置: $REPO_PATH"

# 成功完成，清除退出陷阱
trap - INT TERM EXIT

# 最后再次检查临时目录
cleanup 0

dog_success "Git 仓库重置完成"
