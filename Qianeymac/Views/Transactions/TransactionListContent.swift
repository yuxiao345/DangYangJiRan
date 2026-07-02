import SwiftUI
@preconcurrency import CoreData

struct TransactionListOptions: OptionSet {
    let rawValue: Int
    static let hideCalendar   = TransactionListOptions(rawValue: 1 << 0)
    static let hideTypeFilter = TransactionListOptions(rawValue: 1 << 1)
    static let hideAddButton  = TransactionListOptions(rawValue: 1 << 2)
}

struct TransactionListContent: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @State private var transactions: [Transaction] = []
    @State private var filterType: TransactionType?
    @State private var selectedMonth: Date = Date().startOfMonth
    @State private var selectedDate: Date?
    @State private var transactionDays: Set<Int> = []
    @State private var dailyExpense: [Int: Decimal] = [:]
    @State private var dailyIncome: [Int: Decimal] = [:]
    @State private var maxDailyExpense: Decimal = 0
    @State private var maxDailyIncome: Decimal = 0
    @State private var hoveredDayID: String? = nil
    @State private var monthSlideDirection: Edge = .trailing
    @Namespace private var calendarNamespace

    var filterCategory: Category?
    var options: TransactionListOptions = []

    private let cal = Calendar.current
    private let weekdaySymbols = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        VStack(spacing: 0) {
            // Header + Calendar in glass card
            if !options.contains(.hideCalendar) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Button { shiftMonth(-1) } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            Text(selectedMonth.monthDisplay)
                                .font(.designHeadlineMedium)
                                .frame(width: 120)
                            Button { shiftMonth(1) } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                        }
                        Spacer()
                        if !options.contains(.hideTypeFilter) {
                            GlassSegmentedPicker(selection: $filterType)
                        }
                    }
                    .padding(.top, 6)

                    customCalendar
                        .id(selectedMonth)
                        .transition(.asymmetric(
                            insertion: .move(edge: monthSlideDirection).combined(with: .opacity),
                            removal: .move(edge: monthSlideDirection == .trailing ? .leading : .trailing).combined(with: .opacity)
                        ))
                }
                .glassSection()
                .padding(.horizontal, 12)
                .padding(.top, 12)
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    if transactions.isEmpty {
                        Text(selectedDate != nil ? "当天没有交易记录" : "本月暂无交易记录")
                            .font(.designBodyCaption).foregroundStyle(Color.designOnSurfaceVariant).padding(.top, 40)
                    } else {
                        ForEach(groupedByDate, id: \.key) { group in
                            Text(group.key).font(.designBodyCaption).foregroundStyle(Color.designOnSurfaceVariant)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                            ForEach(group.value) { t in
                                NavigationLink(value: t) {
                                    TransactionRowView(transaction: t)
                                        .padding(.vertical, 2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
        .designScreen()
        .navigationDestination(for: Transaction.self) { t in
            TransactionDetailContent(transaction: t)
        }
        .navigationTitle("")
        .onAppear(perform: load)
        .onChange(of: filterType) { _, _ in load() }
        .onChange(of: selectedMonth) { _, _ in
            selectedDate = nil
            load()
        }
        .onChange(of: selectedDate) { old, new in
            guard old != new else { return }
            load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in load() }
    }

    // MARK: - Custom Calendar (pure SwiftUI, no AppKit)

    private var customCalendar: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        return VStack(spacing: 0) {
            LazyVGrid(columns: cols, spacing: 2) {
                ForEach(weekdaySymbols, id: \.self) { sym in
                    Text(sym)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
                        .frame(maxWidth: .infinity)
                }
                ForEach(calendarDays) { d in
                    let expIntensity = maxDailyExpense > 0
                        ? Double(truncating: (d.expenseAmount / maxDailyExpense) as NSNumber)
                        : 0
                    let incIntensity = maxDailyIncome > 0
                        ? Double(truncating: (d.incomeAmount / maxDailyIncome) as NSNumber)
                        : 0
                    let isSelected = d.date != nil && selectedDate != nil && cal.isDate(d.date!, inSameDayAs: selectedDate!)
                    let currency = appContainer.currentLedger?.defaultCurrencyCode ?? "CNY"

                    Button {
                        if d.date != nil {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if let cur = selectedDate, cal.isDate(d.date!, inSameDayAs: cur) {
                                    selectedDate = nil
                                } else {
                                    selectedDate = d.date
                                }
                            }
                        }
                    } label: {
                        ZStack {
                            // Today / selected fill — light green tint
                            if isSelected || d.isToday {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.designAccentGreen.opacity(0.12))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 30)
                            }

                            // Hover / selected outline — green, matching progress bar fill
                            if (hoveredDayID == d.id || isSelected) && d.day > 0 {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.designAccentGreen, lineWidth: 1.5)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 30)
                            }

                            // Day number (centered)
                            Text(d.day > 0 ? "\(d.day)" : "")
                                .font(d.isToday ? .designBodySmall.bold() : .designBodySmall)
                                .foregroundStyle(
                                    d.day > 0 ? Color.designOnSurface : Color.clear
                                )

                            // Hover amount — positioned top‑left inside the cell, no background
                            if hoveredDayID == d.id, d.expenseAmount > 0 {
                                Text(CurrencyFormatter.formatAdaptive(amount: d.expenseAmount, currencyCode: currency))
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.designOnSurface)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(.leading, 3)
                                    .padding(.top, 1)
                            }

                            // Dual mini progress bars at the bottom — 1/6 cell width.
                            // Red bar (top) = income; green bar (bottom) = expense.
                            if d.day > 0 {
                                VStack {
                                    Spacer()
                                    GeometryReader { geo in
                                        let trackW = geo.size.width / 6
                                        VStack(spacing: 1.5) {
                                            // Income bar (red)
                                            ZStack(alignment: .leading) {
                                                RoundedRectangle(cornerRadius: 1)
                                                    .fill(Color.designOnSurfaceVariant.opacity(0.12))
                                                    .frame(width: trackW, height: 2)
                                                if incIntensity > 0 {
                                                    RoundedRectangle(cornerRadius: 1)
                                                        .fill(Color.designAccentRed.opacity(0.7))
                                                        .frame(width: trackW * incIntensity, height: 2)
                                                }
                                            }
                                            .frame(width: trackW, height: 2)
                                            // Expense bar (green)
                                            ZStack(alignment: .leading) {
                                                RoundedRectangle(cornerRadius: 1)
                                                    .fill(Color.designOnSurfaceVariant.opacity(0.12))
                                                    .frame(width: trackW, height: 2)
                                                if expIntensity > 0 {
                                                    RoundedRectangle(cornerRadius: 1)
                                                        .fill(Color.designAccentGreen.opacity(0.75))
                                                        .frame(width: trackW * expIntensity, height: 2)
                                                }
                                            }
                                            .frame(width: trackW, height: 2)
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                    .frame(height: 5.5)
                                    .padding(.bottom, 2)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                    }
                    .buttonStyle(.borderless)
                    .disabled(d.day == 0)
                    .onHover { hovering in
                        hoveredDayID = hovering ? d.id : nil
                    }
                }
            }
            .padding(.leading, 16).padding(.trailing, 0).padding(.top, 4).padding(.bottom, 4)
        }
    }

    private struct CalendarDay: Identifiable {
        /// Stable ID: year-month-day (or "pad-<N>" for padding cells).
        /// Must NOT use UUID() — causes infinite re-render loop with .onHover.
        let id: String
        let day: Int
        let date: Date?
        let isToday: Bool
        let hasTransactions: Bool
        let expenseAmount: Decimal
        let incomeAmount: Decimal
    }

    private var calendarDays: [CalendarDay] {
        let start = cal.date(from: cal.dateComponents([.year, .month], from: selectedMonth))!
        let range = cal.range(of: .day, in: .month, for: start)!
        let firstWeekday = cal.component(.weekday, from: start)
        let offset = (firstWeekday + 5) % 7
        var days: [CalendarDay] = []
        for i in 0..<offset { days.append(CalendarDay(id: "pad-\(i)", day: 0, date: nil, isToday: false, hasTransactions: false, expenseAmount: 0, incomeAmount: 0)) }
        for day in range {
            let date = cal.date(byAdding: .day, value: day - 1, to: start)!
            let y = cal.component(.year, from: date)
            let m = cal.component(.month, from: date)
            days.append(CalendarDay(id: "\(y)-\(m)-\(day)", day: day, date: date, isToday: cal.isDateInToday(date), hasTransactions: transactionDays.contains(day), expenseAmount: dailyExpense[day] ?? 0, incomeAmount: dailyIncome[day] ?? 0))
        }
        return days
    }

    private var groupedByDate: [(key: String, value: [Transaction])] {
        transactions.groupedByRelativeDate()
    }

    private func load() {
        guard let ledger = appContainer.currentLedger else { return }
        let start = selectedMonth
        guard let end = cal.date(byAdding: .month, value: 1, to: start) else { return }
        var filters = TransactionFilters()
        filters.dateRange = start..<end
        let all = (try? appContainer.transactionService.fetchTransactions(for: ledger, context: modelContext, filters: filters)) ?? []
        var result = all.deduplicatingTransfers()
        transactionDays = Set(result.filter { $0.type != .transfer }.map { cal.component(.day, from: $0.date) })

        // 每日热力图数据（排除转账）
        var expenseSum: [Int: Decimal] = [:]
        var incomeSum: [Int: Decimal] = [:]
        for t in result {
            let day = cal.component(.day, from: t.date)
            switch t.type {
            case .expense:
                expenseSum[day, default: 0] += abs(t.amount)
            case .income:
                incomeSum[day, default: 0] += t.amount
            default:
                break
            }
        }
        dailyExpense = expenseSum
        dailyIncome = incomeSum
        maxDailyExpense = expenseSum.values.max() ?? 0
        maxDailyIncome = incomeSum.values.max() ?? 0
        if let type = filterType { result = result.filter { $0.type == type } }
        if let date = selectedDate { result = result.filter { cal.isDate($0.date, inSameDayAs: date) } }
        if let cat = filterCategory { result = result.filter { $0.category?.id == cat.id } }
        transactions = result
    }

    private func shiftMonth(_ delta: Int) {
        monthSlideDirection = delta > 0 ? .trailing : .leading
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            selectedMonth = cal.date(byAdding: .month, value: delta, to: selectedMonth)?.startOfMonth ?? selectedMonth
        }
    }
}

// MARK: - Glass Segmented Picker

private struct GlassSegmentedPicker: View {
    @Binding var selection: TransactionType?
    @Namespace private var animation

    private let options: [(label: String, type: TransactionType?)] = {
        [(String(localized: "全部"), nil)]
        + TransactionType.allCases.map { ($0.displayName, $0) }
    }()

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.label) { option in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selection = option.type
                    }
                } label: {
                    Text(option.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            selection == option.type
                                ? Color.designOnSurface
                                : Color.designOnSurfaceVariant.opacity(0.7)
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                        .background {
                            if selection == option.type {
                                Capsule()
                                    .fill(Color.white.opacity(0.06))
                                    .background(.regularMaterial, in: Capsule())
                                    .overlay {
                                        Capsule()
                                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                    }
                                    .matchedGeometryEffect(id: "glassPill", in: animation)
                                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background {
            Capsule()
                .fill(Color.designGlassBg)
        }
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
                .padding(1)
        }
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }
}
