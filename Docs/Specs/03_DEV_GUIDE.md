# Notepad for macOS — 开发规范与编码标准 (DEV_GUIDE)

> **版本**：v1.1  
> **适用范围**：所有 Swift / Objective-C / C 代码  
> **强制执行**：SwiftLint + SwiftFormat + Code Review  
> **v1.1 修订**：编码检测接口对齐 04_MODULE_API.md（`detect(from:)`/`NPEncodingDetectionResult`/`NPEncodingError`，自研 BOM + 启发式替代 ICU）；模块分层修正为 08 §3 五层口径；大文件阈值改为 10MB 只读加载（PRD FR-001）；新增构建变体（`#if !APP_STORE`）、macOS 12 API 下限、本地化、通知、偏好观察规范

---

## 1. 代码风格

### 1.1 命名规范

#### Swift

| 类型           | 规范                                       | 示例                                     |
| -------------- | ------------------------------------------ | ---------------------------------------- |
| 类/结构体/枚举 | UpperCamelCase，前缀 `NP`                  | `NPTextDocument`, `NPEditorView`         |
| 协议           | UpperCamelCase，仅委托协议后缀 `Delegate`；能力型协议按名词/`-able`/`-ing` 命名 | `NPEditorDelegate`, `NPEncodingDetector` |
| 函数/方法      | lowerCamelCase，动词开头                   | `detect(from:)`, `saveToURL()`           |
| 变量/常量      | lowerCamelCase                             | `currentEncoding`, `isDirty`             |
| 布尔属性       | 以 `is`/`has`/`should` 开头                | `isAutoSaveEnabled`, `hasUnsavedChanges` |
| 私有属性       | 无前缀下划线，使用 `private` 修饰          | `private var backupTimer: Timer?`        |
| 全局常量       | lowerCamelCase 或 enum case                | `let defaultFontSize = 12`               |
| 回调闭包       | 以 `Handler`/`Completion` 结尾             | `saveCompletionHandler`                  |

#### 文件命名

- 类名与文件名一致：`NPTextDocument.swift`
- 扩展文件：Swift 扩展本身无类型名，`NSTextView+LineNumbers` 仅为文件名约定，形如 `原类型名+功能.swift`
- 测试文件：`NPTextDocumentTests.swift`

### 1.2 代码格式

```swift
// ✅ 正确：花括号不换行（K&R 风格）
final class NPTextDocument: NSDocument {
    var textContent: String = ""
    
    override func read(from data: Data, ofType typeName: String) throws {
        // 实现
    }
}

// ❌ 错误：花括号换行（Allman 风格）
class NPTextDocument: NSDocument
{
    // ...
}
```

- **缩进**：4 个空格（非 Tab）
- **行宽**：120 字符（Xcode Settings（Xcode 15 起更名，旧称 Preferences）→ Text Editing → Page guide at column 120）
- **空行**：函数之间 1 行空行，类/结构体之间 2 行空行
- **逗号后空格**：`func foo(a: Int, b: String)`
- **冒号前无空格，后有空格**：`let x: String`, `case .utf8:`, `[Key: Value]`
- **运算符两侧空格**：`a + b`，但 `a..<b` 和 `a...b` 无空格

### 1.3 注释规范

```swift
/// 检测数据编码格式
/// - Parameter data: 原始文件数据
/// - Returns: 检测到的编码及置信度
/// - Throws: `NPEncodingError.undetectable` 当无法识别时
func detect(from data: Data) throws -> NPEncodingDetectionResult {
    // 实现
}

// MARK: - 生命周期
// MARK: - 公开接口
// MARK: - 私有方法
// MARK: - 协议实现
```

- **文档注释**：使用 `///`（Swift DocC 格式），所有 `public`/`internal` 方法必须写
- **普通注释**：使用 `//`，解释"为什么"而非"做什么"
- **MARK**：按功能分区，`-` 用于生成分隔线
- **禁止**：`/* */` 多行注释、行尾注释（除非极短）

---

## 2. 架构规范

### 2.1 模块划分

> 完整目录结构以 `07_PROJECT_STRUCTURE.md` 为唯一权威，此处仅列一级模块及关键子目录。

