# Notepad for macOS — 项目目录结构规范 (PROJECT_STRUCTURE)

> **版本**：v1.0  
> **说明**：本文档定义 Xcode 项目的标准目录结构，所有代码、资源、配置必须按此规范存放

---

## 1. 顶层结构

```
Notepad/                          # 项目根目录
├── Notepad/                      # 主工程目录（与项目同名）
│   ├── App/                      # 应用入口与生命周期
│   ├── Document/                 # 文档模型层
│   ├── Editor/                   # 编辑器视图层
│   ├── UI/                       # 界面组件层
│   ├── Preferences/              # 偏好设置模块
│   ├── Services/                 # 业务服务层
│   ├── Utilities/                # 工具与扩展
│   ├── Resources/                # 资源文件
│   └── Supporting Files/         # 配置文件
├── NotepadTests/                 # 单元测试
├── NotepadUITests/               # UI 自动化测试
├── Notepad.xcodeproj/            # Xcode 工程文件
├── Notepad.xcworkspace/          # Xcode 工作区（如使用 CocoaPods/SPM）
├── Packages/                     # 本地 Swift Package（如需要）
├── Scripts/                      # 构建脚本
├── Docs/                         # 项目文档（开发文档，非用户文档）
├── .github/                      # GitHub 配置
├── .swiftlint.yml                # SwiftLint 配置
├── .swiftformat                  # SwiftFormat 配置
├── README.md                     # 项目说明
├── CHANGELOG.md                  # 更新日志
├── LICENSE                       # 开源协议（如适用）
└── Makefile                      # 常用命令快捷方式
```

---

## 2. 主工程目录详解

### 2.1 App/ — 应用入口

```
App/
├── AppDelegate.swift             # NSApplicationDelegate 实现
├── main.swift                    # 应用入口（@main）
└── Info.plist                    # 应用信息配置（或 Assets 中的 Info.plist）
```

**职责**：
- 应用生命周期管理（启动、退出、激活）
- 菜单栏动态更新（根据当前文档状态）
- 系统服务注册
- 崩溃监控初始化

### 2.2 Document/ — 文档模型

```
Document/
├── NPTextDocument.swift          # NSDocument 子类（核心）
├── NPEncodingManager.swift       # 编码管理器
├── NPLineEndingManager.swift     # 换行符管理器
├── NPTextStorage.swift           # 自定义 NSTextStorage（大文件优化）
└── Types/
    ├── NPEncodingTypes.swift     # 编码相关类型定义
    ├── NPLineEnding.swift        # 换行符枚举
    └── NPError.swift             # 业务错误定义
```

**职责**：
- 文件读写、编码转换
- 自动保存、版本管理
- 脏状态管理
- 大文件策略

### 2.3 Editor/ — 编辑器

```
Editor/
├── NPEditorView.swift            # 编辑器视图（NSTextView 封装）
├── NPEditorController.swift      # 编辑器控制器
├── NPEditorDelegate.swift        # 编辑器委托协议
├── NPTextView.swift              # 自定义 NSTextView 子类
├── NPFindController.swift        # 查找逻辑控制器
├── NPReplaceController.swift     # 替换逻辑控制器
└── GoToLine/
    ├── NPGoToLinePanel.swift     # 转到行对话框
    └── NPGoToLineController.swift
```

**职责**：
- 文本编辑交互
- 查找替换逻辑
- 光标位置计算
- 选区管理

### 2.4 UI/ — 界面组件

```
UI/
├── TabBar/
│   ├── NPTabBarView.swift        # 标签栏容器
│   ├── NPTabItemView.swift       # 单个标签视图
│   └── NPTabBarController.swift  # 标签栏控制器
├── StatusBar/
│   ├── NPStatusBarView.swift     # 状态栏视图
│   ├── NPStatusBarController.swift
│   └── NPStatusBarButton.swift   # 状态栏可点击信息块
├── FindBar/
│   ├── NPFindBarView.swift       # 查找栏视图
│   ├── NPReplaceBarView.swift    # 替换栏视图
│   └── NPFindOptionsView.swift   # 查找选项面板
├── Theme/
│   ├── NPThemeManager.swift      # 主题管理器
│   ├── NPColorPalette.swift      # 色彩定义
│   └── NPDynamicColor.swift      # 动态颜色（跟随系统）
└── Common/
    ├── NPButton.swift            # 通用按钮样式
    ├── NPTextField.swift         # 通用输入框样式
    └── NPSeparator.swift         # 分隔线视图
```

