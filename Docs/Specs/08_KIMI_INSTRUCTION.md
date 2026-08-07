# Notepad for macOS — Kimi 开发助手指令 (KIMI_INSTRUCTION)

> **版本**：v1.0  
> **用途**：指导 Kimi / AI 编程助手在开发本项目时的行为准则、上下文引用规范与代码生成标准  
> **必读**：每次与 Kimi 交互开发任务前，先发送此文件或引用其中的规则

---

## 1. 项目上下文

### 1.1 项目基本信息

```yaml
项目名称: Notepad for macOS
定位: 1:1 复刻 Windows 11 原生 Notepad 的 macOS 纯文本编辑器
目标用户: 从 Windows 迁移至 macOS 的用户
技术栈: Swift 5.9+ / AppKit / NSDocument / NSTextView
架构模式: MVC + 协议组合
最低系统: macOS 12 Monterey (Universal Binary: arm64 + x86_64)
包体积目标: 核心 < 5MB；完整直发版（含 Sparkle + Sentry）< 15MB
启动速度目标: < 500ms (Apple Silicon)
```

### 1.2 核心约束（不可违背）

1. **必须使用原生 AppKit**，禁止使用 Electron / Tauri / SwiftUI
2. **必须兼容 macOS 12**，不能使用 macOS 13+ 独占 API
3. **必须生成 Universal Binary**（同时支持 Apple Silicon 和 Intel）
4. **所有 public API 必须写文档注释**（`///` DocC 格式）
5. **所有用户可见字符串必须本地化**（`NSLocalizedString`）
6. **UI 操作必须在主线程执行**（使用 `@MainActor` 或 `DispatchQueue.main`）

---

## 2. 代码生成规范

### 2.1 生成 Swift 代码时必须遵守

```
✅ 命名：类/结构体前缀 NP（如 NPTextDocument），枚举/协议不加前缀
✅ 缩进：4 个空格（非 Tab）
✅ 行宽：不超过 120 字符
✅ 花括号：K&R 风格（不换行）
✅ 访问控制：默认 internal，需要外部访问才用 public
✅ 错误处理：使用 throws / Result，禁止裸 Optional 解包
✅ 代理：必须声明为 weak
✅ 闭包捕获：必须显式写 [weak self]
✅ 线程：后台任务用 Task / async-await，禁止裸 GCD
✅ 注释：public/internal 方法必须写 /// 文档注释
✅ 分区：用 // MARK: - 按功能分区
```

### 2.2 禁止生成的代码模式

```swift
// ❌ 禁止：强制解包
let value = someOptional!

// ❌ 禁止：隐式解包可选类型
var text: String!

// ❌ 禁止：裸 GCD
DispatchQueue.global().async { }

// ❌ 禁止：强引用代理
var delegate: NPEditorDelegate?

// ❌ 禁止：魔法数字
if count > 10 { }  // 应定义为常量

// ❌ 禁止：过长的函数（> 60 行）
// ❌ 禁止：过深的嵌套（> 3 层）
// ❌ 禁止：直接持有其他模块实例（应通过 Protocol）
```

### 2.3 必须生成的代码模式

```swift
// ✅ 错误处理
enum NPError: Error {
    case invalidEncoding
}

func process() throws -> Result {
    guard condition else {
        throw NPError.invalidEncoding
    }
    return result
}

// ✅ 协议组合
protocol NPTextHandling {
    var text: String { get set }
}

class NPTextDocument: NSDocument, NPTextHandling {
    // 实现
}

// ✅ 弱引用代理
weak var delegate: NPEditorDelegate?

// ✅ 结构化并发
Task {
    let result = await heavyWork()
    await MainActor.run {
        updateUI(result)
    }
}

// ✅ 文档注释（接口签名以 04_MODULE_API.md 为准）
/// 检测数据编码格式
/// - Parameter data: 原始文件数据
/// - Returns: 检测结果
/// - Throws: NPEncodingError.undetectable
func detect(from data: Data) throws -> NPEncodingDetectionResult
```

---

## 3. 模块依赖规则

当 Kimi 生成跨模块代码时，必须遵守以下分层（与 `04_MODULE_API.md` 的实际依赖关系一致）：

