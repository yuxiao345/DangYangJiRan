import SwiftUI
import Charts

/// Shared donut chart used by both iOS and Mac category breakdown views.
/// Separated to avoid Swift type-checker timeout on complex modifier chains.
struct DonutChartContent: View {
    let categories: [CategoryExpenseItem]
    let animationProgress: Double
    @Binding var selectedAngle: Double?
    let gradientLookup: [String: LinearGradient]
    let fallbackGradient: LinearGradient
    let onCategoryTap: (UUID) -> Void

    var body: some View {
        Chart(categories) { item in
            SectorMark(
                angle: .value("金额", abs(Double(truncating: item.amount as NSNumber)) * animationProgress),
                innerRadius: .ratio(0.5),
                angularInset: 2.5
            )
            .foregroundStyle(by: .value("Category", item.name))
        }
        .chartForegroundStyleScale { gradientLookup[$0] ?? fallbackGradient }
        .chartAngleSelection(value: $selectedAngle)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .simultaneousGesture(
            TapGesture().onEnded {
                guard animationProgress >= 1.0, let angle = selectedAngle else { return }
                var cumulative: Double = 0
                for item in categories {
                    cumulative += Double(truncating: item.amount as NSNumber)
                    if angle <= cumulative {
                        onCategoryTap(item.id)
                        selectedAngle = nil
                        return
                    }
                }
            }
        )
    }
}
