# Notepad for macOS — 模块接口与 API 文档 (MODULE_API)

> **版本**：v1.1  
> **说明**：本文档定义各模块对外暴露的接口契约，是模块间集成的唯一依据  
> **v1.1 修订**：修正 `NPLineEnding` rawValue 转义错误；查找大小写语义对齐 Win11 默认行为；补充标签拖拽、崩溃恢复、编码管理器、主题/快捷指令/崩溃报告等缺失契约；统一通知与线程约定；与 `07_PROJECT_STRUCTURE.md` 模块清单对齐

---

## 0. 总则

### 0.1 访问级别

本项目为单一 App Target，`public` 在本文档中表示"**模块对外可见的契约**"，实际代码中按 `08_KIMI_INSTRUCTION.md` 规范使用默认 `internal` 即可，无需真的声明 `public`。

### 0.2 线程约定

- 所有 UI 类型（`UI/`、`Editor/` 中的视图与窗口控制器）**必须在主线程访问**，声明为 `@MainActor`。
- 编码检测、查找匹配等 CPU 密集型操作**可在后台线程执行**（结构化并发 `Task` / `async-await`，禁止裸 GCD），结果通过 `await MainActor.run` 回主线程。
- 第 6 节所有通知**均在主线程发出**。

### 0.3 本地化约定

所有用户可见字符串使用 `NSLocalizedString`，**key 为稳定的英文标识**（形如 `"Section.Name"`），禁止以中文文案做 key：

```swift
// ✅ 正确
NSLocalizedString("Theme.Light", value: "Light", comment: "主题：浅色模式")
// ❌ 错误
NSLocalizedString("浅色模式", comment: "")
```

### 0.4 错误处理

- 可恢复错误使用 `throws`，错误类型集中在 `Document/Types/NPError.swift`。
- 禁止强制解包、禁止静默吞错。

---

## 1. Document 模块

### 1.1 NPEncodingManager 与检测器协议

> 对应 `07_PROJECT_STRUCTURE.md` 2.2：`Document/NPEncodingManager.swift`

```swift
import AppKit

/// 编码检测器抽象（协议隔离实现，便于 Mock 测试，见 05_TEST_PLAN）
public protocol NPEncodingDetector {
    /// 检测原始数据的编码
    /// - Parameter data: 原始文件数据
    /// - Returns: 检测结果（编码 + 置信度 + 是否有 BOM）
    /// - Throws: `NPEncodingError.undetectable`（置信度低于阈值时）
    func detect(from data: Data) throws -> NPEncodingDetectionResult
}

/// 系统默认编码检测器实现（BOM 检测 → 内容启发式分析，见 `01_TECH_SPEC.md` 3.2）
public struct NPDefaultEncodingDetector: NPEncodingDetector {
    public init()
    public func detect(from data: Data) throws -> NPEncodingDetectionResult
}

/// 编码管理器：检测、解码、编码的唯一入口
public final class NPEncodingManager {

    public static let shared = NPEncodingManager()

    private let detector: NPEncodingDetector

    /// 依赖注入，默认使用系统检测器实现
    public init(detector: NPEncodingDetector = NPDefaultEncodingDetector())

    /// 检测编码。CPU 密集，可在后台线程调用
    public func detect(from data: Data) throws -> NPEncodingDetectionResult

    /// 按指定编码解码为字符串
    /// - Throws: `NPEncodingError.conversionFailed`
    public func decode(_ data: Data, as encoding: String.Encoding) throws -> String

    /// 按指定编码序列化字符串
    /// - Parameters:
    ///   - text: 文本内容
    ///   - encoding: 目标编码
    ///   - includeBOM: 是否写入 BOM（仅 UTF-8/UTF-16/UTF-32 有效）
    /// - Throws: `NPEncodingError.conversionFailed`
    public func encode(_ text: String, as encoding: String.Encoding, includeBOM: Bool) throws -> Data

    /// 支持的编码清单（对齐 PRD FR-010）
    public static var supportedEncodings: [String.Encoding] { get }
}
```

### 1.2 NPLineEndingManager（纯函数，无状态）

> 对应 `07_PROJECT_STRUCTURE.md` 2.2：`Document/NPLineEndingManager.swift`  
> 遵循 `08_KIMI_INSTRUCTION.md` 第 6 节：纯函数、无副作用、仅依赖输入参数

