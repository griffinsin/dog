#!/bin/bash
# 一键发布脚本 - 自动递增版本号并发布新版本

# 严格模式
set -e

# 获取当前目录（确保脚本在 dog 目录下运行）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 加载全局变量
source lib/globals.sh

# 显示当前版本
echo "当前版本: $DOG_VERSION"

# 自动递增版本号（增加最后一位）
MAJOR=$(echo $DOG_VERSION | cut -d. -f1)
MINOR=$(echo $DOG_VERSION | cut -d. -f2)
PATCH=$(echo $DOG_VERSION | cut -d. -f3)
NEW_PATCH=$((PATCH + 1))
NEW_VERSION="$MAJOR.$MINOR.$NEW_PATCH"

# 显示新版本号
echo "新版本: $NEW_VERSION"

# 更新 lib/globals.sh 中的版本号
sed -i '' "s/DOG_VERSION=\"$DOG_VERSION\"/DOG_VERSION=\"$NEW_VERSION\"/" lib/globals.sh

# 更新 bin/dog 中的版本号显示
sed -i '' "s/版本 $DOG_VERSION/版本 $NEW_VERSION/" bin/dog

echo "✅ 版本号已更新"

# 检查是否有未提交的更改
if [[ -n "$(git status --porcelain)" ]]; then
  echo "检测到未提交的更改，将全部提交..."
  # 提交所有本地更改
  git add .
  git commit -m "更新版本号到 $NEW_VERSION 并包含其他修改"
else
  # 如果只有版本号更改
  git add lib/globals.sh bin/dog
  git commit -m "更新版本号到 $NEW_VERSION"
fi

# 推送到远程仓库
echo "推送更改到远程仓库..."
git push origin main

# 创建并推送标签
echo "创建版本标签 v$NEW_VERSION..."
git tag -a "v$NEW_VERSION" -m "版本 $NEW_VERSION"
git push origin "v$NEW_VERSION"

echo "✅ 版本 $NEW_VERSION 发布流程已启动"
echo "GitHub Actions 将自动执行以下步骤:"
echo "  1. 创建发布包"
echo "  2. 计算 SHA256 校验和"
echo "  3. 创建 GitHub Release"
echo "  4. 更新 Homebrew Formula"
echo ""
echo "您可以在 GitHub 仓库的 Actions 页面查看进度"
echo "https://github.com/griffinsin/dog/actions"
