//
//  QianeymacTests.swift
//  QianeymacTests
//
//  Created by Lakuuo&George on 2026/6/1.
//

import Foundation
import Testing
@testable import Qianeymac

struct CurrencyFormatterTests {

    // MARK: - simpleCurrencySymbol

    @Test func currencySymbol_CNY_returnsYenSign() {
        #expect(CurrencyFormatter.simpleCurrencySymbol(for: "CNY") == "¥")
    }

    @Test func currencySymbol_USD_returnsDollarSign() {
        #expect(CurrencyFormatter.simpleCurrencySymbol(for: "USD") == "$")
    }

    @Test func currencySymbol_EUR_returnsEuroSign() {
        #expect(CurrencyFormatter.simpleCurrencySymbol(for: "EUR") == "€")
    }

    @Test func currencySymbol_GBP_returnsPoundSign() {
        #expect(CurrencyFormatter.simpleCurrencySymbol(for: "GBP") == "£")
    }

    @Test func currencySymbol_JPY_returnsYenSign() {
        #expect(CurrencyFormatter.simpleCurrencySymbol(for: "JPY") == "¥")
    }

    @Test func currencySymbol_HKD_returnsHKDollarSign() {
        #expect(CurrencyFormatter.simpleCurrencySymbol(for: "HKD") == "HK$")
    }

    @Test func currencySymbol_unknownCode_returnsFallbackSymbol() {
        // Unknown codes should still return a non-empty string (fallback from NumberFormatter)
        let symbol = CurrencyFormatter.simpleCurrencySymbol(for: "XYZ")
        #expect(!symbol.isEmpty)
    }

    // MARK: - formatDecimal

    @Test func formatDecimal_positiveCNY_showsSymbolAndAmount() {
        let result = CurrencyFormatter.formatDecimal(amount: 123.45, currencyCode: "CNY")
        #expect(result == "¥123.45")
    }

    @Test func formatDecimal_zero_doesNotCrash() {
        let result = CurrencyFormatter.formatDecimal(amount: 0, currencyCode: "CNY")
        #expect(!result.isEmpty)
    }

    @Test func formatDecimal_showAbs_removesNegativeSign() {
        let result = CurrencyFormatter.formatDecimal(amount: -100, currencyCode: "CNY", showAbs: true)
        #expect(!result.contains("-"))
    }

    @Test func formatDecimal_noCurrencyCode_returnsPlainNumber() {
        let result = CurrencyFormatter.formatDecimal(amount: 99.9, currencyCode: nil)
        #expect(result == "99.90")
    }

    @Test func formatDecimal_zeroFractionDigits_doesNotCrash() {
        let result = CurrencyFormatter.formatDecimal(amount: 100, currencyCode: "CNY", fractionDigits: 0)
        #expect(!result.isEmpty)
    }
}
