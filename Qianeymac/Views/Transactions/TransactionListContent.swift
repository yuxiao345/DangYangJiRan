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
                            if let date = d.date, let sd = selectedDate, cal.isDate(date, inSameDayAs: sd) {
                                Circle()
                                    .fill(.regularMaterial)
                                    .background(Circle().fill(Color.designAccentGreen.opacity(0.3)))
                                    .frame(height: 28)
                                    .matchedGeometryEffect(id: "selectedDay", in: calendarNamespace)
                            }
                            if d.isToday, selectedDate == nil || (d.date != nil && !cal.isDate(d.date!, inSameDayAs: selectedDate!)) {
                                Circle().stroke(Color.designAccentGreen, lineWidth: 1.5).frame(height: 28)
                            }
                            VStack(spacing: 0) {
                                Text(d.day > 0 ? "\(d.day)" : "")
                                    .font(d.isToday ? .designBodySmall.bold() : .designBodySmall)
                                    .foregroundStyle(
                                        d.date != nil && selectedDate != nil && cal.isDate(d.date!, inSameDayAs: selectedDate!)
                                            ? Color.designOnSurface : d.day > 0 ? Color.designOnSurface : Color.clear
                                    )
                                if d.hasTransactions, d.day > 0 {
                                    Circle().fill(Color.designAccentGreen.opacity(0.5)).frame(width: 3, height: 3)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                    }
                    .buttonStyle(.borderless)
                    .disabled(d.day == 0)
                }
            }
            .padding(.leading, 16).padding(.trailing, 0).padding(.top, 4).padding(.bottom, 4)
        }
    }

    private struct CalendarDay: Identifiable {
        let id = UUID()
        let day: Int
        let date: Date?
        let isToday: Bool
        let hasTransactions: Bool
    }

    private var calendarDays: [CalendarDay] {
        let start = cal.date(from: cal.dateComponents([.year, .month], from: selectedMonth))!
        let range = cal.range(of: .day, in: .month, for: start)!
        let firstWeekday = cal.component(.weekday, from: start)
        let offset = (firstWeekday + 5) % 7
        var days: [CalendarDay] = []
        for _ in 0..<offset { days.append(CalendarDay(day: 0, date: nil, isToday: false, hasTransactions: false)) }
        for day in range {
            let date = cal.date(byAdding: .day, value: day - 1, to: start)!
            days.append(CalendarDay(day: day, date: date, isToday: cal.isDateInToday(date), hasTransactions: transactionDays.contains(day)))
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