```
Notepad/
├── App/                    # 应用入口与生命周期
│   ├── AppDelegate.swift
│   └── main.swift
├── Document/               # 文档模型（NSDocument）
│   ├── NPTextDocument.swift
│   ├── NPEncodingManager.swift
│   ├── NPLineEndingManager.swift
│   └── Types/              # 共享类型（NPEncodingDetectionResult、NPLineEnding、NPError 等）
├── Editor/                 # 编辑器视图
│   ├── NPEditorView.swift
│   ├── NPEditorController.swift
│   ├── NPEditorDelegate.swift
│   └── GoToLine/           # 转到行对话框
├── UI/                     # 界面组件
│   ├── TabBar/
│   ├── StatusBar/
│   ├── FindBar/
│   └── Theme/
├── Preferences/            # 偏好设置
│   ├── NPPreferences.swift
│   └── Views/              # 设置页视图
├── Services/               # 业务服务
│   ├── NPPrintService.swift
│   ├── NPUpdateService.swift
│   ├── NPBackupService.swift
│   └── Analytics/          # 埋点与崩溃报告
├── Utilities/              # 工具扩展
│   ├── Extensions/         # String+Encoding.swift、Data+EncodingDetection.swift 等
│   ├── Helpers/
│   └── Constants/          # NPConstants.swift、NPNotificationNames.swift
├── Resources/              # 资源文件
│   ├── Assets.xcassets
│   ├── Localizable.strings
│   ├── zh-Hans.lproj/      # 简体中文本地化
│   └── zh-Hant.lproj/      # 繁体中文本地化
└── Supporting Files/       # Info.plist、entitlements 等配置
```

### 2.2 依赖规则

```
第 1 层  App         —— 可依赖所有下层
第 2 层  Editor / UI —— 可依赖 Document、Utilities
第 3 层  Preferences / Services —— 可依赖 Document、Utilities
第 4 层  Document    —— 可依赖 Utilities
第 5 层  Utilities   —— 不依赖任何业务模块
```

- **上层可调用下层，下层不可调用上层**：例如 `NPEditorController`（Editor 层）持有 `weak var document: NPTextDocument?`（Document 层）属合法的上层依赖下层
- **同层模块之间不直接引用**，通过 Protocol/Notification/Delegate 通信
- **禁止循环依赖**：A → B → C → A 绝对禁止

### 2.3 协议优先于继承

- **无继承需求的类默认声明 `final`**（与 04_MODULE_API.md 的类定义一致），需要被继承时显式去除并说明理由

```swift
// ✅ 优先使用协议组合
protocol NPTextHandling {
    var textContent: String { get set }
    func insertText(_ text: String, at index: Int)
}

protocol NPEncodingAware {
    var currentEncoding: String.Encoding { get set }
}

final class NPTextDocument: NSDocument, NPTextHandling, NPEncodingAware {
    // 实现
}

// ❌ 避免过深的继承链
class NPBaseDocument: NSDocument { }
class NPTextDocument: NPBaseDocument { }  // 仅一层继承可接受
```

### 2.4 构建变体（App Store / 直发）

- Sparkle 自动更新（`NPUpdateService`）仅进入直发/Homebrew 构建，通过 `#if !APP_STORE` 条件编译剔除
- **禁止**在 App Store target 中 `import Sparkle`，相关调用必须整体包裹在 `#if !APP_STORE` 内

```swift
#if !APP_STORE
import Sparkle

final class NPUpdateService {
    // 仅直发/Homebrew 渠道编译
}
#endif
```

### 2.5 系统版本下限（macOS 12）

- 最低支持 macOS 12，**禁止**直接使用 macOS 13+ 独占 API
- 确需使用新 API 时必须 `if #available(macOS 13, *)` 兜底，并提供 macOS 12 下的降级实现

```swift
if #available(macOS 13, *) {
    // 使用新 API
} else {
    // macOS 12 降级实现
}
```

### 2.6 本地化规范

- 一律使用 `NSLocalizedString`，key 为稳定英文，采用 `Section.Name` 形式（如 `Document.Untitled`、`Menu.File.Save`）
- **禁止**使用中文做 key（key 不随文案修改而变化）
- 第一阶段语言：简体中文（zh-Hans）、繁体中文（zh-Hant）、英文

### 2.7 通知规范

- 通知名统一走 `NPNotificationNames` 常量（见 04_MODULE_API.md §6），**禁止**散落的 `Notification.Name("xxx")` 字面量
- 通知必须在主线程发出
- `userInfo` 中的枚举值以 `rawValue` 桥接传递

### 2.8 偏好观察

- 偏好设置使用 `UserDefaults` 持久化 + Combine `@Published` 发布变更
- **禁止**使用 KVO 观察偏好变化

---

## 3. 错误处理

### 3.1 使用 Result 或 throws，禁止裸 Optional

