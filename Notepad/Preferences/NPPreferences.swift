//
//  NPPreferences.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit
import Combine

/// 主题设置（PRD FR-013）。
enum NPTheme: String, CaseIterable, Identifiable {
    case light = "light"
    case dark = "dark"
    case system = "system"

    var id: String { rawValue }

    /// 菜单显示名称（已本地化，key 为稳定英文标识）
    var displayName: String {
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

/// 偏好设置相关错误。
enum NPPreferencesError: Error {
    /// 导入数据格式非法（非 JSON、结构不符或字段类型错误）
    case invalidFormat
}

/// 用户偏好设置（单例，`@Published` 属性支持订阅）。
///
/// 存储层 `UserDefaults`（属性 `didSet` 即时持久化），观察层 Combine（`01_TECH_SPEC.md` 8.2）。
/// 默认值对齐 `PRD_Notepad_macOS.md` 7.1。任何变更发出 `NPPreferencesDidChange` 通知（04 §6.2）。
@MainActor
final class NPPreferences: ObservableObject {

    // MARK: - 单例

    static let shared = NPPreferences()

    // MARK: - 默认值

    /// 默认字体（SF Mono 12pt，PRD FR-014）
    private static let defaultFontSize: CGFloat = 12.0
    /// 默认窗口尺寸（`02_UI_DESIGN.md` 4.1）
    private static let defaultWindowFrame = NSRect(x: 0, y: 0, width: 800, height: 600)

    // MARK: - UserDefaults 键

    /// UserDefaults 存储键。
    private enum Key {
        static let theme = "theme"
        static let fontFamily = "fontFamily"
        static let fontSize = "fontSize"
        static let isWordWrapEnabled = "isWordWrapEnabled"
        static let isAutoSaveEnabled = "isAutoSaveEnabled"
        static let defaultEncoding = "defaultEncoding"
        static let defaultLineEnding = "defaultLineEnding"
        static let isStatusBarVisible = "isStatusBarVisible"
        static let defaultZoomLevel = "defaultZoomLevel"
        static let lastWindowFrame = "lastWindowFrame"
    }

    // MARK: - 存储

    /// 存储层（测试可注入独立 suite 的 UserDefaults）
    private let defaults: UserDefaults

    // MARK: - 主题

    /// 主题设置（默认跟随系统）
    @Published var theme: NPTheme {
        didSet { persist(theme.rawValue, forKey: Key.theme) }
    }

    /// 编辑区字体（默认 SF Mono 12pt）
    @Published var font: NSFont {
        didSet {
            persist(font.familyName ?? font.fontName, forKey: Key.fontFamily)
            persist(Double(font.pointSize), forKey: Key.fontSize)
        }
    }

    // MARK: - 编辑

    /// 自动换行（默认开启，PRD FR-016）
    @Published var isWordWrapEnabled: Bool {
        didSet { persist(isWordWrapEnabled, forKey: Key.isWordWrapEnabled) }
    }

    /// 自动保存（默认开启，PRD FR-003）
    @Published var isAutoSaveEnabled: Bool {
        didSet { persist(isAutoSaveEnabled, forKey: Key.isAutoSaveEnabled) }
    }

    /// 新建文档默认编码（默认 UTF-8）
    @Published var defaultEncoding: String.Encoding {
        didSet { persist(Int(defaultEncoding.rawValue), forKey: Key.defaultEncoding) }
    }

    /// 新建文档默认换行符（默认 LF）
    @Published var defaultLineEnding: NPLineEnding {
        didSet { persist(defaultLineEnding.rawValue, forKey: Key.defaultLineEnding) }
    }

    // MARK: - 界面

    /// 状态栏可见性（默认开启）
    @Published var isStatusBarVisible: Bool {
        didSet { persist(isStatusBarVisible, forKey: Key.isStatusBarVisible) }
    }

    /// 默认缩放比例（1.0 = 100%，合法范围 0.1–5.0）
    @Published var defaultZoomLevel: Double {
        didSet { persist(defaultZoomLevel, forKey: Key.defaultZoomLevel) }
    }

    // MARK: - 窗口状态（非 @Published）
    // 窗口 frame 变化高频，不做可观察属性；退出时写入 UserDefaults，启动时读取

    /// 上次主窗口 frame（持久化于 UserDefaults）
    var lastWindowFrame: NSRect {
        didSet { defaults.set(NSStringFromRect(lastWindowFrame), forKey: Key.lastWindowFrame) }
    }

    // MARK: - 初始化

    /// 以标准 UserDefaults 创建（单例入口）。
    convenience init() {
        self.init(defaults: .standard)
    }

    /// 以指定存储创建（测试注入独立 suite，避免污染 standard）。
    /// - Parameter defaults: 存储层
    init(defaults: UserDefaults) {
        self.defaults = defaults
        theme = NPTheme(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .system
        font = Self.loadFont(from: defaults)
        isWordWrapEnabled = (defaults.object(forKey: Key.isWordWrapEnabled) as? Bool) ?? true
        isAutoSaveEnabled = (defaults.object(forKey: Key.isAutoSaveEnabled) as? Bool) ?? true
        if let raw = (defaults.object(forKey: Key.defaultEncoding) as? NSNumber)?.uintValue {
            defaultEncoding = String.Encoding(rawValue: raw)
        } else {
            defaultEncoding = .utf8
        }
        defaultLineEnding = NPLineEnding(rawValue: defaults.string(forKey: Key.defaultLineEnding) ?? "") ?? .lf
        isStatusBarVisible = (defaults.object(forKey: Key.isStatusBarVisible) as? Bool) ?? true
        let storedZoom = (defaults.object(forKey: Key.defaultZoomLevel) as? Double) ?? 1.0
        defaultZoomLevel = min(max(storedZoom, 0.1), 5.0)
        if let frameString = defaults.string(forKey: Key.lastWindowFrame) {
            lastWindowFrame = NSRectFromString(frameString)
        } else {
            lastWindowFrame = Self.defaultWindowFrame
        }
    }

    // MARK: - 方法

    /// 重置所有设置为默认值。
    func resetToDefaults() {
        theme = .system
        font = Self.fallbackFont(family: "SF Mono", size: Self.defaultFontSize)
        isWordWrapEnabled = true
        isAutoSaveEnabled = true
        defaultEncoding = .utf8
        defaultLineEnding = .lf
        isStatusBarVisible = true
        defaultZoomLevel = 1.0
        lastWindowFrame = Self.defaultWindowFrame
    }

    /// 导出设置为 JSON。
    ///
    /// `NSFont` 序列化为 `{"family": "SF Mono", "size": 12}`；编码序列化为 rawValue；
    /// 缩放以百分比整数导出（对齐 PRD 7.1 的 `"zoomLevel": 100`）。
    /// - Returns: JSON 数据
    func export() throws -> Data {
        let dictionary: [String: Any] = [
            "theme": theme.rawValue,
            "font": [
                "family": font.familyName ?? font.fontName,
                "size": Double(font.pointSize),
            ],
            "autoWrap": isWordWrapEnabled,
            "statusBar": isStatusBarVisible,
            "autoSave": isAutoSaveEnabled,
            "defaultEncoding": Int(defaultEncoding.rawValue),
            "defaultLineEnding": defaultLineEnding.rawValue,
            "zoomLevel": defaultZoomLevel * 100.0,
        ]
        return try JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys])
    }

    /// 从 JSON 导入设置（仅应用存在的字段；字段类型错误或主题/换行符取值非法时抛错）。
    /// - Parameter data: JSON 数据
    /// - Throws: `NPPreferencesError.invalidFormat`
    func `import`(from data: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            throw NPPreferencesError.invalidFormat
        }
        if let rawTheme = dictionary["theme"] as? String {
            guard let parsed = NPTheme(rawValue: rawTheme) else {
                throw NPPreferencesError.invalidFormat
            }
            theme = parsed
        }
        if let fontDictionary = dictionary["font"] as? [String: Any] {
            font = try Self.parseFont(from: fontDictionary)
        }
        if let value = dictionary["autoWrap"] as? Bool {
            isWordWrapEnabled = value
        }
        if let value = dictionary["statusBar"] as? Bool {
            isStatusBarVisible = value
        }
        if let value = dictionary["autoSave"] as? Bool {
            isAutoSaveEnabled = value
        }
        if let value = dictionary["defaultEncoding"] as? NSNumber {
            defaultEncoding = String.Encoding(rawValue: value.uintValue)
        }
        if let rawLineEnding = dictionary["defaultLineEnding"] as? String {
            guard let parsed = NPLineEnding(rawValue: rawLineEnding) else {
                throw NPPreferencesError.invalidFormat
            }
            defaultLineEnding = parsed
        }
        if let value = dictionary["zoomLevel"] as? NSNumber {
            defaultZoomLevel = min(max(value.doubleValue / 100.0, 0.1), 5.0)
        }
    }