```swift
import Foundation

/// 换行符检测与转换（静态纯函数）
public enum NPLineEndingManager {

    /// 检测文本中的换行符格式（以出现频次最高的为准，无换行时返回系统默认 LF）
    /// - Parameter text: 文本内容
    /// - Returns: 检测到的换行符格式
    public static func detect(in text: String) -> NPLineEnding

    /// 将文本中的换行符统一转换为目标格式
    public static func normalize(_ text: String, to lineEnding: NPLineEnding) -> String
}
```

### 1.3 NPTextDocument

```swift
import AppKit

/// 纯文本文档模型，封装编码、换行符、内容管理
public final class NPTextDocument: NSDocument {

    // MARK: - 属性

    /// 当前文本内容（主线程访问）
    public var textContent: String

    /// 当前文件编码
    public var currentEncoding: String.Encoding

    /// 当前换行符格式
    public var currentLineEnding: NPLineEnding

    /// 是否包含 UTF-8 BOM
    public var hasBOM: Bool

    /// 是否有未保存的更改（包装 `NSDocument.isDocumentEdited`，不单独维护状态）
    public var hasUnsavedChanges: Bool { get }

    /// 文件原始编码（打开时检测到的，用于保存时默认选择）
    public private(set) var originalEncoding: String.Encoding

    // MARK: - 初始化

    public override init()

    // MARK: - 编码 / 换行符切换
    // 检测逻辑委托给 NPEncodingManager / NPLineEndingManager，本类只维护文档状态

    /// 切换文档编码（会尝试转换内容）
    /// - Parameter encoding: 目标编码
    /// - Throws: `NPEncodingError.conversionFailed`
    public func changeEncoding(to encoding: String.Encoding) throws

    /// 切换换行符格式（转换内容中的换行符）
    /// - Parameter lineEnding: 目标换行符格式
    public func changeLineEnding(to lineEnding: NPLineEnding)

    // MARK: - NSDocument 重写

    public override func read(from data: Data, ofType typeName: String) throws
    public override func data(ofType typeName: String) throws -> Data
    public override func autosave(withImplicitCancellability implicitlyCancellable: Bool,
                                   completionHandler: @escaping (Error?) -> Void)
}

// MARK: - 关联类型

public struct NPEncodingDetectionResult {
    public let encoding: String.Encoding
    public let confidence: Double  // 0.0 - 1.0
    public let hasBOM: Bool
}

public enum NPLineEnding: String, CaseIterable {
    case lf = "\n"      // Unix / macOS
    case crlf = "\r\n"  // Windows
    case cr = "\r"      // Macintosh

    /// 状态栏显示名称（已本地化；文案对齐 Win11 原版）
    public var displayName: String {
        switch self {
        case .lf:
            return NSLocalizedString("StatusBar.LineEnding.LF", value: "Unix (LF)", comment: "换行符：LF")
        case .crlf:
            return NSLocalizedString("StatusBar.LineEnding.CRLF", value: "Windows (CRLF)", comment: "换行符：CRLF")
        case .cr:
            return NSLocalizedString("StatusBar.LineEnding.CR", value: "Macintosh (CR)", comment: "换行符：CR")
        }
    }
}

public enum NPEncodingError: Error {
    case undetectable
    case unsupported(String.Encoding)
    case conversionFailed
    case invalidBOM
}
```

---

## 2. Editor 模块

### 2.1 NPEditorView

