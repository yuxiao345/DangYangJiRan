import Foundation

extension Decimal {
    var isNegative: Bool {
        self < 0
    }

    var absoluteValue: Decimal {
        Swift.abs(self)
    }

    func formatted(
        currencyCode: String = "CNY",
        showSign: Bool = false
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2

        let number = NSDecimalNumber(decimal: self)
        guard var result = formatter.string(from: number) else {
            return "\(self)"
        }

        if showSign, !isNegative {
            result = "+" + result
        }

        return result
    }

    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }

    /// 元 → 分（`Int64`），**朝向零截断**。
    ///
    /// 用在 Core Data 实体的 `Decimal` ↔ `Int64 amountInFen` 桥接上。
    ///
    /// 为什么不写 `Int64(truncating: (self * 100) as NSDecimalNumber)`：
    /// 那个写法在高精度小数上返回的是 **0**，不是截断后的整数。触发条件是
    /// **除法除不尽**——`Decimal` 的除法会填满 38 位有效数字，这种值经
    /// `Int64(truncating:)` 转换即得 0。例：`100 / 3` 元 → **0** 分（应为 3333 分），
    /// 而 `300 / 3` 元 → 10000 分正常。所以「能整除」的用例一直是绿的，bug 长期潜伏。
    ///
    /// 截断语义与历史行为一致：对能精确表示的值，本实现与旧写法输出完全相同
    /// （如 `712.3456789 → 71234`、`-1.005 → -100`、`2.675 → 267`）。
    ///
    /// 注意 `Decimal.RoundingMode` 没有 `.floor`；朝向零截断必须写
    /// `v < 0 ? .up : .down`（`.down` 是朝 −∞、`.up` 是朝 +∞）。
    var fenValue: Int64 {
        var scaled = self * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, scaled.isNegative ? .up : .down)
        return NSDecimalNumber(decimal: rounded).int64Value
    }
}
