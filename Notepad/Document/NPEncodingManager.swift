//
//  NPEncodingManager.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import Foundation

/// 编码检测器抽象（协议隔离实现，便于 Mock 测试，见 `05_TEST_PLAN.md`）。
protocol NPEncodingDetector {
    /// 检测原始数据的编码。
    /// - Parameter data: 原始文件数据
    /// - Returns: 检测结果（编码 + 置信度 + 是否有 BOM）
    /// - Throws: `NPEncodingError.undetectable`（置信度低于阈值时）
    func detect(from data: Data) throws -> NPEncodingDetectionResult
}

/// 系统默认编码检测器实现（BOM 检测 → 内容启发式分析，见 `01_TECH_SPEC.md` 3.2）。
struct NPDefaultEncodingDetector: NPEncodingDetector {

    // MARK: - 常量

    /// 判定为二进制文件的非法控制字符比例上限
    private static let binaryControlRatioThreshold = 0.3
    /// 判定 CJK 结构所需的最少合法双字节对数（低于此数视为西欧单字节编码的偶然配对）
    private static let minimumCJKPairCount = 2
    /// 判定 CJK 结构允许的孤立高位字节占比上限（西欧文本高位字节多孤立出现，CJK 文本几乎全部成对）
    private static let cjkOrphanRatioThreshold = 0.15
    /// 无 CJK 结构时回退 Windows-1252 的置信度（低，但不抛错）
    private static let fallbackConfidence = 0.3
    /// UTF-8 内容启发式置信度
    private static let utf8Confidence = 0.95
    /// GB18030 四字节序列命中时的置信度
    private static let gb18030FourByteConfidence = 0.95
    /// GB18030 独占 trail 区间命中时的置信度
    private static let gb18030ExclusiveConfidence = 0.9
    /// 启发式判定 Big5 的置信度
    private static let big5HeuristicConfidence = 0.8
    /// 启发式判定 GB18030 的置信度
    private static let gb18030HeuristicConfidence = 0.75

