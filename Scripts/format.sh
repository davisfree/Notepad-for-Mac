#!/bin/bash
# 自动格式化（SwiftFormat）
set -euo pipefail

if ! command -v swiftformat >/dev/null 2>&1; then
    echo "ERROR: swiftformat 未安装，请执行 brew install swiftformat" >&2
    exit 1
fi

echo "==> SwiftFormat"
swiftformat --config .swiftformat .
