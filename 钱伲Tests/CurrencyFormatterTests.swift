//
//  CurrencyFormatterTests.swift
//  钱伲Tests
//

import XCTest
@testable import 钱伲

final class CurrencyFormatterTests: XCTestCase {

    // MARK: - simpleCurrencySymbol

    func testCurrencySymbol_CNY_returnsYenSign() {
        XCTAssertEqual(CurrencyFormatter.simpleCurrencySymbol(for: "CNY"), "¥")
    }

    func testCurrencySymbol_USD_returnsDollarSign() {
        XCTAssertEqual(CurrencyFormatter.simpleCurrencySymbol(for: "USD"), "$")
    }

    func testCurrencySymbol_EUR_returnsEuroSign() {
        XCTAssertEqual(CurrencyFormatter.simpleCurrencySymbol(for: "EUR"), "€")
    }

    func testCurrencySymbol_GBP_returnsPoundSign() {
        XCTAssertEqual(CurrencyFormatter.simpleCurrencySymbol(for: "GBP"), "£")
    }

    func testCurrencySymbol_JPY_returnsYenSign() {
        XCTAssertEqual(CurrencyFormatter.simpleCurrencySymbol(for: "JPY"), "¥")
    }

    func testCurrencySymbol_HKD_returnsHKDollarSign() {
        XCTAssertEqual(CurrencyFormatter.simpleCurrencySymbol(for: "HKD"), "HK$")
    }

    func testCurrencySymbol_unknownCode_returnsNonEmpty() {
        let symbol = CurrencyFormatter.simpleCurrencySymbol(for: "XYZ")
        XCTAssertFalse(symbol.isEmpty)
    }

    // MARK: - formatDecimal

    func testFormatDecimal_positiveCNY_showsSymbolAndAmount() {
        let result = CurrencyFormatter.formatDecimal(amount: 123.45, currencyCode: "CNY")
        XCTAssertEqual(result, "¥123.45")
    }

    func testFormatDecimal_noCurrencyCode_returnsPlainNumber() {
        let result = CurrencyFormatter.formatDecimal(amount: 99.9, currencyCode: nil)
        XCTAssertEqual(result, "99.90")
    }

    func testFormatDecimal_showAbs_removesNegativeSign() {
        let result = CurrencyFormatter.formatDecimal(amount: -100, currencyCode: "CNY", showAbs: true)
        XCTAssertFalse(result.contains("-"))
    }

    func testFormatDecimal_zero_doesNotCrash() {
        let result = CurrencyFormatter.formatDecimal(amount: 0, currencyCode: "CNY")
        XCTAssertFalse(result.isEmpty)
    }

    func testFormatDecimal_zeroFractionDigits_doesNotCrash() {
        let result = CurrencyFormatter.formatDecimal(amount: 100, currencyCode: "CNY", fractionDigits: 0)
        XCTAssertFalse(result.isEmpty)
    }
}