```swift
import AppKit

/// 文本编辑器视图，封装 NSTextView 并提供扩展功能
@MainActor
public final class NPEditorView: NSView {

    // MARK: - 委托

    public weak var delegate: NPEditorDelegate?

    // MARK: - 属性

    /// 当前显示的文本
    public var text: String { get set }

    /// 当前选区范围
    public var selectedRange: NSRange { get set }

    /// 当前光标位置（行号，从 1 开始）
    public var currentLine: Int { get }

    /// 当前光标位置（列号，从 1 开始）
    public var currentColumn: Int { get }

    /// 是否启用自动换行
    public var isWordWrapEnabled: Bool { get set }

    /// 当前缩放比例（1.0 = 100%）。
    /// 合法范围 0.1 – 5.0（10%–500%，PRD FR-015），赋值越界时自动夹取
    public var zoomLevel: Double { get set }

    /// 当前字体
    public var font: NSFont { get set }

    // MARK: - 初始化

    public override init(frame: NSRect)
    public required init?(coder: NSCoder)

    // MARK: - 查找替换栏
    // 匹配计算由 NPFindController 执行，视图只负责展示与交互

    /// 显示查找栏
    public func showFindBar()

    /// 隐藏查找栏
    public func hideFindBar()

    /// 显示替换栏（展开查找栏）
    public func showReplaceBar()

    /// 高亮匹配结果（由 NPFindController 计算后回传）
    /// - Parameters:
    ///   - ranges: 全部匹配范围
    ///   - currentIndex: 当前匹配项索引（以不同颜色高亮）
    public func highlightMatches(_ ranges: [NSRange], currentIndex: Int)

    // MARK: - 导航

    /// 跳转到指定行
    /// - Parameter lineNumber: 行号（从 1 开始）
    public func goToLine(_ lineNumber: Int)

    /// 插入时间戳（PRD 菜单：编辑 → 时间/日期，F5）
    public func insertTimestamp()

    // MARK: - 选择

    /// 全选
    public func selectAllText()

    /// 选择指定范围
    public func selectRange(_ range: NSRange)
}

// MARK: - 委托协议（所有回调均在主线程触发）

public protocol NPEditorDelegate: AnyObject {
    func editorDidChangeContent(_ editor: NPEditorView)
    func editorDidChangeSelection(_ editor: NPEditorView)
    func editorDidChangeZoomLevel(_ editor: NPEditorView, zoomLevel: Double)
}

// MARK: - 查找选项

public struct NPFindOptions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int)

    /// 区分大小写。**默认不设置（不区分大小写）**，与 Win11 Notepad 行为一致（PRD FR-004）
    public static let caseSensitive = NPFindOptions(rawValue: 1 << 0)
    /// 到达文档末尾后从头继续
    public static let wrapAround = NPFindOptions(rawValue: 1 << 1)
    /// 正则表达式（增值功能，Win11 原版无）
    public static let regularExpression = NPFindOptions(rawValue: 1 << 2)
}
```

### 2.2 NPFindController / NPReplaceController

> 对应 `07_PROJECT_STRUCTURE.md` 2.3：`Editor/NPFindController.swift`、`Editor/NPReplaceController.swift`  
> 查找/替换的**计算逻辑**从视图剥离，便于后台执行与单元测试

```swift
import Foundation

/// 查找逻辑控制器（无 UI 依赖，可在后台线程执行）
public final class NPFindController {

    public init()

    /// 在文本中查找全部匹配
    /// - Parameters:
    ///   - text: 待搜索文本
    ///   - query: 搜索词
    ///   - options: 查找选项
    /// - Returns: 全部匹配范围（按出现顺序）
    /// - Throws: `NPFindError.invalidRegex`（正则表达式非法时）
    public func allMatches(in text: String, query: String, options: NPFindOptions) throws -> [NSRange]

    /// 从指定位置起查找下一个匹配（支持 `wrapAround`）
    public func nextMatch(in text: String, query: String, options: NPFindOptions,
                          after location: Int) throws -> NSRange?
}

/// 替换逻辑控制器（无 UI 依赖）
public final class NPReplaceController {

    public init()

    /// 替换单个匹配，返回新文本
    public func replacing(_ range: NSRange, in text: String, with replacement: String) -> String

    /// 替换全部匹配
    /// - Returns: 新文本与替换次数
    public func replacingAll(matches: [NSRange], in text: String,
                             with replacement: String) -> (text: String, count: Int)
}

public enum NPFindError: Error {
    case invalidRegex
    case emptyQuery
}
```

### 2.3 NPEditorController

> 对应 `07_PROJECT_STRUCTURE.md` 2.3：`Editor/NPEditorController.swift`  
> 视图与文档之间的协调者：订阅编辑器回调、驱动查找控制器、同步文档脏状态

```swift
import AppKit

/// 编辑器控制器：协调 NPEditorView 与 NPTextDocument
@MainActor
public final class NPEditorController: NPEditorDelegate {

    public let editorView: NPEditorView
    public weak var document: NPTextDocument?

    public init(editorView: NPEditorView, document: NPTextDocument)

    /// 执行查找（后台计算，完成后更新视图高亮）
    public func performFind(query: String, options: NPFindOptions) async

    /// 替换当前匹配项
    public func replaceCurrentMatch(with replacement: String)

    /// 替换全部匹配，返回替换次数
    @discardableResult
    public func replaceAll(with replacement: String) async -> Int
}
```

