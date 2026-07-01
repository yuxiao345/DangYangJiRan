import SwiftUI

struct CalendarStripView: View {
    @Environment(\.managedObjectContext) private var modelContext
    @Binding var selectedMonth: Date
    @Binding var selectedDay: Int?
    @Binding var isExpanded: Bool
    @Binding var dailyExpense: [Int: Decimal]
    @Binding var dailyIncome: [Int: Decimal]
    @Binding var maxDailyExpense: Decimal
    @Binding var monthlyIncome: Decimal
    @Binding var monthlyExpense: Decimal

    /// weekdayOffset: how many empty cells before day 1, assuming columns start from Monday.
    /// Calendar.weekday: 1=Sun 2=Mon … 7=Sat. Column 0 = Mon, so offset = (weekday-2+7)%7.
    var daysInMonth: Int { selectedMonth.daysInMonth }
    var weekdayOffset: Int { (selectedMonth.firstWeekdayOfMonth - 2 + 7) % 7 }
    var monthTitle: String { selectedMonth.monthDisplay }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    private let weekLabels = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        VStack(spacing: 0) {
            summaryBar
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)

            weekdayHeader
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            if isExpanded {
                monthGrid
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            } else {
                weekStrip
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .background(.ultraThinMaterial)
        .background(Color.designGlassBg)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.designGlassBorderHighlight, lineWidth: 1)
        )
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth)?.startOfMonth ?? selectedMonth
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.designBodySmall.weight(.medium))
                    .foregroundStyle(Color.designOnSurfaceVariant)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                Text(monthTitle)
                    .font(.custom("SpaceGrotesk-SemiBold", fixedSize: 20))
                    .foregroundStyle(Color.designOnSurface)
                    .tracking(-0.02)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth)?.startOfMonth ?? selectedMonth
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.designBodySmall.weight(.medium))
                    .foregroundStyle(Color.designOnSurfaceVariant)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 0) {
                    Text("收")
                        .font(.designLabel)
                        .foregroundStyle(Color.designPrimaryFixedDim)
                        .frame(width: 16, alignment: .leading)
                    Text(CurrencyFormatter.formatAdaptive(amount: monthlyIncome, currencyCode: ""))
                        .font(.designMonoDataSmall)
                        .foregroundStyle(Color.designPrimaryFixedDim)
                        .frame(alignment: .leading)
                }
                HStack(spacing: 0) {
                    Text("支")
                        .font(.designLabel)
                        .foregroundStyle(Color.designAccentRed)
                        .frame(width: 16, alignment: .leading)
                    Text(CurrencyFormatter.formatAdaptive(amount: monthlyExpense, currencyCode: ""))
                        .font(.designMonoDataSmall)
                        .foregroundStyle(Color.designAccentRed)
                        .frame(alignment: .leading)
                }
            }
        }
    }

    // MARK: - Weekday Header

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekLabels, id: \.self) { label in
                Text(label)
                    .font(.custom("SpaceGrotesk-Bold", fixedSize: 11))
                    .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
                    .tracking(1.0)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Week Strip

    private var weekStrip: some View {
        let weekDates = displayWeekDates
        let cal = Calendar.current
        let selMonth = cal.component(.month, from: selectedMonth)
        let selYear = cal.component(.year, from: selectedMonth)
        let today = cal.component(.day, from: Date())
        let todayMonth = cal.component(.month, from: Date())
        let todayYear = cal.component(.year, from: Date())
        let isSelCurrentMonth = (todayMonth == selMonth && todayYear == selYear)

        return HStack(spacing: 2) {
            ForEach(weekDates, id: \.self) { date in
                let d = cal.component(.day, from: date)
                let dm = cal.component(.month, from: date)
                let dy = cal.component(.year, from: date)
                let inMonth = (dm == selMonth && dy == selYear)
                let isTodayDate = isSelCurrentMonth && d == today && inMonth
                let isSel = selectedDay == d && inMonth
                let hasTx = inMonth && ((dailyExpense[d] ?? 0) > 0 || (dailyIncome[d] ?? 0) > 0)

                CalendarDayCell(
                    day: d,
                    hasTransaction: hasTx,
                    isToday: isTodayDate,
                    isSelected: isSel,
                    isCurrentMonth: inMonth,
                    onTap: {
                        if inMonth {
                            handleDayTap(day: d, isCurrentMonth: true, targetMonth: selectedMonth)
                        } else {
                            let comps = DateComponents(year: dy, month: dm, day: 1)
                            if let target = cal.date(from: comps) {
                                handleDayTap(day: d, isCurrentMonth: false, targetMonth: target)
                            } else {
                                // Fallback: navigate via relative month offset from selectedMonth
                                let offset = dm >= selMonth ? 1 : -1
                                let target = selectedMonth.adding(.month, value: offset).startOfMonth
                                handleDayTap(day: d, isCurrentMonth: false, targetMonth: target)
                            }
                        }
                    }
                )
            }
        }
    }

    // MARK: - Month Grid

    /// Unified cell model: single data source → single ForEach, no ID collisions.
    private struct GridCell: Identifiable {
        let id: String
        let day: Int
        let isCurrentMonth: Bool
        let monthOffset: Int  // -1 prev, 0 current, +1 next
    }

    private var monthCells: [GridCell] {
        let offset = weekdayOffset
        let days = daysInMonth
        let totalCells = offset + days
        let trailing = (7 - (totalCells % 7)) % 7
        let cal = Calendar.current
        let prevMonth = cal.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
        let prevDays = prevMonth.daysInMonth

        var cells: [GridCell] = []

        // Leading padding: show actual dates from previous month
        for i in 0..<offset {
            let day = prevDays - offset + i + 1
            cells.append(GridCell(id: "pad-\(i)", day: day, isCurrentMonth: false, monthOffset: -1))
        }
        // Current month
        for d in 1...days {
            cells.append(GridCell(id: "d-\(d)", day: d, isCurrentMonth: true, monthOffset: 0))
        }
        // Trailing padding: show sequential dates from next month
        for i in 0..<trailing {
            cells.append(GridCell(id: "trail-\(i)", day: i + 1, isCurrentMonth: false, monthOffset: 1))
        }
        return cells
    }

    private var monthGrid: some View {
        let cal = Calendar.current
        let today = cal.component(.day, from: Date())
        let todayMonth = cal.component(.month, from: Date())
        let todayYear = cal.component(.year, from: Date())
        let selMonth = cal.component(.month, from: selectedMonth)
        let selYear = cal.component(.year, from: selectedMonth)
        let isSelCurrentMonth = (todayMonth == selMonth && todayYear == selYear)
        let cells = monthCells

        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(cells) { cell in
                let hasTx = cell.isCurrentMonth && ((dailyExpense[cell.day] ?? 0) > 0 || (dailyIncome[cell.day] ?? 0) > 0)
                let isTodayDate = cell.isCurrentMonth && isSelCurrentMonth && cell.day == today

                CalendarDayCell(
                    day: cell.day,
                    hasTransaction: hasTx,
                    isToday: isTodayDate,
                    isSelected: cell.isCurrentMonth && selectedDay == cell.day,
                    isCurrentMonth: cell.isCurrentMonth,
                    onTap: {
                        if cell.isCurrentMonth {
                            let wasSelected = (selectedDay == cell.day)
                            handleDayTap(day: cell.day, isCurrentMonth: true, targetMonth: selectedMonth)
                            if !wasSelected {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    isExpanded = false
                                }
                            }
                        } else {
                            // Adjacent-month tap: navigate to that month.
                            // Grid stays expanded so the user can continue browsing the new month.
                            // (Current-month taps collapse to weekStrip — that asymmetry is intentional.)
                            let target = selectedMonth.adding(.month, value: cell.monthOffset).startOfMonth
                            handleDayTap(day: cell.day, isCurrentMonth: false, targetMonth: target)
                        }
                    }
                )
            }
        }
    }

    // MARK: - Helpers

    /// Shared tap handler for both weekStrip and monthGrid.
    private func handleDayTap(day: Int, isCurrentMonth: Bool, targetMonth: Date) {
        if isCurrentMonth {
            selectedDay = (selectedDay == day) ? nil : day
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedMonth = targetMonth
                selectedDay = day
            }
        }
    }

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
        // Force week to start on Monday, regardless of Calendar locale
        let weekday = cal.component(.weekday, from: refDate) // 1=Sun..7=Sat
        let daysFromMonday = (weekday + 5) % 7
        let monday = cal.date(byAdding: .day, value: -daysFromMonday, to: cal.startOfDay(for: refDate)) ?? refDate
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
    }
}
