//
//  DecimalCurrencyTests.swift
//  钱伲Tests
//

import XCTest
@testable import 钱伲

/// `Decimal.fenValue`（元 → 分）单元测试
///
/// 这些用例锁住两件事：① 除不尽的值不能再退化成 0（`Int64(truncating:)` 的老 bug）；
/// ② 语义是**朝零截断**，不是四舍五入。
final class DecimalCurrencyTests: XCTestCase {

    // MARK: - 回归锁：除不尽的值不能是 0

    /// AA 分账场景：100 / 3。老写法 `Int64(truncating:)` 在这里返回 0，不是 3333。
    func test_fenValue_nonTerminatingDivision_returnsTruncatedNotZero() {
        XCTAssertEqual((Decimal(100) / 3).fenValue, 3333)
    }

    func test_fenValue_nonTerminatingDivision_otherDivisors() {
        XCTAssertEqual((Decimal(100) / 7).fenValue, 1428)
        XCTAssertEqual((Decimal(1000) / 3).fenValue, 33333)
    }

    /// 负数同样不能退化成 0，且方向朝零（不是朝 −∞）。
    func test_fenValue_negativeNonTerminatingDivision_truncatesTowardZero() {
        XCTAssertEqual((-(Decimal(100) / 3)).fenValue, -3333)
    }

    // MARK: - 边界：能整除的行为必须与老写法完全一致

    func test_fenValue_dividesEvenly_exact() {
        XCTAssertEqual((Decimal(300) / 3).fenValue, 10000)
    }

    func test_fenValue_zero_isZero() {
        XCTAssertEqual(Decimal(0).fenValue, 0)
    }

    func test_fenValue_wholeYuan() {
        XCTAssertEqual(Decimal(712).fenValue, 71200)
    }

    // MARK: - 语义锁：朝零截断，不是四舍五入

    /// 1.005 元 → 100 分（四舍五入会给 101）。半分处截断。
    func test_fenValue_halfCent_positiveTruncatesNotRounds() {
        XCTAssertEqual(Decimal(string: "1.005")!.fenValue, 100)
    }

    /// 2.675 元 → 267 分（四舍五入会给 268）。
    func test_fenValue_halfCent_anotherPositiveCase() {
        XCTAssertEqual(Decimal(string: "2.675")!.fenValue, 267)
    }

    /// 负数的半分同样朝零：−1.005 → −100（朝 −∞ 会给 −101）。
    func test_fenValue_halfCent_negativeTruncatesTowardZero() {
        XCTAssertEqual(Decimal(string: "-1.005")!.fenValue, -100)
    }

    func test_fenValue_negativeSubCentValues_truncateTowardZero() {
        XCTAssertEqual(Decimal(string: "-0.999")!.fenValue, -99)
        XCTAssertEqual(Decimal(string: "-0.001")!.fenValue, 0)
    }

    func test_fenValue_normalTwoDecimals_exact() {
        XCTAssertEqual(Decimal(string: "712.34")!.fenValue, 71234)
    }

    /// 超过 2 位小数的有限小数：截断，不保留也不四舍五入。
    func test_fenValue_highPrecisionFiniteDecimal_truncates() {
        XCTAssertEqual(Decimal(string: "712.3456789")!.fenValue, 71234)
    }
}
