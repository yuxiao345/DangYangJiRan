import SwiftUI

struct CalendarDayCell: View {
    let day: Int
    let hasTransaction: Bool
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

                    if isCurrentMonth && hasTransaction {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.designPrimaryContainer)
                            .frame(width: 4, height: 4)
                    } else {
                        Color.clear.frame(height: 4)
                    }
                }
            }
            .frame(height: 48)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!isCurrentMonth)
        .opacity(isCurrentMonth ? 1 : 0.35)
    }
}
