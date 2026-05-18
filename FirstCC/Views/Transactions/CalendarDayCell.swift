import SwiftUI

struct CalendarDayCell: View {
    let day: Int
    let expenseFraction: Double
    let hasIncome: Bool
    let isToday: Bool
    let isSelected: Bool
    let isCurrentMonth: Bool
    let onTap: () -> Void

    private var foregroundColor: Color {
        isCurrentMonth ? .primary : Color.secondary.opacity(0.5)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    if isToday {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 30, height: 30)
                    } else if isSelected {
                        Circle()
                            .fill(Color.primary.opacity(0.85))
                            .frame(width: 30, height: 30)
                    }

                    Text("\(day)")
                        .font(.caption)
                        .fontWeight(isToday || isSelected ? .semibold : .regular)
                        .foregroundColor(isToday || isSelected ? .white : foregroundColor)
                        .frame(width: 30, height: 30)

                    if hasIncome {
                        Circle()
                            .fill(.green)
                            .frame(width: 5, height: 5)
                            .offset(x: 1, y: -1)
                    }
                }

                Spacer(minLength: 0)

                if isCurrentMonth, expenseFraction > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.12))
                                .frame(height: 3)
                            Capsule()
                                .fill(Color.expenseHeat(fraction: expenseFraction))
                                .frame(width: max(4, geo.size.width * expenseFraction), height: 3)
                        }
                    }
                    .frame(height: 3)
                    .padding(.horizontal, 3)
                    .padding(.bottom, 4)
                } else {
                    Color.clear.frame(height: 7)
                }
            }
            .opacity(isCurrentMonth ? 1 : 0.35)
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .disabled(!isCurrentMonth)
    }
}
