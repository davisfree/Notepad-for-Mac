#!/bin/bash
# 开发环境初始化：检查依赖 → 生成 Xcode 工程
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> 检查开发环境"

# 1. 完整 Xcode（xcodebuild 需要，Command Line Tools 不够）
if ! xcodebuild -version >/dev/null 2>&1; then
    echo "ERROR: 未检测到完整 Xcode（当前仅为 Command Line Tools）。" >&2
    echo "       请从 App Store 安装 Xcode 15+，然后执行：" >&2
    echo "       sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
    exit 1
fi
xcodebuild -version | head -1

# 2. XcodeGen（用于从 project.yml 生成 .xcodeproj）
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "==> 未检测到 xcodegen，尝试通过 Homebrew 安装"
    if command -v brew >/dev/null 2>&1; then
        brew install xcodegen
    else
        echo "ERROR: 请先安装 Homebrew 或手动安装 xcodegen：" >&2
        echo "       https://github.com/yonsm/XcodeGen" >&2
        exit 1
    fi
fi

# 3. 可选工具
for tool in swiftlint swiftformat; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "WARN: $tool 未安装（可选），brew install $tool"
    fi
done

echo "==> 生成 Notepad.xcodeproj"
xcodegen generate

echo "==> 完成。打开工程："
echo "    open Notepad.xcodeproj"
