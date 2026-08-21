import XCTest
@testable import 钱伲

/// CurrencyService 单元测试
/// 纯逻辑，不依赖 CoreData。
/// convert 跨币种涉及真实 HTTP 调用，本次只覆盖同币种短路。
/// 跨币种 mock URLProtocol 留待后续批次。
final class CurrencyServiceTests: XCTestCase {

    var service: CurrencyServiceImpl!

    override func setUp() {
        super.setUp()
        service = CurrencyServiceImpl()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - supportedCurrencies

    /// supportedCurrencies 包含 16 个常用币种
    func test_supportedCurrencies_containsMajorCodes() {
        let codes = service.supportedCurrencies

        XCTAssertEqual(codes.count, 16)
        XCTAssertTrue(codes.contains("CNY"))
        XCTAssertTrue(codes.contains("USD"))
        XCTAssertTrue(codes.contains("EUR"))
        XCTAssertTrue(codes.contains("JPY"))
        XCTAssertTrue(codes.contains("GBP"))
        XCTAssertTrue(codes.contains("HKD"))
    }

    // MARK: - format

    /// format CNY 正数不带符号
    func test_format_cnyPositiveNoSign() {
        let result = service.format(amount: 100, currencyCode: "CNY", showSign: false)

        XCTAssertTrue(result.contains("100"), "应包含金额 100：\(result)")
        XCTAssertTrue(result.contains("¥") || result.contains("￥"), "应包含 CNY 符号：\(result)")
    }

    /// format CNY 正数带正号
    func test_format_cnyPositiveWithSign() {
        let result = service.format(amount: 100, currencyCode: "CNY", showSign: true)

        XCTAssertTrue(result.contains("+"), "showSign=true 应包含 +：\(result)")
    }

    /// format CNY 负数显示负号
    func test_format_cnyNegative() {
        let result = service.format(amount: -50, currencyCode: "CNY", showSign: false)

        XCTAssertTrue(result.contains("-") || result.contains("("), "负数应包含 - 或 (：\(result)")
    }

    /// format 委托给 CurrencyFormatter，USD 应使用 $ 符号
    func test_format_usd_usesDollarSymbol() {
        let result = service.format(amount: 100, currencyCode: "USD", showSign: false)

        XCTAssertTrue(result.contains("$") || result.contains("US$"), "USD 应包含 $ 符号：\(result)")
    }

    // MARK: - symbol

    /// symbol CNY 返回 ¥
    func test_symbol_cny_returnsYen() {
        let symbol = service.symbol(for: "CNY")
        XCTAssertTrue(symbol == "¥" || symbol == "￥", "CNY 符号应为 ¥ 或 ￥，实际：\(symbol)")
    }

    /// symbol USD 返回 US$（区别于 HKD/AUD/CAD 等其他 $ 货币）
    func test_symbol_usd_returnsUSDollar() {
        XCTAssertEqual(service.symbol(for: "USD"), "US$")
    }

    /// symbol EUR 返回 €
    func test_symbol_eur_returnsEuro() {
        XCTAssertEqual(service.symbol(for: "EUR"), "€")
    }

    // MARK: - convert (同币种短路)

    /// convert 同币种直接返回原金额（不走网络）
    func test_convert_sameCurrency_returnsAmount() async throws {
        let result = try await service.convert(
            amount: 100,
            from: "CNY",
            to: "CNY"
        )

        XCTAssertEqual(result, 100)
    }

    /// convert 同币种 USD → USD
    func test_convert_sameCurrencyUSD_returnsAmount() async throws {
        let result = try await service.convert(
            amount: 50,
            from: "USD",
            to: "USD"
        )

        XCTAssertEqual(result, 50)
    }

    // MARK: - currencyName

    /// currencyName CNY 返回人民币
    func test_currencyName_cny() {
        XCTAssertEqual(service.currencyName("CNY"), "人民币")
    }

    /// currencyName USD 返回美元
    func test_currencyName_usd() {
        XCTAssertEqual(service.currencyName("USD"), "美元")
    }

    /// currencyName EUR 返回欧元
    func test_currencyName_eur() {
        XCTAssertEqual(service.currencyName("EUR"), "欧元")
    }

    /// currencyName JPY 返回日元
    func test_currencyName_jpy() {
        XCTAssertEqual(service.currencyName("JPY"), "日元")
    }

    /// currencyName GBP 返回英镑
    func test_currencyName_gbp() {
        XCTAssertEqual(service.currencyName("GBP"), "英镑")
    }

    /// currencyName HKD 返回港币
    func test_currencyName_hkd() {
        XCTAssertEqual(service.currencyName("HKD"), "港币")
    }

    /// currencyName 未知 code 返回 code 本身
    func test_currencyName_unknownCode_returnsCode() {
        XCTAssertEqual(service.currencyName("XYZ"), "XYZ")
    }
}