**职责**：
- 纯视图渲染，无业务逻辑
- 响应用户交互，通过委托/通知上报
- 主题与样式统一管控

### 2.5 Preferences/ — 偏好设置

```
Preferences/
├── NPPreferences.swift           # 偏好设置单例（ObservableObject）
├── NPPreferencesWindow.swift     # 偏好设置窗口
├── NPPreferencesController.swift # 偏好设置控制器
└── Views/
    ├── NPGeneralSettingsView.swift   # 常规设置页
    ├── NPEditorSettingsView.swift    # 编辑器设置页
    └── NPFontSettingsView.swift      # 字体设置页
```

**职责**：
- 用户设置持久化（UserDefaults）
- 设置界面
- 设置变更通知

### 2.6 Services/ — 业务服务

```
Services/
├── NPPrintService.swift          # 打印服务
├── NPUpdateService.swift         # 自动更新服务（Sparkle）
├── NPBackupService.swift         # 自动保存/崩溃恢复
├── NPShortcutService.swift       # 快捷指令支持
└── Analytics/
    ├── NPAnalytics.swift         # 埋点统计（可选）
    └── NPCrashReporter.swift     # 崩溃报告（Sentry）
```

**职责**：
- 与外部系统交互
- 跨模块共享功能
- 后台任务管理

### 2.7 Utilities/ — 工具扩展

```
Utilities/
├── Extensions/
│   ├── String+Encoding.swift     # 字符串编码扩展
│   ├── String+LineEnding.swift   # 字符串换行符扩展
│   ├── Data+EncodingDetection.swift  # 数据编码检测扩展
│   ├── NSFont+Defaults.swift     # 字体默认值
│   ├── NSColor+Hex.swift         # 颜色十六进制初始化
│   └── NSWindow+State.swift      # 窗口状态保存
├── Helpers/
│   ├── NPFileHelper.swift        # 文件操作辅助
│   ├── NPKeyboardHelper.swift    # 快捷键辅助
│   ├── NPAccessibilityHelper.swift   # 无障碍辅助
│   └── NPFeedbackComposer.swift  # 反馈邮件链接构造（06 §7.2）
└── Constants/
    ├── NPConstants.swift         # 全局常量
    └── NPNotificationNames.swift # 通知名称定义
```

**职责**：
- 纯工具函数，无状态
- 扩展系统类型
- 常量集中管理

### 2.8 Resources/ — 资源文件

```
Resources/
├── Assets.xcassets/              # 图片、颜色、App Icon
│   ├── AppIcon.appiconset/       # App Icon（所有尺寸）
│   ├── Colors/                   # 自定义颜色集
│   └── Images/                   # 图片资源
├── en.lproj/                     # 英文本地化
│   ├── Localizable.strings
│   └── Preferences.strings
├── Localizable.stringsdict       # 复数规则本地化
├── zh-Hans.lproj/                # 简体中文本地化
│   ├── Localizable.strings
│   └── Preferences.strings
├── zh-Hant.lproj/                # 繁体中文本地化
│   ├── Localizable.strings
│   └── Preferences.strings
└── Credits.rtf                   # 关于窗口的 Credits
```

> 注：英文资源必须放在 `en.lproj/` 内——bundle 根级的 `Localizable.strings` 不会被系统加载（v1.1 修正）。

### 2.9 Supporting Files/ — 配置

```
Supporting Files/
├── Info.plist                    # 应用配置
├── Notepad.entitlements          # 沙盒与权限配置
├── Notepad-Bridging-Header.h     # Objective-C 桥接头（如需要）
└── Notepad-Prefix.pch            # 预编译头（如需要）
```

---

## 3. 测试目录结构

### 3.1 单元测试（NotepadTests/）

```
NotepadTests/
├── DocumentTests/
│   ├── NPTextDocumentTests.swift
│   ├── NPEncodingManagerTests.swift
│   └── NPLineEndingManagerTests.swift
├── EditorTests/
│   ├── NPEditorViewTests.swift
│   └── NPFindControllerTests.swift
├── PreferencesTests/
│   └── NPPreferencesTests.swift
└── UtilityTests/
    ├── StringEncodingTests.swift
    └── DataDetectionTests.swift
```

### 3.2 UI 测试（NotepadUITests/）

```
NotepadUITests/
├── Flows/
│   ├── NewEditSaveFlow.swift
│   ├── OpenFileFlow.swift
│   └── FindReplaceFlow.swift
├── Pages/
│   ├── EditorPage.swift          # Page Object 模式
│   ├── FindBarPage.swift
│   └── StatusBarPage.swift
└── AccessibilityTests/
    └── VoiceOverTests.swift
```