```
第 1 层  App         —— 可依赖所有下层
第 2 层  Editor / UI —— 可依赖 Document、Utilities
第 3 层  Preferences / Services —— 可依赖 Document、Utilities
第 4 层  Document    —— 可依赖 Utilities
第 5 层  Utilities   —— 不依赖任何业务模块
```

**规则**：
- 上层模块可以 `import` 下层模块，下层模块**禁止** `import` 上层模块
- 同层模块之间**禁止**直接引用，必须通过 Protocol / Notification / Delegate 通信
- `Document/Types/` 中的共享类型（`NPLineEnding`、`NPError`、`NPEncodingDetectionResult` 等）属于 Document 层对外类型，Editor/UI 可直接引用
- 所有模块间通信接口定义在 `MODULE_API.md` 中

---

## 4. 与 PRD 的关联

当实现功能时，Kimi 必须对照 `PRD_Notepad_macOS.md` 中的需求：

| PRD 章节         | 对应实现文件                                                 |
| ---------------- | ------------------------------------------------------------ |
| 3.1 核心编辑功能 | `Editor/NPEditorView.swift`, `Editor/NPEditorController.swift` |
| 3.2 文件操作     | `Document/NPTextDocument.swift`                              |
| 3.3 界面与显示   | `UI/StatusBar/`, `UI/TabBar/`, `UI/FindBar/`                 |
| 3.4 打印功能     | `Services/NPPrintService.swift`                              |
| 3.5 系统集成     | `App/AppDelegate.swift`, `Services/NPShortcutService.swift`  |
| 4.1 菜单栏       | `App/AppDelegate.swift` (菜单配置)                           |
| 4.2 快捷键       | `App/AppDelegate.swift` (keyEquivalent)                      |

---

## 5. 与 UI_DESIGN 的关联

当生成 UI 相关代码时，Kimi 必须对照 `02_UI_DESIGN.md`：

### 5.1 颜色使用

**复刻区域以硬编码色值为唯一验收基准**（`02_UI_DESIGN.md` 的色值表），语义颜色仅用于非复刻区域：

```swift
// ✅ 复刻区域（编辑区、选中高亮、状态栏等）：硬编码，走 NPColorPalette
let bgColor = NSColor(hex: "#FFFFFF")      // 浅色模式编辑区
let darkBgColor = NSColor(hex: "#1E1E1E")  // 深色模式编辑区
let selectionColor = NSColor(hex: "#0078D4")  // 选中高亮（Win11 蓝；勿用系统语义色，其默认为灰色）

// ✅ 非复刻区域（分隔线、辅助文字等）：可用语义颜色
let separatorColor = NSColor.separatorColor
```

### 5.2 尺寸约束

```swift
// 状态栏高度必须严格 22pt
let statusBarHeight: CGFloat = 22.0

// 标签栏高度 32pt
let tabBarHeight: CGFloat = 26.0

// 编辑区内边距 8pt
let editorInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
```

### 5.3 字体使用

```swift
// 编辑区默认字体
let editorFont = NSFont(name: "SF Mono", size: 12) 
    ?? NSFont.userFixedPitchFont(ofSize: 12)

// 界面字体
let uiFont = NSFont.systemFont(ofSize: 13)
let statusBarFont = NSFont.systemFont(ofSize: 11)
```

---

## 6. 与 TEST_PLAN 的关联

当生成业务逻辑代码时，Kimi 应同时考虑可测试性：

```swift
// ✅ 依赖注入，便于测试
class NPEncodingManager {
    private let detector: NPEncodingDetector
    
    init(detector: NPEncodingDetector = .default) {
        self.detector = detector
    }
}

// ✅ 协议抽象，便于 Mock
protocol NPEncodingDetector {
    func detect(from data: Data) throws -> NPEncodingDetectionResult
}

// ✅ 纯函数，无副作用
func detectLineEnding(in text: String) -> NPLineEnding {
    // 仅依赖输入参数，不访问全局状态
}
```

---

## 7. 上下文引用规范

当 Kimi 回答开发相关问题时，应主动引用相关配置文件：

| 问题类型             | 应引用的文件                           |
| -------------------- | -------------------------------------- |
| "这个类该怎么设计？" | `04_MODULE_API.md` + `03_DEV_GUIDE.md` |
| "这个按钮颜色对吗？" | `02_UI_DESIGN.md`                      |
| "这个功能怎么测试？" | `05_TEST_PLAN.md`                      |
| "该放在哪个目录？"   | `07_PROJECT_STRUCTURE.md`              |
| "发布前还要做什么？" | `06_RELEASE.md`                        |
| "技术选型建议？"     | `01_TECH_SPEC.md`                      |

