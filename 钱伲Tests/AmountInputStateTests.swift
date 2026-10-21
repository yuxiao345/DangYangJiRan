//
//  AmountInputStateTests.swift
//  钱伲Tests
//

import XCTest
@testable import 钱伲

final class AmountInputStateTests: XCTestCase {

    // MARK: - 预填态：第一个数字键整串替换

    func testSeededValue_isPristine() {
        var state = AmountInputState()
        state.seed("1,234.50")
        XCTAssertTrue(state.isPristine)
        XCTAssertEqual(state.text, "1,234.50")
    }

    func testFirstDigitAfterSeed_replacesWholeValue() {
        var state = AmountInputState()
        state.seed("1,234.50")
        state.appendDigit(5)
        XCTAssertEqual(state.text, "5")
        XCTAssertFalse(state.isPristine)
    }

    func testSecondDigit_appendsToReplacement() {
        var state = AmountInputState()
        state.seed("1,234.50")
        state.appendDigit(5)
        state.appendDigit(0)
        XCTAssertEqual(state.text, "50")
    }

    func testFirstDotAfterSeed_becomesZeroDot() {
        var state = AmountInputState()
        state.seed("88.80")
        state.appendDot()
        XCTAssertEqual(state.text, "0.")
        XCTAssertFalse(state.isPristine)
    }

    // MARK: - 退格与清空不算整串重输

    func testBackspaceWhilePristine_deletesLastCharacterInsteadOfReplacing() {
        var state = AmountInputState()
        state.seed("1,234.50")
        state.backspace()
        XCTAssertEqual(state.text, "1,234.5")
        XCTAssertFalse(state.isPristine)
    }

    func testDigitAfterBackspace_appends() {
        var state = AmountInputState()
        state.seed("100")
        state.backspace()
        state.appendDigit(5)
        XCTAssertEqual(state.text, "105")
    }

    func testBackspaceToEmpty_leavesEmptyString() {
        var state = AmountInputState()
        state.seed("7")
        state.backspace()
        XCTAssertEqual(state.text, "")
        XCTAssertFalse(state.isPristine)
    }

    func testClear_emptiesAndLeavesPristine() {
        var state = AmountInputState()
        state.seed("99.9")
        state.clear()
        XCTAssertEqual(state.text, "")
        XCTAssertFalse(state.isPristine)
    }

    // MARK: - 空字段（新建记账）

    func testSeedEmpty_isNotPristine() {
        var state = AmountInputState()
        state.seed("")
        XCTAssertFalse(state.isPristine)
    }

    func testDigitOnEmptyField_startsFresh() {
        var state = AmountInputState()
        state.seed("")
        state.appendDigit(3)
        XCTAssertEqual(state.text, "3")
    }

    // MARK: - 原有追加规则

    func testLeadingZero_isReplacedNotPrefixed() {
        var state = typed("0")
        state.appendDigit(5)
        XCTAssertEqual(state.text, "5")
    }

    func testLeadingZeroWithDecimals_isReplacedNotPrefixed() {
        var state = typed("0.00")
        state.appendDigit(5)
        XCTAssertEqual(state.text, "5")
    }

    func testThirdDecimalDigit_isIgnored() {
        var state = typed("1.23")
        state.appendDigit(4)
        XCTAssertEqual(state.text, "1.23")
    }

    func testSecondDot_isIgnored() {
        var state = typed("1.2")
        state.appendDot()
        XCTAssertEqual(state.text, "1.2")
    }

    // MARK: - Helpers

    /// 构造一个「用户已经打过字」的状态：非预填态，后续按键按追加处理。
    private func typed(_ text: String) -> AmountInputState {
        var state = AmountInputState()
        state.seed("")
        state.text = text
        return state
    }

    func testDotOnEmptyField_becomesZeroDot() {
        var state = AmountInputState()
        state.seed("")
        state.appendDot()
        XCTAssertEqual(state.text, "0.")
    }

    // MARK: - 负号（余额类字段）

    func testSeededNegative_firstDigitKeepsSign() {
        var state = AmountInputState()
        state.seed("-500.00")
        state.appendDigit(3)
        XCTAssertEqual(state.text, "-3")
    }

    func testSeededNegative_firstDotKeepsSign() {
        var state = AmountInputState()
        state.seed("-500")
        state.appendDot()
        XCTAssertEqual(state.text, "-0.")
    }

    func testToggleSign_keepsPristineSoNextDigitStillReplaces() {
        var state = AmountInputState()
        state.seed("500")
        state.toggleSign()
        XCTAssertEqual(state.text, "-500")
        XCTAssertTrue(state.isPristine)
        state.appendDigit(3)
        XCTAssertEqual(state.text, "-3")
    }

    func testToggleSign_afterTyping_appendsNormally() {
        var state = typed("500")
        state.toggleSign()
        XCTAssertEqual(state.text, "-500")
        state.appendDigit(3)
        XCTAssertEqual(state.text, "-5003")
    }

    func testToggleSign_onEmptyField_doesNothing() {
        var state = AmountInputState()
        state.seed("")
        state.toggleSign()
        XCTAssertEqual(state.text, "")
    }

    // MARK: - 再预填

    func testSeedAfterTyping_returnsToPristine() {
        var state = AmountInputState()
        state.seed("10")
        state.appendDigit(5)
        XCTAssertEqual(state.text, "5")
        state.seed("88.00")
        XCTAssertTrue(state.isPristine)
        state.appendDigit(9)
        XCTAssertEqual(state.text, "9")
    }
}
