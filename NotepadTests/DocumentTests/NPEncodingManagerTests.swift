//
//  NPEncodingManagerTests.swift
//  NotepadTests
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import XCTest
@testable import Notepad

/// `NPEncodingManager` 编码检测与编解码测试（覆盖 `05_TEST_PLAN.md` UT-ENC-001 ~ UT-ENC-014）。
final class NPEncodingManagerTests: XCTestCase {

    /// 被测对象（SUT，测试内允许直接解包/强引用，见 08 §2 测试豁免说明）
    private var sut: NPEncodingManager!

    override func setUp() {
        super.setUp()
        sut = NPEncodingManager()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - BOM 检测

    /// UT-ENC-001：UTF-8 无 BOM 检测 —— `Hello 世界` (UTF-8) 识别为 UTF-8，无 BOM。
    func testDetectUTF8WithoutBOM() throws {
        let data = try XCTUnwrap("Hello 世界".data(using: .utf8))
        let result = try sut.detect(from: data)
        XCTAssertEqual(result.encoding, .utf8)
        XCTAssertFalse(result.hasBOM)
    }

    /// UT-ENC-002：UTF-8 带 BOM 检测 —— `EF BB BF` + UTF-8 内容识别为 UTF-8，有 BOM。
    func testDetectUTF8WithBOM() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(try XCTUnwrap("Hello".data(using: .utf8)))
        let result = try sut.detect(from: data)
        XCTAssertEqual(result.encoding, .utf8)
        XCTAssertTrue(result.hasBOM)
        XCTAssertEqual(result.confidence, 1.0)
    }

    /// UT-ENC-003：UTF-16 LE 检测 —— `FF FE` + UTF-16LE 内容识别为 UTF-16 LE。
    func testDetectUTF16LittleEndian() throws {
        let data = try sut.encode("Hello 世界", as: .utf16LittleEndian, includeBOM: true)
        XCTAssertEqual(data.prefix(2), Data([0xFF, 0xFE]))
        let result = try sut.detect(from: data)
        XCTAssertEqual(result.encoding, .utf16LittleEndian)
        XCTAssertTrue(result.hasBOM)
    }

    /// UT-ENC-004：UTF-16 BE 检测 —— `FE FF` + UTF-16BE 内容识别为 UTF-16 BE。
    func testDetectUTF16BigEndian() throws {
        let data = try sut.encode("Hello 世界", as: .utf16BigEndian, includeBOM: true)
        XCTAssertEqual(data.prefix(2), Data([0xFE, 0xFF]))
        let result = try sut.detect(from: data)
        XCTAssertEqual(result.encoding, .utf16BigEndian)
        XCTAssertTrue(result.hasBOM)
    }

    /// UT-ENC-012：UTF-32 LE 检测 —— `FF FE 00 00` 必须判为 UTF-32 LE 而非 UTF-16 LE（先判 UTF-32）。
    func testDetectUTF32LittleEndianBeforeUTF16() throws {
        let data = try sut.encode("Hello", as: .utf32LittleEndian, includeBOM: true)
        XCTAssertEqual(data.prefix(4), Data([0xFF, 0xFE, 0x00, 0x00]))
        let result = try sut.detect(from: data)
        XCTAssertEqual(result.encoding, .utf32LittleEndian)
        XCTAssertTrue(result.hasBOM)
    }

    /// UT-ENC-013：UTF-32 BE 检测 —— `00 00 FE FF` + UTF-32BE 内容识别为 UTF-32 BE。
    func testDetectUTF32BigEndian() throws {
        let data = try sut.encode("Hello", as: .utf32BigEndian, includeBOM: true)
        XCTAssertEqual(data.prefix(4), Data([0x00, 0x00, 0xFE, 0xFF]))
        let result = try sut.detect(from: data)
        XCTAssertEqual(result.encoding, .utf32BigEndian)
        XCTAssertTrue(result.hasBOM)
    }

    // MARK: - 内容启发式

    /// UT-ENC-005：GB18030 检测 —— GB18030 编码中文内容识别为 GB18030。
    func testDetectGB18030() throws {
        let data = try XCTUnwrap("你好世界，这是一个中文测试文件。".data(using: .gb18030))
        let result = try sut.detect(from: data)
        XCTAssertEqual(result.encoding, .gb18030)
        XCTAssertFalse(result.hasBOM)
    }

