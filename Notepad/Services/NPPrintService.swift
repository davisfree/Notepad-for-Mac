//
//  NPPrintService.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// 打印页眉页脚文案格式化（纯函数，无 UI 依赖）。
enum NPPrintFormatter {

    /// 页脚文案（"第 1 页 共 3 页"，对齐 Win11 Notepad 页脚格式，本地化 key `Print.PageXOfY`）。
    /// - Parameters:
    ///   - page: 当前页码（从 1 开始）
    ///   - totalPages: 总页数
    /// - Returns: 页脚文案
    static func footerText(page: Int, totalPages: Int) -> String {
        String(format: NSLocalizedString("Print.PageXOfY", comment: "打印：页脚页码"), page, totalPages)
    }
}

/// 打印分页计算（纯逻辑，可无 UI 测试）。
enum NPPrintPaginator {

    /// 内容区尺寸（纸张 - 页边距 - 页眉页脚高度）。
    /// - Parameters:
    ///   - printInfo: 打印信息
    ///   - headerHeight: 页眉高度
    ///   - footerHeight: 页脚高度
    /// - Returns: 内容区尺寸
    static func contentSize(for printInfo: NSPrintInfo,
                            headerHeight: CGFloat,
                            footerHeight: CGFloat) -> NSSize {
        NSSize(
            width: printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin,
            height: printInfo.paperSize.height - printInfo.topMargin - printInfo.bottomMargin
                - headerHeight - footerHeight
        )
    }

    /// 按内容区尺寸为文本分页（每页一个 textContainer）。
    /// - Parameters:
    ///   - text: 打印文本
    ///   - font: 打印字体
    ///   - contentSize: 内容区尺寸
    /// - Returns: 文本存储（调用方须持有，layoutManager 不持有 storage）、布局管理器与页数（至少 1 页）
    static func makeLayoutManager(text: String, font: NSFont,
                                  contentSize: NSSize) -> (textStorage: NSTextStorage,
                                                           layoutManager: NSLayoutManager,
                                                           pageCount: Int) {
        let textStorage = NSTextStorage(string: text, attributes: [
            .font: font,
            // 打印一律黑字白底（不跟随编辑器主题色）
            .foregroundColor: NSColor.black
        ])
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        var pageCount = 0
        while true {
            let container = NSTextContainer(size: contentSize)
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            pageCount += 1
            layoutManager.ensureLayout(for: container)
            let laidGlyphs = NSMaxRange(layoutManager.glyphRange(for: container))
            if laidGlyphs >= layoutManager.numberOfGlyphs {
                break
            }
        }
        return (textStorage, layoutManager, pageCount)
    }
}

/// 打印渲染视图（带页眉页脚的分页文本）。
///
/// 页眉为文件名居中、页脚为"第 X 页 共 Y 页"居中（Win11 Notepad 默认格式，PRD FR-019）。
/// 尺寸为 `纸张 × 页数`，经 `knowsPageRange` / `rectForPage` 向 `NSPrintOperation` 报告分页。
@MainActor
final class NPPrintTextView: NSView {

    // MARK: - 常量

    /// 页眉高度
    static let headerHeight: CGFloat = 24.0
    /// 页脚高度
    static let footerHeight: CGFloat = 24.0
    /// 页眉页脚字号
    private static let headerFooterFontSize: CGFloat = 10.0

    // MARK: - 属性

    /// 页眉标题（文件名）
    private let headerTitle: String
    /// 打印信息（纸张/方向/页边距）
    private let printInfo: NSPrintInfo
    /// 布局管理器（每页一个 textContainer）
    private let layoutManager: NSLayoutManager
    /// 文本存储（必须持有：layoutManager 不持有 storage，释放后布局失效）
    private let textStorage: NSTextStorage
    /// 总页数
    let pageCount: Int

    // MARK: - 初始化

    /// 创建打印渲染视图并完成分页。
    /// - Parameters:
    ///   - text: 打印文本
    ///   - font: 打印字体（文档字体，PRD FR-014）
    ///   - title: 页眉标题（文件名）
    ///   - printInfo: 打印信息
    init(text: String, font: NSFont, title: String, printInfo: NSPrintInfo) {
        self.headerTitle = title
        self.printInfo = printInfo
        let contentSize = NPPrintPaginator.contentSize(for: printInfo,
                                                       headerHeight: Self.headerHeight,
                                                       footerHeight: Self.footerHeight)
        let paginated = NPPrintPaginator.makeLayoutManager(text: text,
                                                           font: font,
                                                           contentSize: contentSize)
        self.layoutManager = paginated.layoutManager
        self.textStorage = paginated.textStorage
        self.pageCount = paginated.pageCount
        super.init(frame: NSRect(x: 0, y: 0,
                                 width: printInfo.paperSize.width,
                                 height: printInfo.paperSize.height * CGFloat(pageCount)))
    }

