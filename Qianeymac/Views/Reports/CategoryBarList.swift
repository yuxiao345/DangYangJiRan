import SwiftUI

// MARK: - Category Bar List

struct CategoryBarList: View {
    let categories: [CategoryExpenseItem]
    let barProgress: Double
    @Binding var hoveredIndex: Int?
    @Binding var explodedIndex: Int?
    let onCategoryTap: (UUID) -> Void

    // MARK: - Member Split Support (L2)

    var memberSplits: [UUID: [CategoryMemberSplit]] = [:]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(categories.enumerated()), id: \.element.id) { index, item in
                let isLeaf = item.children.isEmpty
                CategoryBarRow(
                    item: item,
                    index: index,
                    isLeaf: isLeaf,
                    barProgress: barProgress,
                    onTap: { onCategoryTap(item.id) },
                    onHover: { hovering in
                        if hovering {
                            explodedIndex = nil
                            hoveredIndex = index
                        } else {
                            hoveredIndex = nil
                        }
                    }
                )

                // Member split sub-rows (L2)
                if let splits = memberSplits[item.id], !splits.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(splits, id: \.memberID) { split in
                            let mIdx = splits.firstIndex(where: { $0.memberID == split.memberID }) ?? 0
                            memberSubRow(split: split, baseColorHex: item.colorHex, memberIndex: mIdx, totalMembers: splits.count)
                        }
                    }
                    .padding(.leading, 20)
                    .padding(.bottom, 4)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Member Sub-Row

    private func memberSubRow(split: CategoryMemberSplit, baseColorHex: String, memberIndex: Int, totalMembers: Int) -> some View {
        let tint = memberSplitColor(baseColorHex: baseColorHex, memberIndex: memberIndex, totalMembers: totalMembers)
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(split.memberName)
                    .font(.designBodySmall)
                    .foregroundStyle(Color.designOnSurfaceVariant)
                Spacer()
                CurrencyText(amount: split.amount, currencyCode: "", size: 12, foregroundColor: Color.designOnSurfaceVariant)
                Text(split.percentage, format: .percent.precision(.fractionLength(1)))
                    .font(.designMonoDataSmall)
                    .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.6))
            }
            PixelProgressBar(progress: barProgress * split.percentage, tint: tint, totalBlocks: 16)
        }
    }

    private func memberSplitColor(baseColorHex: String, memberIndex: Int, totalMembers: Int) -> Color {
        let base = baseColorHex.isEmpty ? Color.gray : (Color(hex: baseColorHex) ?? .gray)
        guard totalMembers > 1 else { return base }
        let fraction = Double(totalMembers - memberIndex) / Double(totalMembers)
        return base.opacity(max(0.3, fraction))
    }
}

// MARK: - Category Bar Row

private struct CategoryBarRow: View {
    let item: CategoryExpenseItem
    let index: Int
    let isLeaf: Bool
    let barProgress: Double
    let onTap: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: item.colorHex) ?? .gray)
                        .frame(width: 12, height: 12)

                    Text(item.name)
                        .font(.designBodyMedium)
                        .foregroundStyle(Color.designOnSurface)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        CurrencyText(amount: item.amount, currencyCode: "", size: 14, foregroundColor: Color.designOnSurface)
                            .fontWeight(.medium)
                        Text(item.percentage, format: .percent.precision(.fractionLength(1)))
                            .font(.designMonoDataSmall)
                            .foregroundStyle(Color.designOnSurfaceVariant)
                    }

                    if !isLeaf {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
                    }
                }

                thermometerBar
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .glassCard(cornerRadius: 10)
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
    }

    // MARK: Pixel Progress Bar

    private var thermometerBar: some View {
        PixelProgressBar(
            progress: barProgress * item.percentage,
            tint: Color(hex: item.colorHex) ?? .gray
        )
        .animation(
            .spring(response: 0.7, dampingFraction: 0.55)
            .delay(Double(index) * 0.09),
            value: barProgress
        )
    }
}
