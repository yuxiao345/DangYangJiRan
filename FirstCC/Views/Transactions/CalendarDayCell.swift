import SwiftUI

/// Single day cell in the calendar strip.
///
/// - Important: Callers must handle `!isCurrentMonth` taps in their `onTap` closure —
///   the cell itself does not guard against non-current-month interaction.
///   When `isCurrentMonth` is `false`, tapping the cell should navigate to the
///   corresponding adjacent month rather than toggling `selectedDay` in the current month.
struct CalendarDayCell: View {
    let day: Int
    /// 0…1 expense heatmap intensity. 0 = no expense.
    let expenseIntensity: Double
    /// 0…1 income heatmap intensity. 0 = no income.
    let incomeIntensity: Double
    let isToday: Bool
    let isSelected: Bool
    let isCurrentMonth: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.designPrimaryContainer.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.designPrimaryContainer, lineWidth: 2)
                        )
                } else if isToday {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.designPrimaryContainer.opacity(0.2))
                }

                VStack(spacing: 2) {
                    Text("\(day)")
                        .font(.designBodySmall.weight(isToday || isSelected ? .bold : .regular))
                        .foregroundColor(
                            isCurrentMonth
                                ? (isToday || isSelected ? .designPrimary : .designOnSurface)
                                : .designOnSurfaceVariant.opacity(0.4)
                        )
                        .frame(height: 28)

                    // Dual mini progress bars — fixed 1/3 cell width, centered below the date.
                    // Green bar (top) = income; red bar (bottom) = expense.
                    if isCurrentMonth {
                        GeometryReader { geo in
                            let trackW = geo.size.width / 3
                            VStack(spacing: 2) {
                                // Income bar (green)
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(Color.designOnSurfaceVariant.opacity(0.12))
                                        .frame(width: trackW, height: 2.5)
                                    if incomeIntensity > 0 {
                                        RoundedRectangle(cornerRadius: 1.5)
                                            .fill(Color.designAccentGreen.opacity(0.7))
                                            .frame(width: trackW * incomeIntensity, height: 2.5)
                                    }
                                }
                                .frame(width: trackW, height: 2.5)
                                // Expense bar (red)
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(Color.designOnSurfaceVariant.opacity(0.12))
                                        .frame(width: trackW, height: 2.5)
                                    if expenseIntensity > 0 {
                                        RoundedRectangle(cornerRadius: 1.5)
                                            .fill(Color.designAccentRed.opacity(0.75))
                                            .frame(width: trackW * expenseIntensity, height: 2.5)
                                    }
                                }
                                .frame(width: trackW, height: 2.5)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .frame(height: 7)
                    } else {
                        Color.clear.frame(height: 7)
                    }
                }
            }
            .frame(height: 48)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .opacity(isCurrentMonth ? 1 : 0.35)
        .accessibilityHint(isCurrentMonth ? "" : String(localized: "点击切换到对应月份"))
    }
}