    /// UTF-8 BOM
    private static let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]
    /// UTF-16 LE BOM
    private static let utf16LittleEndianBOM: [UInt8] = [0xFF, 0xFE]
    /// UTF-16 BE BOM
    private static let utf16BigEndianBOM: [UInt8] = [0xFE, 0xFF]
    /// UTF-32 LE BOM（前缀与 UTF-16 LE BOM 相同，必须先判）
    private static let utf32LittleEndianBOM: [UInt8] = [0xFF, 0xFE, 0x00, 0x00]
    /// UTF-32 BE BOM
    private static let utf32BigEndianBOM: [UInt8] = [0x00, 0x00, 0xFE, 0xFF]

    // MARK: - NPEncodingDetector

    /// 检测原始数据的编码（两阶段：BOM → 内容启发式）。
    /// - Parameter data: 原始文件数据
    /// - Returns: 检测结果（编码 + 置信度 + 是否有 BOM）
    /// - Throws: `NPEncodingError.undetectable`（二进制内容或置信度低于阈值）
    func detect(from data: Data) throws -> NPEncodingDetectionResult {
        // 阶段 1 — BOM 检测（UTF-16/UTF-32 仅通过 BOM 判定，内容分析不可靠）
        if let bomResult = Self.detectBOM(in: data) {
            return bomResult
        }
        // 空文件默认 UTF-8（UT-ENC-010）
        if data.isEmpty {
            return NPEncodingDetectionResult(encoding: .utf8, confidence: 1.0, hasBOM: false)
        }
        // 二进制内容直接判为不可检测（UT-ENC-011）
        try Self.ensureNotBinary(data)
        // 阶段 2 — 内容启发式：严格 UTF-8 校验 → 双字节统计 → Windows-1252 兜底
        if let utf8Result = Self.detectUTF8(in: data) {
            return utf8Result
        }
        if let cjkResult = Self.detectCJK(in: data) {
            return cjkResult
        }
        return NPEncodingDetectionResult(encoding: .windowsCP1252, confidence: Self.fallbackConfidence, hasBOM: false)
    }

    // MARK: - 阶段 1：BOM 检测

    /// 按 BOM 前缀判定 Unicode 编码。
    ///
    /// 判定顺序不可调整：UTF-32 LE 的 BOM `FF FE 00 00` 以 UTF-16 LE 的 BOM `FF FE` 为前缀，
    /// 必须先判 UTF-32 再判 UTF-16（UT-ENC-012）。
    /// - Parameter data: 原始文件数据
    /// - Returns: 命中 BOM 时返回置信度 1.0 的结果，否则返回 `nil`
    private static func detectBOM(in data: Data) -> NPEncodingDetectionResult? {
        if data.starts(with: utf32BigEndianBOM) {
            return NPEncodingDetectionResult(encoding: .utf32BigEndian, confidence: 1.0, hasBOM: true)
        }
        if data.starts(with: utf32LittleEndianBOM) {
            return NPEncodingDetectionResult(encoding: .utf32LittleEndian, confidence: 1.0, hasBOM: true)
        }
        if data.starts(with: utf16LittleEndianBOM) {
            return NPEncodingDetectionResult(encoding: .utf16LittleEndian, confidence: 1.0, hasBOM: true)
        }
        if data.starts(with: utf16BigEndianBOM) {
            return NPEncodingDetectionResult(encoding: .utf16BigEndian, confidence: 1.0, hasBOM: true)
        }
        if data.starts(with: utf8BOM) {
            return NPEncodingDetectionResult(encoding: .utf8, confidence: 1.0, hasBOM: true)
        }
        return nil
    }

    // MARK: - 阶段 2：内容启发式

    /// 检查数据是否像二进制文件：含 NUL 字节，或非法控制字符（除 Tab/LF/CR）比例超阈值。
    /// - Parameter data: 原始文件数据
    /// - Throws: `NPEncodingError.undetectable`
    private static func ensureNotBinary(_ data: Data) throws {
        var controlCount = 0
        for byte in data where byte < 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D {
            controlCount += 1
        }
        let containsNUL = data.contains(0x00)
        let controlRatio = Double(controlCount) / Double(data.count)
        if containsNUL || controlRatio > binaryControlRatioThreshold {
            throw NPEncodingError.undetectable
        }
    }

    /// 严格 UTF-8 校验：合法即判定为 UTF-8（纯 ASCII 是合法 UTF-8，UT-ENC-014）。
    /// - Parameter data: 原始文件数据
    /// - Returns: 合法 UTF-8 时返回结果，否则返回 `nil`
    private static func detectUTF8(in data: Data) -> NPEncodingDetectionResult? {
        guard String(data: data, encoding: .utf8) != nil else {
            return nil
        }
        let isPureASCII = data.allSatisfy { byte in byte < 0x80 }
        let confidence = isPureASCII ? 1.0 : utf8Confidence
        return NPEncodingDetectionResult(encoding: .utf8, confidence: confidence, hasBOM: false)
    }

    /// 双字节区间统计，区分 GB18030 与 Big5。
    ///
    /// 判别特征：
    /// - GB18030 四字节序列（lead `0x81–0xFE` + `0x30–0x39` + lead + `0x30–0x39`）为 GB 系独有；
    /// - trail 落在 `0x80–0xA0` 区间仅 GB 系合法（Big5 trail 为 `0x40–0x7E` / `0xA1–0xFE`）；
    /// - 其余双字节两者均合法，按 lead 高频区投票：Big5 高频字 lead 集中于 `0xA1–0xAF`，
    ///   GB 高频字 lead 集中于 `0xD0–0xF7`；Big5 常用 trail 低区 `0x40–0x7E`（GB2312 不使用）作为佐证；
    /// - 票数持平或无区分特征时归 GB18030（GBK/GB2312 超集，对齐 PRD FR-010 优先级 UTF-8 > GBK > ANSI）。
    ///
    /// 前置门槛（防止西欧单字节编码误判为 CJK）：
    /// - 合法双字节对数不得低于 `minimumCJKPairCount`；
    /// - 未组成合法对的高位字节（≥ 0x80）占比不得高于 `cjkOrphanRatioThreshold`——
    ///   Windows-1252 文本中高位字节多孤立出现（如 `é`、`ü` 后随空格/标点），CJK 文本则几乎全部成对。
    /// - Parameter data: 原始文件数据
    /// - Returns: 存在 CJK 双字节结构时返回结果，否则返回 `nil`
    private static func detectCJK(in data: Data) -> NPEncodingDetectionResult? {
        let stats = collectCJKStats(in: data)
        let totalPairs = stats.sharedPairs + stats.gbExclusivePairs + stats.gbFourByteSequences
        guard totalPairs >= minimumCJKPairCount else {
            return nil
        }
        let pairedHighBytes = (stats.sharedPairs + stats.gbExclusivePairs) * 2 + stats.gbFourByteSequences * 2
        let totalHighBytes = pairedHighBytes + stats.orphanHighBytes
        let orphanRatio = Double(stats.orphanHighBytes) / Double(max(totalHighBytes, 1))
        guard orphanRatio <= cjkOrphanRatioThreshold else {
            return nil
        }
        if stats.gbFourByteSequences > 0 {
            return NPEncodingDetectionResult(encoding: .gb18030, confidence: gb18030FourByteConfidence, hasBOM: false)
        }
        if stats.gbExclusivePairs > 0 {
            return NPEncodingDetectionResult(encoding: .gb18030, confidence: gb18030ExclusiveConfidence, hasBOM: false)
        }
        let big5Evidence = stats.big5ZoneLeads * 2 + stats.big5LowTrails
        let gbEvidence = stats.gbZoneLeads * 2
        if big5Evidence > gbEvidence {
            return NPEncodingDetectionResult(encoding: .big5, confidence: big5HeuristicConfidence, hasBOM: false)
        }
        return NPEncodingDetectionResult(encoding: .gb18030, confidence: gb18030HeuristicConfidence, hasBOM: false)
    }

    /// 双字节扫描统计结果。
    private struct CJKStats {
        /// GB18030 与 Big5 均合法的双字节对数
        var sharedPairs = 0
        /// trail 落在 `0x80–0xA0` 的双字节对数（GB 系独占特征）
        var gbExclusivePairs = 0
        /// GB18030 四字节序列数
        var gbFourByteSequences = 0
        /// lead 落在 `0xA1–0xAF` 的双字节对数（Big5 高频区）
        var big5ZoneLeads = 0
        /// lead 落在 `0xD0–0xF7` 的双字节对数（GB 高频区）
        var gbZoneLeads = 0
        /// trail 落在 `0x40–0x7E` 的双字节对数（Big5 常用，GB2312 不使用）
        var big5LowTrails = 0
        /// 未组成合法双字节/四字节序列的高位字节（≥ 0x80）数
        var orphanHighBytes = 0
    }

    /// 顺序扫描字节流，按双字节区间规则累计统计。
    /// - Parameter data: 原始文件数据
    /// - Returns: CJK 双字节统计结果
    private static func collectCJKStats(in data: Data) -> CJKStats {
        var stats = CJKStats()
        let bytes = [UInt8](data)
        var index = 0
        while index < bytes.count {
            let lead = bytes[index]
            // ASCII 直接跳过
            if lead < 0x80 {
                index += 1
                continue
            }
            // 非 lead 区间（0x80、0xFF）或落单的 lead 计为孤立高位字节
            guard lead >= 0x81, lead <= 0xFE, index + 1 < bytes.count else {
                stats.orphanHighBytes += 1
                index += 1
                continue
            }
            let trail = bytes[index + 1]
            // GB18030 四字节序列：0x81–0xFE 0x30–0x39 0x81–0xFE 0x30–0x39
            if trail >= 0x30, trail <= 0x39, index + 3 < bytes.count,
               bytes[index + 2] >= 0x81, bytes[index + 2] <= 0xFE,
               bytes[index + 3] >= 0x30, bytes[index + 3] <= 0x39 {
                stats.gbFourByteSequences += 1
                index += 4
                continue
            }
            switch trail {
            case 0x40 ... 0x7E:
                stats.sharedPairs += 1
                stats.big5LowTrails += 1
                countLeadZone(lead, into: &stats)
                index += 2
            case 0x80 ... 0xA0:
                stats.gbExclusivePairs += 1
                index += 2
            case 0xA1 ... 0xFE:
                stats.sharedPairs += 1
                countLeadZone(lead, into: &stats)
                index += 2
            default:
                stats.orphanHighBytes += 1
                index += 1
            }
        }
        return stats
    }

    /// 按 lead 字节累计 Big5 / GB 高频区票数。
    /// - Parameters:
    ///   - lead: 双字节对的 lead 字节
    ///   - stats: 统计结果（原地修改）
    private static func countLeadZone(_ lead: UInt8, into stats: inout CJKStats) {
        switch lead {
        case 0xA1 ... 0xAF:
            stats.big5ZoneLeads += 1
        case 0xD0 ... 0xF7:
            stats.gbZoneLeads += 1
        default:
            break
        }
    }
}