### 2.4 NPGoToLineController

> 对应 `07_PROJECT_STRUCTURE.md` 2.3：`Editor/GoToLine/`

```swift
import AppKit

/// "转到行"对话框控制器（PRD：编辑 → 转到… ⌃G；点击状态栏 Ln/Col 同样触发）
@MainActor
public final class NPGoToLineController {

    public init()

    /// 以非模态浮动面板（NSPanel）弹出"转到行"对话框。
    /// 对齐 Win11 原版交互：独立小对话框，不阻塞编辑区焦点切换；
    /// 面板随宿主窗口联动关闭，不使用模态 sheet（与 02_UI_DESIGN.md 一致）。
    /// - Parameters:
    ///   - window: 宿主窗口
    ///   - maxLine: 当前文档最大行号（用于输入校验）
    ///   - completion: 用户确认后回传目标行号；取消时回传 nil
    public func present(in window: NSWindow, maxLine: Int,
                        completion: @escaping (Int?) -> Void)
}
```

---

## 3. UI 模块

### 3.1 NPStatusBarView

```swift
import AppKit

/// 底部状态栏视图（高度固定 22pt，见 02_UI_DESIGN.md）
@MainActor
public final class NPStatusBarView: NSView {

    // MARK: - 委托

    public weak var delegate: NPStatusBarDelegate?

    // MARK: - 属性

    /// 当前行号
    public var lineNumber: Int { get set }

    /// 当前列号
    public var columnNumber: Int { get set }

    /// 当前缩放比例（1.0 = 100%）
    public var zoomLevel: Double { get set }

    /// 当前换行符格式
    public var lineEnding: NPLineEnding { get set }

    /// 当前编码
    public var encoding: String.Encoding { get set }

    // 可见性直接使用 NSView.isHidden，不单独引入状态（避免双状态失步）。
    // 开关动作（视图 → 状态栏 ⌘/）由窗口控制器读写 isHidden。

    // MARK: - 初始化

    public override init(frame: NSRect)
    public required init?(coder: NSCoder)
}

public protocol NPStatusBarDelegate: AnyObject {
    /// 点击 "Ln, Col"：弹出"转到行"
    func statusBarDidTapLineColumn(_ statusBar: NPStatusBarView)
    /// 点击缩放比例：弹出缩放选择菜单
    func statusBarDidTapZoomLevel(_ statusBar: NPStatusBarView)
    /// 点击换行符：弹出 CRLF / LF / CR 切换菜单
    func statusBarDidTapLineEnding(_ statusBar: NPStatusBarView)
    /// 点击编码：弹出编码切换菜单
    func statusBarDidTapEncoding(_ statusBar: NPStatusBarView)
}
```

### 3.2 NPTabBarView

```swift
import AppKit

/// 标签栏视图（高度固定 32pt，见 02_UI_DESIGN.md）
@MainActor
public final class NPTabBarView: NSView {

    // MARK: - 委托

    public weak var delegate: NPTabBarDelegate?

    // MARK: - 属性

    /// 当前标签列表
    public private(set) var tabs: [NPTabItem]

    /// 当前选中索引
    public var selectedIndex: Int { get set }

    // MARK: - 方法

    /// 添加标签
    public func addTab(_ tab: NPTabItem)

    /// 移除标签
    public func removeTab(at index: Int)

    /// 更新标签状态（未保存时标题前显示圆点 ●，PRD FR-002）
    public func updateTab(at index: Int, isModified: Bool)
}

public struct NPTabItem {
    public let identifier: UUID
    public let title: String
    public let fileURL: URL?
    public var isModified: Bool
}

public protocol NPTabBarDelegate: AnyObject {
    func tabBar(_ tabBar: NPTabBarView, didSelectTabAt index: Int)
    func tabBar(_ tabBar: NPTabBarView, didCloseTabAt index: Int)

    /// 拖拽排序完成（PRD FR-002）
    func tabBar(_ tabBar: NPTabBarView, didMoveTabFrom sourceIndex: Int, to destinationIndex: Int)

    /// 标签被拖出窗口区域：由窗口控制器将其迁移为新窗口（PRD FR-002）
    func tabBar(_ tabBar: NPTabBarView, didDragOutTabAt index: Int)

    /// 右键菜单（关闭 / 关闭其他 / 关闭右侧 / 复制标签 / 在 Finder 中显示）。
    /// 返回 nil 使用默认菜单；菜单动作由委托方以 target/action 方式处理
    func tabBar(_ tabBar: NPTabBarView, didRequestContextMenuForTabAt index: Int) -> NSMenu?
}
```

