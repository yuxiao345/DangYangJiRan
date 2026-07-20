import Foundation

extension AccountAllocationItem {
    /// 资产配置聚合/下钻的统一节点。报告页与 Dashboard 共用同一套数据。
    struct AllocationNode: Identifiable, Hashable {
        let id: String            // L1: "typeRaw|custom|side"；L2: account.id.uuidString —— 稳定 ID
        let name: String
        let iconName: String
        let balance: Decimal      // 资产为正、负债为负
        let isLiability: Bool
        let accountType: AccountType
        let customName: String
        let drillKey: DrillKey?
    }

    struct DrillKey: Hashable {
        let typeRaw: String
        let customName: String
        let isLiability: Bool

        var accountType: AccountType { AccountType(rawValue: typeRaw) ?? .other }
        var displayName: String { customName.isEmpty ? accountType.displayName : customName }
        var iconName: String { accountType.systemIcon }
    }

    /// 由账户条目派生其聚合键：`.other` 类型用 customTypeName 区分
    var drillKey: DrillKey {
        let custom = accountType == .other ? (customTypeName ?? "") : ""
        return DrillKey(typeRaw: accountType.rawValue, customName: custom, isLiability: isLiability)
    }

    var displayName: String {
        if accountType == .other, let c = customTypeName, !c.isEmpty { return c }
        return accountType.displayName
    }
}

enum AllocationAggregator {
    /// L1：按 (具体类型, 侧) 聚合，资产在前、负债在后，按 AccountType.sortPriority 排序
    static func aggregate(_ items: [AccountAllocationItem]) -> [AccountAllocationItem.AllocationNode] {
        var groups: [AccountAllocationItem.DrillKey: Decimal] = [:]
        for item in items {
            groups[item.drillKey, default: 0] += item.balance
        }
        return groups
            .map { (key: $0.key, sum: $0.value) }
            .sorted { lhs, rhs in
                if lhs.key.isLiability != rhs.key.isLiability { return !lhs.key.isLiability }
                return (AccountType(rawValue: lhs.key.typeRaw) ?? .other).sortPriority <
                       (AccountType(rawValue: rhs.key.typeRaw) ?? .other).sortPriority
            }
            .map { pair in
                let type = AccountType(rawValue: pair.key.typeRaw) ?? .other
                return AccountAllocationItem.AllocationNode(
                    id: "\(pair.key.typeRaw)|\(pair.key.customName)|\(pair.key.isLiability)",
                    name: pair.key.customName.isEmpty ? type.displayName : pair.key.customName,
                    iconName: type.systemIcon,
                    balance: pair.sum,
                    isLiability: pair.key.isLiability,
                    accountType: type,
                    customName: pair.key.customName,
                    drillKey: pair.key
                )
            }
    }

    /// L2：下钻到指定 (类型, 侧) 后的账户明细
    static func drillDown(_ items: [AccountAllocationItem], to key: AccountAllocationItem.DrillKey) -> [AccountAllocationItem.AllocationNode] {
        items
            .filter { $0.drillKey == key }
            .map { item in
                AccountAllocationItem.AllocationNode(
                    id: item.id.uuidString,
                    name: item.name,
                    iconName: item.iconName,
                    balance: item.balance,
                    isLiability: item.isLiability,
                    accountType: item.accountType,
                    customName: item.customTypeName ?? "",
                    drillKey: nil
                )
            }
    }
}