/// 编码管理器：检测、解码、编码的唯一入口。
final class NPEncodingManager {

    /// 全局共享实例
    static let shared = NPEncodingManager()

    /// 编码检测器（依赖注入，默认系统实现）
    private let detector: NPEncodingDetector

    /// 置信度阈值，低于此值抛出 `NPEncodingError.undetectable`
    private static let confidenceThreshold = 0.2

    /// 依赖注入，默认使用系统检测器实现。
    /// - Parameter detector: 编码检测器
    init(detector: NPEncodingDetector = NPDefaultEncodingDetector()) {
        self.detector = detector
    }

    // MARK: - 检测

    /// 检测编码。CPU 密集，可在后台线程调用。
    /// - Parameter data: 原始文件数据
    /// - Returns: 检测结果（编码 + 置信度 + 是否有 BOM）
    /// - Throws: `NPEncodingError.undetectable`（置信度低于阈值时）
    func detect(from data: Data) throws -> NPEncodingDetectionResult {
        let result = try detector.detect(from: data)
        guard result.confidence >= Self.confidenceThreshold else {
            throw NPEncodingError.undetectable
        }
        return result
    }

    // MARK: - 解码 / 编码

    /// 按指定编码解码为字符串。
    /// - Parameters:
    ///   - data: 原始数据
    ///   - encoding: 源编码
    /// - Returns: 解码后的字符串
    /// - Throws: `NPEncodingError.conversionFailed`
    func decode(_ data: Data, as encoding: String.Encoding) throws -> String {
        guard let text = String(data: data, encoding: encoding) else {
            throw NPEncodingError.conversionFailed
        }
        return text
    }