### 3.3 NPFindBarView

```swift
import AppKit

/// 查找/替换栏视图（悬浮于编辑区顶部，不遮挡内容，PRD FR-004）
@MainActor
public final class NPFindBarView: NSView {

    // MARK: - 委托

    public weak var delegate: NPFindBarDelegate?

    // MARK: - 属性

    /// 当前查找文本
    public var findText: String { get set }

    /// 当前替换文本
    public var replaceText: String { get set }

    /// 是否显示替换区域
    public var isReplaceMode: Bool { get set }

    /// 查找选项（"区分大小写"复选框状态映射到 NPFindOptions.caseSensitive）
    public var options: NPFindOptions { get set }

    /// 匹配结果统计（"3/17" 样式展示）
    public var matchResult: NPMatchResult? { get set }

    // MARK: - 方法

    /// 聚焦到查找输入框
    public func focusFindField()

    /// 选中查找输入框中的文本
    public func selectFindText()
}

public struct NPMatchResult {
    public let currentIndex: Int
    public let totalCount: Int
}

public protocol NPFindBarDelegate: AnyObject {
    func findBar(_ findBar: NPFindBarView, didChangeFindText text: String)
    func findBar(_ findBar: NPFindBarView, didChangeReplaceText text: String)
    func findBarDidRequestFindNext(_ findBar: NPFindBarView)
    func findBarDidRequestFindPrevious(_ findBar: NPFindBarView)
    func findBarDidRequestReplace(_ findBar: NPFindBarView)
    func findBarDidRequestReplaceAll(_ findBar: NPFindBarView)
    func findBarDidChangeOptions(_ findBar: NPFindBarView, options: NPFindOptions)
    func findBarDidRequestClose(_ findBar: NPFindBarView)
}
```

### 3.4 NPThemeManager

> 对应 `07_PROJECT_STRUCTURE.md` 2.4：`UI/Theme/NPThemeManager.swift`

```swift
import AppKit

/// 主题管理器：应用/切换浅色、深色、跟随系统（PRD FR-013）
@MainActor
public final class NPThemeManager {

    public static let shared = NPThemeManager()

    /// 当前生效的主题设置
    public private(set) var currentTheme: NPTheme

    /// 应用主题（写入偏好设置并发出 `NPThemeDidChange` 通知）
    public func apply(theme: NPTheme)

    /// 将主题解析为具体的 NSAppearance（跟随系统时读取系统外观）
    public func resolvedAppearance(for theme: NPTheme) -> NSAppearance?
}
```

---

## 4. Preferences 模块

### 4.1 NPPreferences

> 存储层：`UserDefaults`；观察层：Combine `@Published`（与 `01_TECH_SPEC.md` 8.2 口径一致）。