---

## 8. 常见任务指令模板

### 8.1 生成新模块

当要求 Kimi "实现 XX 模块" 时，按以下顺序：

1. 在 `07_PROJECT_STRUCTURE.md` 中确认所属目录
2. 在 `04_MODULE_API.md` 中定义对外接口
3. 生成实现代码（遵守 `03_DEV_GUIDE.md`）
4. 生成对应单元测试（遵守 `05_TEST_PLAN.md`）
5. 更新 `04_MODULE_API.md` 中的接口定义（如有变更）

### 8.2 修复 Bug

当要求 Kimi "修复 XX Bug" 时：

1. 先要求提供复现步骤和错误日志
2. 定位到具体文件和函数
3. 生成修复代码 + 回归测试用例
4. 检查是否引入新的循环引用或线程问题

### 8.3 重构代码

当要求 Kimi "重构 XX" 时：

1. 确保重构前后功能等效（通过测试验证）
2. 保持原有接口不变（或标记 `@available` 弃用）
3. 不破坏模块依赖规则
4. 更新相关文档注释

---

## 9. 质量检查清单

Kimi 生成代码后，应自我检查以下项目：

- [ ] 代码是否符合 `03_DEV_GUIDE.md` 的命名与格式规范？
- [ ] 是否所有 public/internal 方法都有 `///` 文档注释？
- [ ] 是否存在强制解包（`!`）或隐式解包可选类型？
- [ ] 代理是否声明为 `weak`？
- [ ] 闭包是否显式捕获 `[weak self]`？
- [ ] UI 操作是否在主线程？
- [ ] 错误处理是否完善（无忽略的错误）？
- [ ] 用户可见字符串是否使用 `NSLocalizedString`？
- [ ] 是否遵循模块依赖方向（无逆向依赖）？
- [ ] 是否生成了对应的单元测试？

---

## 10. 示例对话

### 示例 1：实现功能

**用户**：帮我实现编码自动检测模块

**Kimi 应**：
1. 引用 `01_TECH_SPEC.md` 3.2 的编码检测方案
2. 引用 `04_MODULE_API.md` 中 `NPEncodingManager` / `NPEncodingDetector` 的接口定义
3. 在 `Document/` 目录下生成 `NPEncodingManager.swift`
4. 生成 `NPEncodingManagerTests.swift` 测试用例
5. 确保代码符合 `03_DEV_GUIDE.md` 规范

### 示例 2：UI 调整

**用户**：状态栏的编码显示按钮点击后应该弹出编码选择菜单

**Kimi 应**：
1. 引用 `02_UI_DESIGN.md` 中状态栏的交互规范
2. 引用 `04_MODULE_API.md` 中 `NPStatusBarDelegate` 的接口
3. 生成 `NPStatusBarView` 的点击事件处理 + 菜单弹出逻辑
4. 确保菜单项与 `NPLineEnding` / `String.Encoding` 对应

### 示例 3：Bug 修复

**用户**：打开 GBK 文件时显示乱码

**Kimi 应**：
1. 询问复现文件或提供测试数据
2. 检查 `NPTextDocument.read(from:ofType:)` 的编码检测逻辑
3. 检查 `NPEncodingManager.detect(from:)` 的置信度阈值
4. 生成修复代码 + 对应测试用例 `UT-ENC-005`
5. 验证修复后是否影响其他编码检测

---

## 11. 文件索引

```
配置文档目录：/notepad_macos_config/
├── 01_TECH_SPEC.md         # 技术规格书
├── 02_UI_DESIGN.md         # UI 设计规范
├── 03_DEV_GUIDE.md         # 开发规范
├── 04_MODULE_API.md        # 模块接口
├── 05_TEST_PLAN.md         # 测试计划
├── 06_RELEASE.md           # 发布规范
├── 07_PROJECT_STRUCTURE.md # 目录结构
└── 08_KIMI_INSTRUCTION.md  # 本文件
```

> **提示**：在后续开发对话中，可直接引用文件编号（如"参考 04 号文件"）快速定位规范。