    /// UT-ENC-006：GBK/GB2312 检测 —— GBK/GB2312 为 GB18030 子集，超集归并识别为 GB18030。
    func testDetectGBKAsGB18030() throws {
        let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GBK_95.rawValue)))
        let data = try XCTUnwrap("简体中文测试内容，用于检测编码。".data(using: gbk))
        let result = try sut.detect(from: data)
        XCTAssertEqual(result.encoding, .gb18030)
    }

    /// UT-ENC-007：Big5 检测 —— Big5 编码繁体中文识别为 Big5。
    func testDetectBig5() throws {
        let data = try XCTUnwrap("繁體中文，這是一個測試文件。".data(using: .big5))
        let result = try sut.detect(from: data)
        XCTAssertEqual(result.encoding, .big5)
        XCTAssertFalse(result.hasBOM)
    }

    /// UT-ENC-008：ANSI/Windows-1252 —— 含高位字节且不构成合法 UTF-8 序列的西欧文本识别为 Windows-1252。
    func testDetectWindows1252() throws {
        let data = try XCTUnwrap("Café — naïve façade, señor.".data(using: .windowsCP1252))
        let result = try sut.detect(from: data)
        XCTAssertEqual(result.encoding, .windowsCP1252)
        XCTAssertLessThan(result.confidence, 0.5)
    }

    /// UT-ENC-009：混合编码容错 —— 包含乱码的 GBK 文件返回最高置信度编码。
    func testDetectGBKWithGarbage() throws {
        var data = try XCTUnwrap("你好世界，这是一个中文测试文件。".data(using: .gb18030))
        data.append(contentsOf: [0xFF, 0x81, 0x20, 0xFF])
        let result = try sut.detect(from: data)
        XCTAssertEqual(result.encoding, .gb18030)
    }

    /// UT-ENC-010：空文件检测 —— 0 字节文件默认 UTF-8。
    func testDetectEmptyData() throws {
        let result = try sut.detect(from: Data())
        XCTAssertEqual(result.encoding, .utf8)
        XCTAssertFalse(result.hasBOM)
    }

    /// UT-ENC-011：二进制文件检测 —— 非文本内容抛出 `undetectable` 错误。
    func testDetectBinaryThrowsUndetectable() {
        var data = Data()
        for index: UInt8 in 0 ... 255 {
            data.append(index)
        }
        XCTAssertThrowsError(try sut.detect(from: data)) { error in
            guard case NPEncodingError.undetectable = error else {
                XCTFail("期望 NPEncodingError.undetectable，实际 \(error)")
                return
            }
        }
    }

    /// UT-ENC-014：纯 ASCII 对照 —— 纯 ASCII 文本识别为 UTF-8（纯 ASCII 是合法 UTF-8）。
    func testDetectPureASCIIAsUTF8() throws {
        let data = try XCTUnwrap("Hello, Notepad! 123".data(using: .ascii))
        let result = try sut.detect(from: data)
        XCTAssertEqual(result.encoding, .utf8)
        XCTAssertEqual(result.confidence, 1.0)
    }

    // MARK: - 编解码

    /// decode/encode 往返：UTF-8/UTF-16 LE·BE/UTF-32 LE·BE（含 BOM 写入）。
    func testEncodeDecodeRoundTripWithBOM() throws {
        let text = "Hello 世界 123"
        for encoding in [String.Encoding.utf8, .utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian] {
            let data = try sut.encode(text, as: encoding, includeBOM: true)
            XCTAssertNotNil(NPEncodingManager.bomBytes(for: encoding))
            let bomCount = try XCTUnwrap(NPEncodingManager.bomBytes(for: encoding)).count
            let decoded = try sut.decode(data.dropFirst(bomCount), as: encoding)
            XCTAssertEqual(decoded, text, "编码 \(encoding.rawValue) 往返失败")
        }
    }

    /// decode/encode 往返：Windows-1252 / GB18030 / Big5（无 BOM）。
    func testEncodeDecodeRoundTripLegacyEncodings() throws {
        let cases: [(String, String.Encoding)] = [
            ("Café señor", .windowsCP1252),
            ("你好世界，中文测试。", .gb18030),
            ("繁體中文測試。", .big5),
        ]
        for (text, encoding) in cases {
            let data = try sut.encode(text, as: encoding, includeBOM: false)
            let decoded = try sut.decode(data, as: encoding)
            XCTAssertEqual(decoded, text, "编码 \(encoding.rawValue) 往返失败")
        }
    }

    /// 编码失败时抛出 `NPEncodingError.conversionFailed`（如中文写入 Windows-1252）。
    func testEncodeUnsupportedCharactersThrows() {
        XCTAssertThrowsError(try sut.encode("中文", as: .windowsCP1252, includeBOM: false)) { error in
            guard case NPEncodingError.conversionFailed = error else {
                XCTFail("期望 NPEncodingError.conversionFailed，实际 \(error)")
                return
            }
        }
    }

    /// 支持的编码清单对齐 PRD FR-010。
    func testSupportedEncodings() {
        let expected: [String.Encoding] = [
            .utf8, .utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian,
            .windowsCP1252, .gb18030, .big5,
        ]
        XCTAssertEqual(NPEncodingManager.supportedEncodings, expected)
    }
}