```swift
import AppKit
import Combine

/// 用户偏好设置（单例，@Published 属性支持订阅）
@MainActor
public final class NPPreferences: ObservableObject {

    // MARK: - 单例

    public static let shared = NPPreferences()

    // MARK: - 主题

    @Published public var theme: NPTheme
    @Published public var font: NSFont

    // MARK: - 编辑

    @Published public var isWordWrapEnabled: Bool
    @Published public var isAutoSaveEnabled: Bool
    @Published public var defaultEncoding: String.Encoding
    @Published public var defaultLineEnding: NPLineEnding

    // MARK: - 界面

    @Published public var isStatusBarVisible: Bool
    @Published public var defaultZoomLevel: Double

    // MARK: - 窗口状态（非 @Published）
    // 窗口 frame 变化高频，不做可观察属性；退出时写入 UserDefaults，启动时读取

    /// 上次主窗口 frame（持久化于 UserDefaults）
    public var lastWindowFrame: NSRect { get set }

    // MARK: - 方法

    /// 重置所有设置为默认值
    public func resetToDefaults()

    /// 导出设置为 JSON。
    /// NSFont 序列化为 `{"family": "SF Mono", "size": 12}`；编码序列化为 rawValue
    public func export() throws -> Data

    /// 从 JSON 导入设置
    /// - Throws: `NPPreferencesError.invalidFormat`
    public func `import`(from data: Data) throws
}

public enum NPTheme: String, CaseIterable, Identifiable {
    case light = "light"
    case dark = "dark"
    case system = "system"

    public var id: String { rawValue }

    /// 菜单显示名称（已本地化，key 为稳定英文标识）
    public var displayName: String {
        switch self {
        case .light:
            return NSLocalizedString("Theme.Light", value: "Light", comment: "主题：浅色模式")
        case .dark:
            return NSLocalizedString("Theme.Dark", value: "Dark", comment: "主题：深色模式")
        case .system:
            return NSLocalizedString("Theme.System", value: "System", comment: "主题：跟随系统")
        }
    }
}

public enum NPPreferencesError: Error {
    case invalidFormat
}
```

---

## 5. Services 模块

### 5.1 NPPrintService

```swift
import AppKit

/// 打印服务（PRD FR-018 / FR-019）
@MainActor
public final class NPPrintService {

    public static let shared = NPPrintService()

    /// 显示页面设置面板
    /// - Parameter completion: 用户确认后回传更新后的打印信息（已含纸张/方向/页边距）
    public func showPageSetup(for document: NPTextDocument,
                              in window: NSWindow?,
                              completion: @escaping (NSPrintInfo) -> Void)

    /// 执行打印
    /// - Parameter completion: true = 已送入打印队列；false = 用户取消
    public func printDocument(_ document: NPTextDocument,
                              in window: NSWindow?,
                              completion: @escaping (Bool) -> Void)
}
```

### 5.2 NPUpdateService

> **仅官网直发渠道有效**：App Store 构建必须通过编译条件 `#if !APP_STORE` 整体剔除本模块及 Sparkle 依赖（见 `01_TECH_SPEC.md` 6.3）

```swift
import Foundation

/// 自动更新服务（Sparkle 封装）
@MainActor
public final class NPUpdateService {

    public static let shared = NPUpdateService()

    /// 检查更新
    public func checkForUpdates()

    /// 自动检查开关
    public var isAutomaticCheckEnabled: Bool { get set }

    /// 上次检查时间
    public var lastCheckDate: Date? { get }
}
```

### 5.3 NPBackupService

```swift
import Foundation

/// 自动保存与崩溃恢复服务（PRD FR-003、5.3 节：崩溃时丢失不超过 1 秒的编辑内容）
public final class NPBackupService {

    public static let shared = NPBackupService()

    /// 注册文档进行自动保存监控
    public func registerDocument(_ document: NPTextDocument)

    /// 取消注册
    public func unregisterDocument(_ document: NPTextDocument)

    /// 恢复崩溃前的会话。
    /// 必须包含从未保存的"无标题"文档及其光标位置（PRD FR-003）。
    /// 只返回有效记录：文件对完整、元数据可解码且未超 7 天保留期
    /// - Returns: 可恢复的备份项列表
    public func recoverableItems() -> [NPBackupItem]

    /// 清理无效备份文件：删除目录中不属于 `validBackupIDs` 的一切文件
    /// （超期备份、原子写入临时残留、孤儿单边文件、元数据损坏的记录）。
    /// 启动时以 recoverableRecords() 的结果为白名单调用
    public func pruneInvalidBackupFiles(keeping validBackupIDs: Set<UUID>)
}

/// 崩溃恢复项：描述一份可恢复的备份
public struct NPBackupItem {
    /// 备份内容文件位置
    public let backupContentURL: URL
    /// 原始文件位置；nil 表示从未保存的无标题文档
    public let originalFileURL: URL?
    /// 光标位置（UTF-16 偏移量）
    public let cursorPosition: Int
    /// 文档编码
    public let encoding: String.Encoding
    /// 换行符格式
    public let lineEnding: NPLineEnding
}
```

### 5.4 NPShortcutService

> 对应 `07_PROJECT_STRUCTURE.md` 2.6：`Services/NPShortcutService.swift`（PRD FR-024）

