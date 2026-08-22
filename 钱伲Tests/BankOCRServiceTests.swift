import XCTest
@preconcurrency import CoreData
@testable import 钱伲

/// BankOCRService 单元测试
/// 覆盖：CSV 解析路径（OCR/PDF 路径需要 Vision/PDFKit/UIImage，整体 disabled_）
final class BankOCRServiceTests: XCTestCase {

    var service: BankOCRServiceImpl!

    override func setUp() {
        super.setUp()
        service = BankOCRServiceImpl()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - recognizeTransactions(fromCSV:)

    /// 基本中文表头 CSV 解析
    /// 注：service 把消费金额识别为负数（expense 约定），desc 拼接类别
    func test_recognizeFromCSV_basicChineseHeaders() {
        let csv = """
       消费日期,交易说明,金额,记账日期,交易类别
       2026-08-01,午餐,30.00,2026-08-02,餐饮
       2026-08-02,打车,15.50,2026-08-03,交通
       """
        let data = csv.data(using: .utf8)!

        let items = service.recognizeTransactions(fromCSV: data)

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].amount, -30.00, "消费应为负数")
        XCTAssertTrue(items[0].desc?.contains("午餐") ?? false)
        XCTAssertEqual(items[1].amount, -15.50)
    }

    /// Tab 分隔符
    func test_recognizeFromCSV_tabDelimiter() {
        let csv = "消费日期\t交易说明\t金额\n2026-08-01\t午餐\t30.00\n"
        let data = csv.data(using: .utf8)!

        let items = service.recognizeTransactions(fromCSV: data)

        XCTAssertGreaterThan(items.count, 0)
    }

    /// 仅有 1 行（仅表头）→ 返回空
    func test_recognizeFromCSV_headerOnly_returnsEmpty() {
        let csv = "消费日期,交易说明,金额\n"
        let data = csv.data(using: .utf8)!

        let items = service.recognizeTransactions(fromCSV: data)

        XCTAssertTrue(items.isEmpty)
    }

    /// 空数据 → 返回空
    func test_recognizeFromCSV_emptyData_returnsEmpty() {
        let data = Data()

        let items = service.recognizeTransactions(fromCSV: data)

        XCTAssertTrue(items.isEmpty)
    }

    /// 空行被跳过
    func test_recognizeFromCSV_emptyLines_skipped() {
        let csv = """
       消费日期,交易说明,金额
2026-08-01,午餐,30.00

2026-08-02,打车,15.50

"""
        let data = csv.data(using: .utf8)!

        let items = service.recognizeTransactions(fromCSV: data)

        XCTAssertEqual(items.count, 2)
    }

    /// summary 关键字行（合计/总计/小计）被跳过
    func test_recognizeFromCSV_summaryKeywords_skipped() {
        let csv = """
       消费日期,交易说明,金额
2026-08-01,午餐,30.00
合计,100.00,
"""
        let data = csv.data(using: .utf8)!

        let items = service.recognizeTransactions(fromCSV: data)

        XCTAssertEqual(items.count, 1)
    }

    /// 负数金额输入（消费/退款场景）
    /// 注：service 把所有消费视为负数（金额符号来自类型推断，不取输入符号）
    func test_recognizeFromCSV_negativeAmount() {
        let csv = """
       消费日期,交易说明,金额
2026-08-01,退款,-30.00
"""
        let data = csv.data(using: .utf8)!

        let items = service.recognizeTransactions(fromCSV: data)

        XCTAssertEqual(items.count, 1)
        // service 输出总是 -30.00（视为支出）
        XCTAssertEqual(items.first?.amount, -30.00)
    }

    /// sortOrder 单调递增
    func test_recognizeFromCSV_sortOrderMonotonic() {
        let csv = """
       消费日期,交易说明,金额
2026-08-01,A,10.00
2026-08-02,B,20.00
2026-08-03,C,30.00
"""
        let data = csv.data(using: .utf8)!

        let items = service.recognizeTransactions(fromCSV: data)

        // service 的 sortOrder 反映原始行号（跳过 summary 行后递增）
        XCTAssertEqual(items.count, 3)
        // 验证 sortOrder 严格递增
        for i in 1..<items.count {
            XCTAssertGreaterThan(items[i].sortOrder, items[i-1].sortOrder)
        }
    }

    /// GB18030 编码的中文 CSV（部分银行导出）
    func test_recognizeFromCSV_gb18030Encoding() {
        let csv = "消费日期,交易说明,金额\n2026-08-01,午餐,30.00\n"
        let data = csv.data(using: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))))!

        let items = service.recognizeTransactions(fromCSV: data)

        XCTAssertGreaterThan(items.count, 0)
    }

    // MARK: - recognizeTransactions(from image:) [disabled_]

    /// OCR 图片识别：需要真实 UIImage + Vision framework
    func disabled_test_recognizeFromImage_requiresVision() async throws {
        throw XCTSkip("Known limitation: 需要真实 UIImage + Vision framework，单元测试环境无法提供")
    }

    /// OCR PDF 识别：需要真实 PDF + PDFKit
    func disabled_test_recognizeFromPDF_requiresPDFKit() async throws {
        throw XCTSkip("Known limitation: 需要真实 PDFDocument，单元测试环境无法提供")
    }
}