    /// 按指定编码序列化字符串。
    /// - Parameters:
    ///   - text: 文本内容
    ///   - encoding: 目标编码
    ///   - includeBOM: 是否写入 BOM（仅 UTF-8/UTF-16/UTF-32 有效）
    /// - Returns: 编码后的数据
    /// - Throws: `NPEncodingError.conversionFailed`
    func encode(_ text: String, as encoding: String.Encoding, includeBOM: Bool) throws -> Data {
        let effectiveEncoding = Self.effectiveEncoding(for: encoding)
        guard var data = text.data(using: effectiveEncoding) else {
            throw NPEncodingError.conversionFailed
        }
        if includeBOM, let bom = Self.bomBytes(for: effectiveEncoding) {
            data.insert(contentsOf: bom, at: 0)
        }
        return data
    }

    /// 支持的编码清单（对齐 PRD FR-010）。
    static var supportedEncodings: [String.Encoding] {
        [
            .utf8,
            .utf16LittleEndian,
            .utf16BigEndian,
            .utf32LittleEndian,
            .utf32BigEndian,
            .windowsCP1252,
            .gb18030,
            .big5
        ]
    }

    // MARK: - BOM 工具

    /// 指定编码的 BOM 字节序列（非 Unicode 编码返回 `nil`）。
    /// - Parameter encoding: 目标编码
    /// - Returns: BOM 字节序列
    static func bomBytes(for encoding: String.Encoding) -> [UInt8]? {
        switch encoding {
        case .utf8:
            return [0xEF, 0xBB, 0xBF]
        case .utf16LittleEndian:
            return [0xFF, 0xFE]
        case .utf16BigEndian:
            return [0xFE, 0xFF]
        case .utf32LittleEndian:
            return [0xFF, 0xFE, 0x00, 0x00]
        case .utf32BigEndian:
            return [0x00, 0x00, 0xFE, 0xFF]
        default:
            return nil
        }
    }

    /// 归一化编码：泛型 `.utf16` / `.utf32` 映射为显式小端变体，使 BOM 写入行为确定。
    /// - Parameter encoding: 原始编码
    /// - Returns: 归一化后的编码
    private static func effectiveEncoding(for encoding: String.Encoding) -> String.Encoding {
        switch encoding {
        case .utf16:
            return .utf16LittleEndian
        case .utf32:
            return .utf32LittleEndian
        default:
            return encoding
        }
    }
}