    /// 不支持归档恢复。
    /// - Parameter coder: 解码器
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NPPrintTextView 不支持 coder 初始化")
    }

    // MARK: - 分页

    /// 向打印系统报告页数范围。
    /// - Parameter range: 输出页数范围（1-based）
    /// - Returns: 是否支持自定义分页
    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: pageCount)
        return true
    }

    /// 返回指定页在视图中的区域（第 1 页在顶部）。
    /// - Parameter page: 页码（从 1 开始）
    /// - Returns: 页面区域
    override func rectForPage(_ page: Int) -> NSRect {
        NSRect(x: 0,
               y: CGFloat(pageCount - page) * printInfo.paperSize.height,
               width: printInfo.paperSize.width,
               height: printInfo.paperSize.height)
    }

    // MARK: - 绘制

    /// 绘制当前打印页：页眉（文件名居中）、文本内容、页脚（页码居中）。
    /// - Parameter dirtyRect: 待绘制区域
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        dirtyRect.fill()
        guard let operation = NSPrintOperation.current,
              operation.currentPage >= 1, operation.currentPage <= pageCount else {
            return
        }
        let page = operation.currentPage
        let pageOrigin = rectForPage(page).origin
        let captionAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: Self.headerFooterFontSize),
            .foregroundColor: NSColor.black
        ]

        // 页眉：文件名居中（Win11 默认页眉）
        let headerRect = NSRect(x: printInfo.leftMargin,
                                y: pageOrigin.y + printInfo.paperSize.height - printInfo.topMargin - Self.headerHeight,
                                width: printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin,
                                height: Self.headerHeight)
        headerTitle.draw(in: headerRect, withAttributes: centeredAttributes(captionAttributes))

        // 文本内容
        let contentOrigin = NSPoint(x: printInfo.leftMargin,
                                    y: pageOrigin.y + printInfo.bottomMargin + Self.footerHeight)
        let container = layoutManager.textContainers[page - 1]
        layoutManager.drawGlyphs(forGlyphRange: layoutManager.glyphRange(for: container), at: contentOrigin)

        // 页脚："第 X 页 共 Y 页"居中（Win11 默认页脚）
        let footerRect = NSRect(x: printInfo.leftMargin,
                                y: pageOrigin.y + printInfo.bottomMargin,
                                width: headerRect.width,
                                height: Self.footerHeight)
        NPPrintFormatter.footerText(page: page, totalPages: pageCount)
            .draw(in: footerRect, withAttributes: centeredAttributes(captionAttributes))
    }

    /// 居中段落属性。
    /// - Parameter attributes: 基础属性
    /// - Returns: 附加居中段落的属性
    private func centeredAttributes(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        var merged = attributes
        merged[.paragraphStyle] = paragraph
        return merged
    }
}

/// 打印服务（PRD FR-018 / FR-019）。
///
/// 页面设置与打印信息按文档保留（`NSPrintInfo` 含纸张/方向/页边距）；
/// 打印渲染为带页眉页脚的离屏分页视图，打印面板（预览/份数/页面范围）由系统提供。
@MainActor
final class NPPrintService {

    // MARK: - 单例

    static let shared = NPPrintService()

    // MARK: - 属性

    /// 每文档打印信息（页面设置结果保留）
    private var printInfos: [ObjectIdentifier: NSPrintInfo] = [:]

    /// 打印完成回调（sheet 流程单实例即可）
    private var printCompletion: ((Bool) -> Void)?

    // MARK: - 初始化

    private init() {}

    // MARK: - 页面设置

