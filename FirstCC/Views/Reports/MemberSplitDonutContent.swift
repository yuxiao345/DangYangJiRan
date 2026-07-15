import SwiftUI
import Charts

/// L2 member-split donut: each category sector is split into adjacent member sub-sectors.
/// Same color family, decreasing opacity per member.
struct MemberSplitDonutContent: View {
    let items: [MemberSplitDonutItem]
    let animationProgress: Double

    /// Color lookup: (categoryID, memberIndex) → Color
    private func memberColor(categoryColorHex: String, memberIndex: Int, totalMembers: Int) -> Color {
        let base = categoryColorHex.isEmpty ? Color.gray : Color(hex: categoryColorHex)
        guard totalMembers > 1 else { return base }
        let fraction = Double(totalMembers - memberIndex) / Double(totalMembers)
        let clampedFraction = max(0.3, fraction)  // never go below 30% opacity
        return base.opacity(clampedFraction)
    }

    var body: some View {
        Chart(items) { item in
            SectorMark(
                angle: .value("amount", abs(Double(truncating: item.amount as NSNumber)) * animationProgress),
                innerRadius: .ratio(0.5),
                angularInset: 1.0
            )
            .foregroundStyle(memberColor(
                categoryColorHex: item.categoryColorHex,
                memberIndex: item.memberIndex,
                totalMembers: item.totalMembers
            ))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}
