import XCTest
@preconcurrency import CoreData
@testable import 钱伲

/// ExportService 单元测试
/// 覆盖：exportToCSV / exportToJSON / shareURL
/// CSV/JSON 输出文件写入临时目录，测试后清理
final class ExportServiceTests: CoreDataTestCase {

    var service: ExportServiceImpl!
    var tempFiles: [URL] = []

    override func setUp() {
        super.setUp()
        service = ExportServiceImpl()
    }

    override func tearDown() {
        service = nil
        for url in tempFiles {
            try? FileManager.default.removeItem(at: url)
        }
        tempFiles.removeAll()
        super.tearDown()
    }

    private func trackTempFile(_ url: URL) -> URL {
        tempFiles.append(url)
        return url
    }

    // MARK: - exportToCSV

    /// exportToCSV 返回有效 URL，文件存在
    func test_exportToCSV_returnsValidURL() throws {
        let ledger = context.makeLedger("L")
        let account = context.makeAccount("现金", ledger: ledger)
        let tx = context.makeTransaction(amount: -100, account: account, ledger: ledger)

        let url = try service.exportToCSV(transactions: [tx])

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        trackTempFile(url)
    }

    /// exportToCSV 包含表头
    func test_exportToCSV_containsHeader() throws {
        let ledger = context.makeLedger("L")
        let account = context.makeAccount("现金", ledger: ledger)
        let tx = context.makeTransaction(amount: -100, account: account, ledger: ledger)

        let url = try service.exportToCSV(transactions: [tx])
        trackTempFile(url)
        let content = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(content.contains("日期"))
        XCTAssertTrue(content.contains("类型"))
        XCTAssertTrue(content.contains("金额"))
    }

    /// exportToCSV 普通交易字段映射正确
    func test_exportToCSV_regularTransaction_mapsFields() throws {
        let ledger = context.makeLedger("L")
        let account = context.makeAccount("现金", ledger: ledger)
        let category = context.makeCategory("餐饮", ledger: ledger, type: .expense)
        let merchant = context.makeMerchant("麦当劳", ledger: ledger)
        let tx = context.makeTransaction(
            amount: -100,
            account: account,
            ledger: ledger,
            category: category,
            type: .expense
        )
        tx.merchant = merchant
        tx.note = "午餐"
        try context.save()

        let url = try service.exportToCSV(transactions: [tx])
        trackTempFile(url)
        let content = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(content.contains("100"), "应包含金额 100")
        XCTAssertTrue(content.contains("餐饮"))
        XCTAssertTrue(content.contains("麦当劳"))
        XCTAssertTrue(content.contains("午餐"))
        XCTAssertTrue(content.contains("现金"))
    }

    /// exportToCSV CSV 字段中的逗号/引号/换行被正确转义
    func test_exportToCSV_escapesSpecialChars() throws {
        let ledger = context.makeLedger("L")
        let account = context.makeAccount("现金", ledger: ledger)
        let tx = context.makeTransaction(amount: -100, account: account, ledger: ledger)
        tx.note = "包含,逗号和\"引号"
        try context.save()

        let url = try service.exportToCSV(transactions: [tx])
        trackTempFile(url)
        let content = try String(contentsOf: url, encoding: .utf8)

        // 引号应该被 escape 为 "" 并整体被 ""
        XCTAssertTrue(content.contains("\"包含,逗号和\"\"引号\""))
    }

    /// exportToCSV 空交易列表只有表头
    func test_exportToCSV_emptyTransactions_onlyHeader() throws {
        let url = try service.exportToCSV(transactions: [])
        trackTempFile(url)
        let content = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(content.contains("日期"))
        // 行数 = 1（仅表头）
        let lines = content.split(separator: "\n")
        XCTAssertEqual(lines.count, 1)
    }

    // MARK: - exportToJSON

    /// exportToJSON 返回有效 URL，文件存在
    func test_exportToJSON_returnsValidURL() throws {
        let ledger = context.makeLedger("L")
        let account = context.makeAccount("现金", ledger: ledger)
        let tx = context.makeTransaction(amount: -100, account: account, ledger: ledger)

        let url = try service.exportToJSON(transactions: [tx])

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        trackTempFile(url)
    }

    /// exportToJSON 输出可解析的 JSON 数组
    func test_exportToJSON_producesParseableArray() throws {
        let ledger = context.makeLedger("L")
        let account = context.makeAccount("现金", ledger: ledger)
        let tx = context.makeTransaction(amount: -100, account: account, ledger: ledger)

        let url = try service.exportToJSON(transactions: [tx])
        trackTempFile(url)
        let data = try Data(contentsOf: url)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.count, 1)
    }

    /// exportToJSON 字段映射：date / amount / currency / account 等
    func test_exportToJSON_mapsFields() throws {
        let ledger = context.makeLedger("L")
        let account = context.makeAccount("现金", ledger: ledger)
        let category = context.makeCategory("餐饮", ledger: ledger, type: .expense)
        let tx = context.makeTransaction(
            amount: -100,
            account: account,
            ledger: ledger,
            category: category,
            type: .expense
        )
        try context.save()

        let url = try service.exportToJSON(transactions: [tx])
        trackTempFile(url)
        let data = try Data(contentsOf: url)
        guard let parsed = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = parsed.first else {
            XCTFail("JSON 解析失败")
            return
        }

        XCTAssertEqual(first["currency"] as? String, "CNY")
        XCTAssertEqual(first["account"] as? String, "现金")
        XCTAssertEqual(first["category"] as? String, "餐饮")
        XCTAssertEqual(first["type"] as? String, "支出")  // service 用 displayName 而非 rawValue
        XCTAssertNotNil(first["id"])
        XCTAssertNotNil(first["date"])
    }

    /// exportToJSON 退款输出负数（抵消原交易）
    func test_exportToJSON_refundShowsNegative() throws {
        let ledger = context.makeLedger("L")
        let account = context.makeAccount("现金", ledger: ledger)
        let original = context.makeTransaction(amount: -100, account: account, ledger: ledger)
        original.refundGroupId = UUID()
        try context.save()

        let url = try service.exportToJSON(transactions: [original])
        trackTempFile(url)
        let data = try Data(contentsOf: url)
        guard let parsed = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = parsed.first else {
            XCTFail("JSON 解析失败")
            return
        }

        XCTAssertEqual(first["amount"] as? String, "-100", "退款应输出负数")
    }

    /// exportToJSON 空交易列表输出空数组
    func test_exportToJSON_emptyTransactions_emptyArray() throws {
        let url = try service.exportToJSON(transactions: [])
        trackTempFile(url)
        let data = try Data(contentsOf: url)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.count, 0)
    }

    // MARK: - shareURL

    /// shareURL 不抛错（实际呈现 Share Sheet 需要 UI 上下文，测试只验证不 crash）
    func test_shareURL_doesNotThrow() {
        let ledger = context.makeLedger("L")
        let account = context.makeAccount("现金", ledger: ledger)
        let tx = context.makeTransaction(amount: -100, account: account, ledger: ledger)
        let url = (try? service.exportToCSV(transactions: [tx])) ?? URL(fileURLWithPath: "/dev/null")
        trackTempFile(url)

        // shareURL 在测试环境（无 root VC）下是 no-op，不应 crash
        service.shareURL(url)
    }
}