import Testing
@testable import Qianeymac

/// 与 iOS 侧 `钱伲Tests/AmountInputStateTests.swift` 覆盖同一套规则。
/// `AmountInputState` 是两个 target 共享的类型，任何一侧漏测都可能在另一侧回归。
struct AmountInputStateTests {

    @Test func seededValue_isPristine() {
        var state = AmountInputState()
        state.seed("1,234.50")
        #expect(state.isPristine)
        #expect(state.text == "1,234.50")
    }

    @Test func firstDigitAfterSeed_replacesWholeValue() {
        var state = AmountInputState()
        state.seed("1,234.50")
        state.appendDigit(5)
        #expect(state.text == "5")
        #expect(!state.isPristine)
    }

    @Test func secondDigit_appendsToReplacement() {
        var state = AmountInputState()
        state.seed("1,234.50")
        state.appendDigit(5)
        state.appendDigit(0)
        #expect(state.text == "50")
    }

    @Test func firstDotAfterSeed_becomesZeroDot() {
        var state = AmountInputState()
        state.seed("88.80")
        state.appendDot()
        #expect(state.text == "0.")
        #expect(!state.isPristine)
    }

    @Test func backspaceWhilePristine_deletesInsteadOfReplacing() {
        var state = AmountInputState()
        state.seed("1,234.50")
        state.backspace()
        #expect(state.text == "1,234.5")
        #expect(!state.isPristine)
    }

    @Test func digitAfterBackspace_appends() {
        var state = AmountInputState()
        state.seed("100")
        state.backspace()
        state.appendDigit(5)
        #expect(state.text == "105")
    }

    @Test func clear_emptiesAndLeavesPristine() {
        var state = AmountInputState()
        state.seed("99.9")
        state.clear()
        #expect(state.text == "")
        #expect(!state.isPristine)
    }

    @Test func seedEmpty_isNotPristine() {
        var state = AmountInputState()
        state.seed("")
        #expect(!state.isPristine)
        state.appendDigit(3)
        #expect(state.text == "3")
    }

    @Test func leadingZero_isReplacedNotPrefixed() {
        var state = typed("0")
        state.appendDigit(5)
        #expect(state.text == "5")

        var withDecimals = typed("0.00")
        withDecimals.appendDigit(5)
        #expect(withDecimals.text == "5")
    }

    @Test func thirdDecimalDigit_isIgnored() {
        var state = typed("1.23")
        state.appendDigit(4)
        #expect(state.text == "1.23")
    }

    @Test func backspaceToEmpty_leavesEmptyString() {
        var state = AmountInputState()
        state.seed("7")
        state.backspace()
        #expect(state.text == "")
        #expect(!state.isPristine)
    }

    @Test func dotOnEmptyField_becomesZeroDot() {
        var state = AmountInputState()
        state.seed("")
        state.appendDot()
        #expect(state.text == "0.")
    }

    @Test func secondDot_isIgnored() {
        var state = typed("1.2")
        state.appendDot()
        #expect(state.text == "1.2")
    }

    @Test func seededNegative_firstDigitKeepsSign() {
        var state = AmountInputState()
        state.seed("-500.00")
        state.appendDigit(3)
        #expect(state.text == "-3")
    }

    @Test func toggleSign_keepsPristineSoNextDigitStillReplaces() {
        var state = AmountInputState()
        state.seed("500")
        state.toggleSign()
        #expect(state.text == "-500")
        #expect(state.isPristine)
        state.appendDigit(3)
        #expect(state.text == "-3")
    }

    /// 构造一个「用户已经打过字」的状态：非预填态，后续按键按追加处理。
    private func typed(_ text: String) -> AmountInputState {
        var state = AmountInputState()
        state.seed("")
        state.text = text
        return state
    }

    @Test func seedAfterTyping_returnsToPristine() {
        var state = AmountInputState()
        state.seed("10")
        state.appendDigit(5)
        #expect(state.text == "5")
        state.seed("88.00")
        #expect(state.isPristine)
        state.appendDigit(9)
        #expect(state.text == "9")
    }
}