---

## 4. 脚本目录（Scripts/）

```
Scripts/
├── build.sh                      # 构建脚本
├── test.sh                       # 测试脚本
├── lint.sh                       # 代码检查脚本
├── format.sh                     # 自动格式化脚本
├── release.sh                    # 发布打包脚本
└── setup.sh                      # 开发环境初始化脚本
```

---

## 5. 文档目录（Docs/）

```
Docs/
├── ARCHITECTURE.md               # 架构设计文档
├── API/                          # 内部 API 文档（DocC 生成）
├── DESIGN/                       # UI 设计稿与标注
└── USER_GUIDE.md                 # 用户手册（可选）
```

---

## 6. GitHub 配置（.github/）

```
.github/
├── workflows/
│   ├── ci.yml                    # CI 工作流（构建 + 测试）
│   ├── lint.yml                  # 代码规范检查
│   └── release.yml               # 自动发布工作流
├── ISSUE_TEMPLATE/
│   ├── bug_report.md             # Bug 报告模板
│   └── feature_request.md        # 功能请求模板
├── PULL_REQUEST_TEMPLATE.md      # PR 模板
└── CODEOWNERS                    # 代码审查责任人
```

---

## 7. 配置文件说明

### 7.1 .swiftlint.yml

```yaml
disabled_rules:
  - trailing_whitespace
  - todo

opt_in_rules:
  - empty_count
  - explicit_init
  - first_where
  - force_unwrapping
  - redundant_nil_coalescing

line_length:
  warning: 120
  error: 150

function_body_length:
  warning: 60
  error: 100

type_body_length:
  warning: 300
  error: 500

file_length:
  warning: 500
  error: 800

excluded:
  - NotepadTests/
  - NotepadUITests/
  - Packages/
```

### 7.2 .swiftformat

```
--indent 4
--maxwidth 120
--wraparguments before-first
--wrapparameters before-first
--wrapcollections before-first
--self remove
--importgrouping testable-bottom
--decimalgrouping 3,4
--binarygrouping 4,8
--hexgrouping 4,8
--octalgrouping 4,8
--fractiongrouping disabled
--exponentgrouping disabled
--patternlet hoist
--redundanttype infer
--trimwhitespace always
--insertlines preserve
--removelines preserve
```

### 7.3 Makefile

```makefile
.PHONY: build test lint format clean release

build:
	xcodebuild -scheme Notepad -configuration Debug

test:
	xcodebuild test -scheme Notepad -destination 'platform=macOS'

lint:
	swiftlint lint

format:
	swiftformat --config .swiftformat .

clean:
	xcodebuild clean -scheme Notepad
	rm -rf build/

release:
	./Scripts/release.sh
```

---

## 8. 文件创建规范

### 8.1 新建文件流程

1. 根据功能判断所属模块（Document/Editor/UI/...）
2. 在对应目录下创建 `.swift` 文件
3. 文件名与主类型名一致（`NPTextDocument.swift`）
4. 文件顶部添加模块归属注释：
   ```swift
   //
   //  NPTextDocument.swift
   //  Notepad
   //
   //  Created by [Name] on [Date].
   //  Copyright © 2026 [Company]. All rights reserved.
   //
   ```
5. 在对应测试目录下创建测试文件
6. 更新本目录的 README（如有）

### 8.2 禁止事项

- ❌ 禁止在根目录直接创建 `.swift` 文件
- ❌ 禁止跨模块直接 `import` 内部类型（通过 Protocol 通信）
- ❌ 禁止在 Resources 中存放非必要的大文件（> 1MB）
- ❌ 禁止将密钥、证书等敏感文件提交到 Git
- ❌ 禁止在代码中硬编码绝对路径

---

## 9. 目录权限与归属

| 目录         | 负责人      | 修改权限  |
| ------------ | ----------- | --------- |
| App/         | 架构师      | 需 Review |
| Document/    | 核心开发    | 需 Review |
| Editor/      | 核心开发    | 需 Review |
| UI/          | 前端开发    | 自由修改  |
| Preferences/ | 前端开发    | 自由修改  |
| Services/    | 核心开发    | 需 Review |
| Utilities/   | 全员        | 自由修改  |
| Resources/   | 设计师/前端 | 需 Review |
| Tests/       | QA / 开发   | 自由修改  |
|              |             |           |