```swift
import Foundation

/// 快捷指令（Shortcuts App）集成服务
public final class NPShortcutService {

    public static let shared = NPShortcutService()

    /// 注册 App Shortcuts：用 Notepad 打开文件、创建新文本文件
    public func registerShortcuts()
}
```

### 5.5 NPCrashReporter

> 对应 `07_PROJECT_STRUCTURE.md` 2.6：`Services/Analytics/NPCrashReporter.swift`  
> 隐私约束：崩溃日志匿名化后上传，**不含文件路径与内容片段**（`01_TECH_SPEC.md` 第 5 节）

```swift
import Foundation

/// 崩溃报告服务
public final class NPCrashReporter {

    public static let shared = NPCrashReporter()

    /// 启动崩溃监控（应用启动时调用一次，不阻塞主线程）
    public func start()
}
```

---

## 6. 模块间通信规范

### 6.1 通知名称与 userInfo 键

> 定义于 `Utilities/Constants/NPNotificationNames.swift`（`07_PROJECT_STRUCTURE.md` 2.7）。  
> **桥接规则**：`userInfo` 为 `[AnyHashable: Any]`，值一律以 rawValue 传递——
> `String.Encoding` → `NSNumber(rawValue: UInt)`；`NPLineEnding` / `NPTheme` → `String(rawValue)`；缩放 → `NSNumber(Double)`。

```swift
import Foundation

/// 通知名称与 userInfo 键常量
public enum NPNotificationNames {

    // MARK: - 通知名称

    /// 文档编码发生变化（发出者：NPTextDocument）
    public static let documentEncodingDidChange = Notification.Name("NPDocumentEncodingDidChange")

    /// 文档换行符发生变化（发出者：NPTextDocument）
    public static let documentLineEndingDidChange = Notification.Name("NPDocumentLineEndingDidChange")

    /// 主题发生变化（发出者：NPThemeManager）
    public static let themeDidChange = Notification.Name("NPThemeDidChange")

    /// 缩放比例发生变化（发出者：NPEditorView）
    public static let zoomLevelDidChange = Notification.Name("NPZoomLevelDidChange")

    /// 偏好设置发生变化（发出者：NPPreferences）
    public static let preferencesDidChange = Notification.Name("NPPreferencesDidChange")

    // MARK: - userInfo 键

    /// `NSNumber`，值为 `String.Encoding.rawValue`
    public static let encodingKey = "encoding"
    /// `String`，值为 `NPLineEnding.rawValue`
    public static let lineEndingKey = "lineEnding"
    /// `String`，值为 `NPTheme.rawValue`
    public static let themeKey = "theme"
    /// `NSNumber`，值为 `Double`（1.0 = 100%）
    public static let zoomLevelKey = "zoomLevel"
}
```

### 6.2 通知契约表

| 通知名称                       | 发出者           | 发出线程 | userInfo 键     | 值类型（桥接后）        |
| ------------------------------ | ---------------- | -------- | --------------- | ----------------------- |
| `documentEncodingDidChange`    | `NPTextDocument` | 主线程   | `encodingKey`   | `NSNumber`（UInt）      |
| `documentLineEndingDidChange`  | `NPTextDocument` | 主线程   | `lineEndingKey` | `String`（rawValue）    |
| `themeDidChange`               | `NPThemeManager` | 主线程   | `themeKey`      | `String`（rawValue）    |
| `zoomLevelDidChange`           | `NPEditorView`   | 主线程   | `zoomLevelKey`  | `NSNumber`（Double）    |
| `preferencesDidChange`         | `NPPreferences`  | 主线程   | 无              | —                       |

---

## 7. 版本兼容性

| 接口版本 | 对应 App 版本 | 变更说明                                                                                                 |
| -------- | ------------- | -------------------------------------------------------------------------------------------------------- |
| v1.0     | 1.0.0         | 初始版本                                                                                                 |
| v1.1     | 1.0.0         | 审阅修订：修正 `NPLineEnding` rawValue；`caseInsensitive` → `caseSensitive`；补齐标签拖拽/崩溃恢复/编码管理器等契约 |

> **向后兼容承诺**：所有对外接口在 v2.0 之前保持向后兼容。破坏性变更将通过 `@available` 标记弃用期。