    // MARK: - 私有

    /// 持久化单个值并发出变更通知。
    /// - Parameters:
    ///   - value: 属性值
    ///   - key: 存储键
    private func persist(_ value: Any, forKey key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: NPNotificationNames.preferencesDidChange, object: self)
    }

    /// 从存储读取字体（缺失时使用默认字体）。
    /// - Parameter defaults: 存储层
    /// - Returns: 字体
    private static func loadFont(from defaults: UserDefaults) -> NSFont {
        let family = defaults.string(forKey: Key.fontFamily) ?? "SF Mono"
        let size = (defaults.object(forKey: Key.fontSize) as? Double) ?? Double(defaultFontSize)
        return fallbackFont(family: family, size: CGFloat(size))
    }

    /// 按名称与字号构造字体，失败时降级到系统等宽字体。
    /// - Parameters:
    ///   - family: 字体族名
    ///   - size: 字号
    /// - Returns: 字体
    private static func fallbackFont(family: String, size: CGFloat) -> NSFont {
        if let font = NSFont(name: family, size: size) {
            return font
        }
        return NSFont.userFixedPitchFont(ofSize: size) ?? NSFont.systemFont(ofSize: size)
    }

    /// 解析导出的字体字典。
    /// - Parameter dictionary: 字体字典（`{"family": ..., "size": ...}`）
    /// - Returns: 字体
    /// - Throws: `NPPreferencesError.invalidFormat`（缺少字段或字体不可用）
    private static func parseFont(from dictionary: [String: Any]) throws -> NSFont {
        guard let family = dictionary["family"] as? String,
              let size = (dictionary["size"] as? NSNumber)?.doubleValue,
              let font = NSFont(name: family, size: CGFloat(size)) else {
            throw NPPreferencesError.invalidFormat
        }
        return font
    }
}
