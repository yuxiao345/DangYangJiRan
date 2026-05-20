import SwiftUI

struct CalendarStripView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedMonth: Date
    @Binding var selectedDay: Int?
    @Binding var isExpanded: Bool
    @Binding var dailyExpense: [Int: Decimal]
    @Binding var dailyIncome: [Int: Decimal]
    @Binding var maxDailyExpense: Decimal
    @Binding var monthlyIncome: Decimal
    @Binding var monthlyExpense: Decimal

    var daysInMonth: Int { selectedMonth.daysInMonth }
    var weekdayOffset: Int { selectedMonth.firstWeekdayOfMonth - 1 }
    var monthTitle: String { selectedMonth.monthDisplay }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    private let weekLabels = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        VStack(spacing: 6) {
            summaryBar

            if isExpanded {
                weekdayHeader
                monthGrid
            } else {
                weekdayHeader
                weekStrip
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .background(Color.designGlassBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth)?.startOfMonth ?? selectedMonth
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.designBodySmall.weight(.medium))
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(monthTitle)
                        .font(.designHeadlineMedium)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.designBodySmall)
                }
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth)?.startOfMonth ?? selectedMonth
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.designBodySmall.weight(.medium))
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 16) {
                Text("收 \(CurrencyFormatter.formatShort(amount: monthlyIncome, currencyCode: ""))")
                    .font(.designMonoDataSmall)
                    .foregroundStyle(Color.designAccentGreen)
                Text("支 \(CurrencyFormatter.formatShort(amount: monthlyExpense, currencyCode: ""))")
                    .font(.designMonoDataSmall)
                    .foregroundStyle(Color.designAccentRed)
            }
        }
    }

    // MARK: - Weekday Header

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekLabels, id: \.self) { label in
                Text(label)
                    .font(.designLabel)
                    .foregroundStyle(Color.designOnSurfaceVariant)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Week Strip (shows week of selected day, or current week)

    private var weekStrip: some View {
        let cal = Calendar.current
        let weekDates = displayWeekDates

        let selMonth = cal.component(.month, from: selectedMonth)
        let selYear = cal.component(.year, from: selectedMonth)
        let today = cal.component(.day, from: Date())
        let todayMonth = cal.component(.month, from: Date())
        let todayYear = cal.component(.year, from: Date())
        let isSelCurrentMonth = (todayMonth == selMonth && todayYear == selYear)

        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(weekDates, id: \.self) { date in
                let d = cal.component(.day, from: date)
                let dm = cal.component(.month, from: date)
                let dy = cal.component(.year, from: date)
                let inMonth = (dm == selMonth && dy == selYear)
                let expense = inMonth ? (dailyExpense[d] ?? 0) : 0
                let income = inMonth ? (dailyIncome[d] ?? 0) : 0
                let fraction = maxDailyExpense > 0 ? Double(truncating: (expense / maxDailyExpense) as NSNumber) : 0
                let isTodayDate = isSelCurrentMonth && d == today

                CalendarDayCell(
                    day: d,
                    expenseFraction: fraction,
                    hasIncome: income > 0,
                    isToday: isTodayDate,
                    isSelected: selectedDay == d && inMonth,
                    isCurrentMonth: inMonth
                ) {
                    if inMonth {
                        if selectedDay == d {
                            selectedDay = nil
                        } else {
                            selectedDay = d
                        }
                    }
                }
            }
        }
    }

    // MARK: - Month Grid

    private var monthGrid: some View {
        let cal = Calendar.current
        let today = cal.component(.day, from: Date())
        let todayMonth = cal.component(.month, from: Date())
        let todayYear = cal.component(.year, from: Date())
        let selMonth = cal.component(.month, from: selectedMonth)
        let selYear = cal.component(.year, from: selectedMonth)
        let isSelCurrentMonth = (todayMonth == selMonth && todayYear == selYear)

        let prevMonth = cal.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
        let prevDays = prevMonth.daysInMonth

        let totalCells = weekdayOffset + daysInMonth
        let trailingCells = (7 - (totalCells % 7)) % 7

        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(0..<weekdayOffset, id: \.self) { i in
                let d = prevDays - weekdayOffset + i + 1
                CalendarDayCell(
                    day: d,
                    expenseFraction: 0,
                    hasIncome: false,
                    isToday: false,
                    isSelected: false,
                    isCurrentMonth: false
                ) {}
            }

            ForEach(1...daysInMonth, id: \.self) { d in
                let expense = dailyExpense[d] ?? 0
                let income = dailyIncome[d] ?? 0
                let fraction = maxDailyExpense > 0 ? Double(truncating: (expense / maxDailyExpense) as NSNumber) : 0
                let isTodayDate = isSelCurrentMonth && d == today

                CalendarDayCell(
                    day: d,
                    expenseFraction: fraction,
                    hasIncome: income > 0,
                    isToday: isTodayDate,
                    isSelected: selectedDay == d,
                    isCurrentMonth: true
                ) {
                    if selectedDay == d {
                        selectedDay = nil
                    } else {
                        selectedDay = d
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isExpanded = false
                        }
                    }
                }
            }

            if trailingCells > 0 {
                ForEach(1...trailingCells, id: \.self) { d in
                    CalendarDayCell(
                        day: d,
                        expenseFraction: 0,
                        hasIncome: false,
                        isToday: false,
                        isSelected: false,
                        isCurrentMonth: false
                    ) {}
                }
            }
        }
    }

    // MARK: - Helpers

    private var displayWeekDates: [Date] {
        let cal = Calendar.current
        let refDate: Date
        if let day = selectedDay {
            let comps = cal.dateComponents([.year, .month], from: selectedMonth)
            var dayComps = DateComponents(year: comps.year, month: comps.month, day: day)
            refDate = cal.date(from: dayComps) ?? Date()
        } else {
            refDate = Date()
        }
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: refDate)) ?? refDate
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }
}
