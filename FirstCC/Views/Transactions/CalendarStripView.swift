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
                    Text(CurrencyFormatter.formatShort(amount: monthlyIncome, currencyCode: ""))
                        .font(.designMonoDataSmall)
                        .foregroundStyle(Color.designPrimaryFixedDim)
                        .frame(alignment: .leading)
                }
                HStack(spacing: 0) {
                    Text("支")
                        .font(.designLabel)
                        .foregroundStyle(Color.designAccentRed)
                        .frame(width: 16, alignment: .leading)
                    Text(CurrencyFormatter.formatShort(amount: monthlyExpense, currencyCode: ""))
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
                        if selectedDay == d { selectedDay = nil }
                        else { selectedDay = d }
                    }
                )
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
                    hasTransaction: false,
                    isToday: false,
                    isSelected: false,
                    isCurrentMonth: false,
                    onTap: {}
                )
            }

            ForEach(1...daysInMonth, id: \.self) { d in
                let hasTx = (dailyExpense[d] ?? 0) > 0 || (dailyIncome[d] ?? 0) > 0
                let isTodayDate = isSelCurrentMonth && d == today

                CalendarDayCell(
                    day: d,
                    hasTransaction: hasTx,
                    isToday: isTodayDate,
                    isSelected: selectedDay == d,
                    isCurrentMonth: true,
                    onTap: {
                        if selectedDay == d {
                            selectedDay = nil
                        } else {
                            selectedDay = d
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isExpanded = false
                            }
                        }
                    }
                )
            }

            if trailingCells > 0 {
                ForEach(1...trailingCells, id: \.self) { d in
                    CalendarDayCell(
                        day: d,
                        hasTransaction: false,
                        isToday: false,
                        isSelected: false,
                        isCurrentMonth: false,
                        onTap: {}
                    )
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
        // Force week to start on Monday, regardless of Calendar locale
        let weekday = cal.component(.weekday, from: refDate) // 1=Sun..7=Sat
        let daysFromMonday = (weekday + 5) % 7
        let monday = cal.date(byAdding: .day, value: -daysFromMonday, to: cal.startOfDay(for: refDate)) ?? refDate
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
    }
}
