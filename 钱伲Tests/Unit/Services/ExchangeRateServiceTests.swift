import XCTest
@preconcurrency import CoreData
@testable import 钱伲

/// ExchangeRateService 单元测试
/// 注意：fetchRate 涉及真实 HTTP 请求，本测试只覆盖同币种路径和错误类型。
/// 网络调用留待集成测试（mock URLProtocol）覆盖。
final class ExchangeRateServiceTests: CoreDataTestCase {

    var service: ExchangeRateServiceImpl!

    override func setUp() {
        super.setUp()
        service = ExchangeRateServiceImpl()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - fetchRate (same currency, no network)

    /// fetchRate 同币种：不走网络，直接返回 rate = 1
    func test_fetchRate_sameCurrency_returnsRateOne() async throws {
        let rate = try await service.fetchRate(from: "CNY", to: "CNY", context: context)

        XCTAssertEqual(rate.fromCurrencyCode, "CNY")
        XCTAssertEqual(rate.toCurrencyCode, "CNY")
        XCTAssertEqual(rate.rate, 1.0)
    }

    // MARK: - cachedRate

    /// cachedRate 同币种：返回 rate = 1
    func test_cachedRate_sameCurrency_returnsRateOne() {
        let rate = service.cachedRate(from: "USD", to: "USD", context: context)

        XCTAssertNotNil(rate)
        XCTAssertEqual(rate?.fromCurrencyCode, "USD")
        XCTAssertEqual(rate?.toCurrencyCode, "USD")
        XCTAssertEqual(rate?.rate, 1.0)
    }

    /// cachedRate 不同币种：当前实现返回 nil（持久化由调用方负责）
    func test_cachedRate_differentCurrency_returnsNil() {
        let rate = service.cachedRate(from: "USD", to: "CNY", context: context)
        XCTAssertNil(rate)
    }

    // MARK: - refreshRates

    /// refreshRates 是 no-op，不抛错
    func test_refreshRates_doesNotThrow() async throws {
        try await service.refreshRates()
        // 不抛错即通过
    }

    // MARK: - ExchangeRateError

    /// rateNotFound 错误：errorDescription 含源+目标币种
    func test_rateNotFoundError_descriptionIncludesCurrencyCodes() {
        let error = ExchangeRateError.rateNotFound("USD", "XYZ")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("USD"))
        XCTAssertTrue(error.errorDescription!.contains("XYZ"))
    }

    /// rateNotFound 错误：LocalizedError 协议符合
    func test_rateNotFoundError_conformsToLocalizedError() {
        let error: LocalizedError = ExchangeRateError.rateNotFound("USD", "XYZ")
        XCTAssertNotNil(error.errorDescription)
    }
}