```swift
// ✅ 明确错误类型
enum NPEncodingError: Error {
    case undetectable
    case unsupported(String.Encoding)
    case conversionFailed
}

func readFile(at url: URL) -> Result<String, NPEncodingError> {
    // 实现
}

// ❌ 不明确错误
func readFile(at url: URL) -> String?  // 失败原因丢失
```

### 3.2 错误处理层级

| 层级            | 处理方式                 |
| --------------- | ------------------------ |
| 底层（Utility） | 抛出 Error，由调用方决定 |
| 中层（Service） | 转换为业务错误，记录日志 |
| 上层（UI）      | 捕获并展示用户友好提示   |

---

## 4. 并发规范

### 4.1 线程规则

```swift
// ✅ 明确标注线程要求
/// - Thread Safety: 必须在主线程调用
func updateUI() { }

/// - Thread Safety: 线程安全，可在任意线程调用
func detect(from data: Data) throws -> NPEncodingDetectionResult { }

// ✅ 后台任务使用结构化并发
Task {
    let result = await heavyComputation()
    await MainActor.run {
        updateUI(with: result)
    }
}

// ❌ 禁止裸 GCD（除非与旧 API 交互）
DispatchQueue.global().async {  // 避免
    // ...
    DispatchQueue.main.async {  // 避免
        // ...
    }
}
```

### 4.2 主线程检查

```swift
import os.log

func assertMainThread(file: String = #file, line: Int = #line) {
    if !Thread.isMainThread {
        os_log(.fault, "必须在主线程调用: %{public}@:%d", file, line)
        assertionFailure("必须在主线程调用")
    }
}
```

---

## 5. 内存管理

### 5.1 闭包捕获

```swift
// ✅ 明确捕获列表，避免循环引用
class NPTextDocument {
    private var saveTask: Task<Void, Never>?
    
    func autoSave() {
        saveTask = Task { [weak self] in
            guard let self = self else { return }
            await self.performSave()
        }
    }
}

// ❌ 隐式强引用可能导致循环引用
func autoSave() {
    saveTask = Task {
        await self.performSave()  // 危险
    }
}
```

### 5.2 代理模式

```swift
// ✅ 代理始终使用 weak
weak var delegate: NPEditorDelegate?

// ❌ 禁止强引用代理
var delegate: NPEditorDelegate?  // 可能导致循环引用
```

---

## 6. 测试规范

### 6.1 测试结构

```swift
import XCTest
@testable import Notepad

final class NPTextDocumentTests: XCTestCase {
    
    // MARK: - 生命周期
    
    // 测试类的 SUT 允许隐式解包（仅限 setUp/tearDown 场景），
    // 为 08_KIMI_INSTRUCTION.md §2.2 禁令的测试侧例外
    var sut: NPTextDocument!
    
    override func setUp() {
        super.setUp()
        sut = NPTextDocument()
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    // MARK: - 编码检测
    // 检测逻辑已从 NPTextDocument 剥离（04_MODULE_API.md §1.3），
    // 测试针对 NPEncodingManager 编写，init 注入 Mock NPEncodingDetector
    
    func test_detect_withUTF8BOM_shouldReturnUTF8() throws {
        // Given
        let manager = NPEncodingManager(detector: MockEncodingDetector())
        let data = Data([0xEF, 0xBB, 0xBF]) + "Hello".data(using: .utf8)!
        
        // When
        let result = try manager.detect(from: data)
        
        // Then
        XCTAssertEqual(result.encoding, .utf8)
        XCTAssertTrue(result.hasBOM)
    }
    
    func test_detect_withUndetectableData_shouldThrowUndetectable() {
        // Given
        let manager = NPEncodingManager(detector: MockEncodingDetector())
        let data = Data([0x00, 0x01])
        
        // Then
        XCTAssertThrowsError(try manager.detect(from: data)) { error in
            XCTAssertEqual(error as? NPEncodingError, .undetectable)
        }
    }
    
    // MARK: - 换行符识别
    // 针对 NPLineEndingManager.detect(in:) 静态纯函数编写
    
    func test_detect_withCRLF_shouldReturnCRLF() {
        // Given
        let text = "Line1\r\nLine2"
        
        // When
        let ending = NPLineEndingManager.detect(in: text)
        
        // Then
        XCTAssertEqual(ending, .crlf)
    }
}
```

### 6.2 测试命名

- `test_{被测方法}_{条件}_{预期结果}`
- 一个测试只验证一个概念
- 使用 Given-When-Then 注释结构

### 6.3 覆盖率要求

