# Dog 工具

一个简单的命令行工具，用于演示 GitHub Actions 自动发布到 Homebrew 的流程。

## 安装

```bash
brew install griffinsin/dog/dog
```

## 使用方法

```bash
dog hello    # 运行 hello 命令
dog -h       # 显示帮助信息
dog -v       # 显示版本信息
```

## 开发

### 目录结构

- `bin/dog`: 主程序入口
- `bin/commands/`: 各个子命令的实现
- `lib/`: 共享库和工具函数