    /// 显示页面设置面板（`NSPageLayout`，纸张/方向/页边距，PRD FR-018）。
    /// - Parameters:
    ///   - document: 目标文档
    ///   - window: 宿主窗口（sheet 挂载；nil 时应用级模态）
    ///   - completion: 用户确认后回传更新后的打印信息；取消时回传原打印信息
    func showPageSetup(for document: NPTextDocument,
                       in window: NSWindow?,
                       completion: @escaping (NSPrintInfo) -> Void) {
        let printInfo = self.printInfo(for: document)
        let pageLayout = NSPageLayout()
        guard let window else {
            // 无宿主窗口：应用级模态
            runPageLayoutModally(pageLayout, with: printInfo, for: document, completion: completion)
            return
        }
        if #available(macOS 14, *) {
            // macOS 14+：completion 版 sheet API
            pageLayout.beginSheet(using: printInfo, on: window) { [weak self] result in
                let accepted = result.rawValue == NSApplication.ModalResponse.OK.rawValue
                self?.applyPageSetupResult(accepted ? pageLayout.printInfo : nil,
                                           fallback: printInfo, for: document, completion: completion)
            }
        } else {
            // macOS 12/13：NSPageLayout 无 completion 版 sheet API（10.5 版 delegate API 需 NSObject
            // 接收 selector，代价高），退化为应用级模态——仅影响旧系统上的页面设置呈现方式
            runPageLayoutModally(pageLayout, with: printInfo, for: document, completion: completion)
        }
    }

    /// 以应用级模态运行页面设置面板（无宿主窗口 / macOS 12-13 回退路径共用）。
    /// - Parameters:
    ///   - pageLayout: 页面设置面板
    ///   - printInfo: 当前打印信息
    ///   - document: 目标文档
    ///   - completion: 用户确认后回传更新后的打印信息；取消时回传原打印信息
    private func runPageLayoutModally(_ pageLayout: NSPageLayout,
                                      with printInfo: NSPrintInfo,
                                      for document: NPTextDocument,
                                      completion: @escaping (NSPrintInfo) -> Void) {
        let accepted = pageLayout.runModal(with: printInfo) == NSApplication.ModalResponse.OK.rawValue
        applyPageSetupResult(accepted ? pageLayout.printInfo : nil,
                             fallback: printInfo, for: document, completion: completion)
    }

    /// 应用页面设置结果（确认时保存并回传新值，取消时回传原值）。
    /// - Parameters:
    ///   - updated: 更新后的打印信息（取消为 nil）
    ///   - fallback: 原打印信息
    ///   - document: 目标文档
    ///   - completion: 完成回调
    private func applyPageSetupResult(_ updated: NSPrintInfo?,
                                      fallback: NSPrintInfo,
                                      for document: NPTextDocument,
                                      completion: @escaping (NSPrintInfo) -> Void) {
        if let updated {
            printInfos[ObjectIdentifier(document)] = updated
            completion(updated)
        } else {
            completion(fallback)
        }
    }

    // MARK: - 打印

    /// 执行打印（系统打印面板：预览/份数/页面范围，PRD FR-019）。
    /// - Parameters:
    ///   - document: 目标文档
    ///   - window: 宿主窗口（sheet 挂载；nil 时应用级模态）
    ///   - completion: true = 已送入打印队列；false = 用户取消
    func printDocument(_ document: NPTextDocument,
                       in window: NSWindow?,
                       completion: @escaping (Bool) -> Void) {
        let printInfo = self.printInfo(for: document)
        let printView = NPPrintTextView(
            text: document.textContent,
            font: NPPreferences.shared.font,
            title: document.displayName ?? "",
            printInfo: printInfo
        )
        let operation = NSPrintOperation(view: printView, printInfo: printInfo)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        guard let window else {
            // 无宿主窗口：应用级模态，返回是否已打印
            completion(operation.run())
            return
        }
        printCompletion = completion
        operation.runModal(for: window,
                           delegate: self,
                           didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
                           contextInfo: nil)
    }

    // MARK: - 私有

    /// 取文档的打印信息（无记录时以共享默认值初始化）。
    /// - Parameter document: 目标文档
    /// - Returns: 打印信息
    private func printInfo(for document: NPTextDocument) -> NSPrintInfo {
        if let stored = printInfos[ObjectIdentifier(document)] {
            return stored
        }
        let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        printInfo.orientation = .portrait
        printInfos[ObjectIdentifier(document)] = printInfo
        return printInfo
    }

    /// 打印 sheet 结束回调。
    /// - Parameters:
    ///   - printOperation: 打印操作
    ///   - success: 是否成功（用户确认即 true，取消为 false）
    ///   - contextInfo: 上下文（未使用）
    @objc private func printOperationDidRun(_ printOperation: NSPrintOperation,
                                            success: Bool,
                                            contextInfo: UnsafeMutableRawPointer?) {
        printCompletion?(success)
        printCompletion = nil
    }
}