| 模块                 | 覆盖率目标            |
| -------------------- | --------------------- |
| Document（核心业务） | ≥ 90%                 |
| Encoding/LineEnding  | ≥ 95%                 |
| UI 层                | ≥ 60%（关键交互路径） |
| 整体                 | ≥ 80%                 |

---

## 7. Git 工作流

### 7.1 分支模型（Git Flow 简化版）

```
main        ─────●─────────●─────────●─────  (生产环境)
                  ↑         ↑         ↑
develop     ─────●────●────●────●────●─────  (集成测试)
                       ↑         ↑
feature/encoding       ●─────────●              (功能分支)
feature/find-bar                 ●─────────●
```

- `main`：仅接受来自 `develop` 和 `hotfix/*` 的合并，始终可发布
- `develop`：日常开发分支，功能集成
- `feature/*`：单个功能分支，从 `develop` 切出，完成后 PR 回 `develop`
- `hotfix/*`：紧急修复，从 `main` 切出，完成后同时合并到 `main` 和 `develop`

### 7.2 Commit 规范（Conventional Commits）

```
<type>(<scope>): <subject>

<body>

<footer>
```

| Type       | 含义                   |
| ---------- | ---------------------- |
| `feat`     | 新功能                 |
| `fix`      | 修复 Bug               |
| `docs`     | 文档更新               |
| `style`    | 代码格式（不影响功能） |
| `refactor` | 重构                   |
| `test`     | 测试相关               |
| `chore`    | 构建/工具/依赖更新     |

**示例**：
```
feat(encoding): 增加 GB18030 编码自动检测

- 实现 BOM + 启发式两阶段编码检测（GB18030 字符分布统计）
- 增加 GB18030 字符分布检测逻辑
- 添加对应单元测试

Closes #23
```

### 7.3 Pull Request 规范

- **标题**：与 Commit 规范一致
- **描述模板**：
  ```markdown
  ## 变更内容
  - 
  
  ## 关联 Issue
  Closes #
  
  ## 测试情况
  - [ ] 单元测试通过
  - [ ] 手动测试通过
  - [ ] UI 验收通过
  
  ## 截图（如适用）
  ```
- **Review 要求**：至少 1 人 Approve，CI 全部通过

---

## 8. 日志规范

### 8.1 使用 os.log 而非 print

```swift
import os.log

private let logger = Logger(subsystem: "com.yourcompany.notepad", category: "Document")

func save(to url: URL) {
    logger.info("开始保存文件: %{public}@", url.path)
    
    do {
        try performSave(to: url)
        logger.info("文件保存成功")
    } catch {
        logger.error("文件保存失败: %{public}@", error.localizedDescription)
    }
}
```

### 8.2 日志级别使用

| 级别    | 使用场景                                     |
| ------- | -------------------------------------------- |
| `debug` | 开发调试信息，生产环境不输出                 |
| `info`  | 关键流程节点（打开、保存、编码切换）         |
| `error` | 可恢复错误（保存失败、编码检测失败）         |
| `fault` | 严重错误，需要立即修复（数据损坏、断言失败） |

---

## 9. 安全规范

### 9.1 输入验证

```swift
// ✅ 所有外部输入都需验证
func openFile(at url: URL) throws {
    guard url.isFileURL else {
        throw NPError.invalidURL
    }
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw NPError.fileNotFound
    }
    // 检查文件大小，防止内存溢出；超过 10MB 时提示并进入只读模式（PRD FR-001）
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    if let size = attributes[.size] as? Int, size > 10 * 1024 * 1024 {
        throw NPError.fileTooLarge  // 调用方转为只读整体加载
    }
}
```

### 9.2 敏感信息

- 禁止在代码中硬编码 API Key、证书密码
- 使用 Xcode 配置文件或环境变量注入
- 崩溃日志中脱敏处理（去除文件路径、用户名）

---

## 10. 代码审查清单（Code Review Checklist）

审查者必须检查以下项目：

- [ ] 代码是否符合本规范的风格要求
- [ ] 是否存在循环引用风险
- [ ] 错误处理是否完善（无裸 `!`、无忽略的错误）
- [ ] 线程安全是否正确（UI 操作在主线程）
- [ ] 是否有适当的单元测试覆盖
- [ ] 是否有内存泄漏风险
- [ ] 字符串是否已本地化（`NSLocalizedString`）
- [ ] 新功能是否已更新文档注释
- [ ] 接口签名是否与 04_MODULE_API.md 一致（类型/方法名）
- [ ] 编码/通知/偏好常量是否走统一定义（`NPEncodingManager.supportedEncodings`、`NPNotificationNames`）

