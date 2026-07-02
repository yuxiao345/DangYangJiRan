import SwiftUI

// MARK: - Category Bar List

struct CategoryBarList: View {
    let categories: [CategoryExpenseItem]
    let barProgress: Double
    @Binding var hoveredIndex: Int?
    @Binding var explodedIndex: Int?
    let onCategoryTap: (UUID) -> Void

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
            }
        }
        .padding(.horizontal, 24)
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
                        Text(String(format: "%.1f%%", item.percentage * 100))
                            .font(.system(size: 11, design: .monospaced))
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
