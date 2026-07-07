import Foundation

extension Array where Element == Transaction {
    func groupedByRelativeDate(locale: Locale? = nil) -> [(key: String, value: [Transaction])] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today) ?? today

        var todayTx: [Transaction] = []
        var yesterdayTx: [Transaction] = []
        var other: [String: [Transaction]] = [:]

        for t in self {
            let day = cal.startOfDay(for: t.date)
            if day == today {
                todayTx.append(t)
            } else if day == yesterday {
                yesterdayTx.append(t)
            } else {
                var fmt = t.date.formatted(.dateTime.month(.abbreviated).day(.defaultDigits))
                if let locale { fmt = t.date.formatted(.dateTime.month(.abbreviated).day(.defaultDigits).locale(locale)) }
                other[fmt, default: []].append(t)
            }
        }

        var result: [(String, [Transaction])] = []
        if !todayTx.isEmpty { result.append(("今天", todayTx)) }
        if !yesterdayTx.isEmpty { result.append(("昨天", yesterdayTx)) }
        for key in other.keys.sorted(by: { other[$0]?.first?.date ?? .distantPast > other[$1]?.first?.date ?? .distantPast }) {
            if let list = other[key] { result.append((key, list)) }
        }
        return result
    }

    /// 排除可报销支出及其关联的报销结算收入，用于统计/报表等非流水口径。
    func excludingReimbursementTransactions() -> [Transaction] {
        let settlementIDs = Set(compactMap(\.reimbursedById))
        return filter { t in
            if t.type == .expense, t.isReimbursable { return false }
            if t.type == .income, settlementIDs.contains(t.id) { return false }
            return true
        }
    }

    /// Keep only one side of each transfer (outflow, amount < 0). Other types pass through unchanged.
    func deduplicatingTransfers() -> [Transaction] {
        var seen = Set<UUID>()
        return filter { t in
            if t.type == .transfer, let gid = t.transferGroupId {
                if seen.contains(gid) { return false }
                if t.amount < 0 {
                    seen.insert(gid)
                    return true
                }
                return false
            }
            return true
        }
    }
}

/// 根据交易类型和借贷方向计算签名金额
func signedAmount(amount: Decimal, type: TransactionType, direction: LendingDirection? = nil) -> Decimal {
    switch type {
    case .expense: return -abs(amount)
    case .income: return abs(amount)
    case .lending:
        switch direction {
        case .lendOut, .repay: return -abs(amount)
        case .borrowIn, .collect: return abs(amount)
        case .none: return abs(amount)
        }
    case .transfer: return -abs(amount)
    case .adjustment: return amount
    default: return abs(amount)
    }
}

/// 将分类层级（父+子）展平为一维数组，按 sortOrder 排序
func flattenCategoryTree(_ parents: [Category]) -> [Category] {
    var result: [Category] = []
    for parent in parents.sorted(by: { $0.sortOrder < $1.sortOrder }) {
        result.append(parent)
        for child in (parent.children as? Set<Category> ?? []).sorted(by: { $0.sortOrder < $1.sortOrder }) {
            result.append(child)
        }
    }
    return result
}
