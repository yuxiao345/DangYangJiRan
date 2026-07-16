import SwiftUI

/// L3: 分类 × 成员交叉表 — 行=一级分类，列=成员，热力图色块
struct MemberCategoryCrossView: View {
    let items: [MemberCategoryCrossItem]

    /// Stable column identifier
    private struct MemberColumn: Identifiable {
        let id: String  // memberID.uuidString or "__unassigned__"
        let memberID: UUID?
        let name: String
    }

    /// Collect all unique members across all categories for column headers
    private var allMembers: [MemberColumn] {
        var seen: Set<String> = []
        var result: [MemberColumn] = []
        for item in items {
            for ma in item.memberAmounts {
                let key = ma.memberID?.uuidString ?? "__unassigned__"
                if !seen.contains(key) {
                    seen.insert(key)
                    result.append(MemberColumn(id: key, memberID: ma.memberID, name: ma.memberName))
                }
            }
        }
        return result
    }

    /// Find the max amount across all cells for heatmap scaling
    private var maxAmount: Decimal {
        var maxVal: Decimal = 0
        for item in items {
            for ma in item.memberAmounts {
                if ma.amount > maxVal { maxVal = ma.amount }
            }
        }
        return maxVal == 0 ? 1 : maxVal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack {
                Text(String(localized: "分类 × 成员对比"))
                    .font(.designBodyMedium.weight(.semibold))
                    .foregroundStyle(Color.designOnSurface)
                Spacer()
            }
            .padding(.horizontal, 16)

            // Scrollable table
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Column headers
                    headerRow
                    // Data rows
                    ForEach(items) { item in
                        dataRow(for: item)
                    }
                }
            }
            .glassCard(cornerRadius: 14)
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 0) {
            // Category label column
            Text(String(localized: "分类"))
                .font(.designMonoDataSmall)
                .foregroundStyle(Color.designOnSurfaceVariant)
                .frame(width: 80, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            // Member columns
            ForEach(allMembers) { member in
                Text(member.name)
                    .font(.designMonoDataSmall)
                    .foregroundStyle(Color.designOnSurfaceVariant)
                    .frame(width: 72, alignment: .trailing)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
            }

            // Total column
            Text(String(localized: "合计"))
                .font(.designMonoDataSmall)
                .foregroundStyle(Color.designOnSurfaceVariant)
                .frame(width: 72, alignment: .trailing)
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
        }
        .background(Color.designSurfaceContainer.opacity(0.5))
    }

    // MARK: - Data Row

    private func dataRow(for item: MemberCategoryCrossItem) -> some View {
        HStack(spacing: 0) {
            // Category label
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: item.colorHex) ?? .gray)
                    .frame(width: 10, height: 10)
                Text(item.categoryName)
                    .font(.designBodySmall)
                    .foregroundStyle(Color.designOnSurface)
                    .lineLimit(1)
            }
            .frame(width: 80, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            // Member amount cells
            ForEach(allMembers) { member in
                let amt = item.memberAmounts.first(where: { $0.memberID == member.memberID })?.amount ?? 0
                cellView(amount: amt)
            }

            // Total column
            totalCellView(amount: item.totalAmount)
        }
    }

    // MARK: - Cell Views

    private func cellView(amount: Decimal) -> some View {
        let intensity = maxAmount > 0 ? Double(truncating: (amount / maxAmount) as NSNumber) : 0
        return CurrencyText(amount: amount, currencyCode: "", size: 12, foregroundColor: Color.designOnSurface)
            .fontWeight(amount > 0 ? .medium : .regular)
            .frame(width: 72, alignment: .trailing)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .background(
                Color.designAccentGreen.opacity(intensity * 0.25)
            )
    }

    private func totalCellView(amount: Decimal) -> some View {
        CurrencyText(amount: amount, currencyCode: "", size: 12, foregroundColor: Color.designOnSurface)
            .fontWeight(.semibold)
            .frame(width: 72, alignment: .trailing)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .background(Color.designSurfaceContainer.opacity(0.3))
    }
}
