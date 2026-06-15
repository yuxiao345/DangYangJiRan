import SwiftUI
@preconcurrency import CoreData

struct TransactionListContent: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @Binding var selection: Transaction?
    @State private var transactions: [Transaction] = []
    @State private var filterType: TransactionType?
    @State private var selectedMonth: Date = Date().startOfMonth
    @State private var selectedDate: Date?
    @State private var transactionDays: Set<Int> = []

    private let weekdaySymbols = ["一", "二", "三", "四", "五", "六", "日"]
    private let cal = Calendar.current
    private let cellSize: CGFloat = 26

    var body: some View {
        VStack(spacing: 0) {
            miniCalendar
            Divider()
            ScrollView {
                LazyVStack(spacing: 6) {
                    if transactions.isEmpty {
                        Text(selectedDate != nil ? "当天没有交易记录" : "本月暂无交易记录")
                            .font(.caption).foregroundStyle(Color.designOnSurfaceVariant).padding(.top, 40)
                    } else {
                        ForEach(groupedByDate, id: \.key) { group in
                            Text(group.key).font(.caption).foregroundStyle(Color.designOnSurfaceVariant)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                            ForEach(group.value) { t in
                                Button {
                                    selection = t
                                } label: {
                                    TransactionRowView(transaction: t)
                                        .padding(.vertical, 2)
                                        .background(selection?.id == t.id ? Color.accentColor.opacity(0.08) : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(12)
            }
            .designScreen()
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("类型", selection: $filterType) {
                    Text("全部").tag(nil as TransactionType?)
                    ForEach([TransactionType.expense, .income, .transfer, .lending], id: \.self) { t in
                        Text(t.displayName).tag(t as TransactionType?)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 4) {
                    Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    Text(selectedMonth.monthDisplay).font(.headline)
                    Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: filterType) { _, _ in load() }
        .onChange(of: selectedMonth) { _, _ in selectedDate = nil; load() }
        .onChange(of: selectedDate) { _, _ in load() }
        .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in load() }
    }

    private var miniCalendar: some View {
        let cols = Array(repeating: GridItem(.fixed(cellSize), spacing: 1), count: 7)
        return VStack(spacing: 0) {
            LazyVGrid(columns: cols, spacing: 1) {
                ForEach(weekdaySymbols, id: \.self) { sym in
                    Text(sym)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
                        .frame(width: cellSize, height: 16)
                }
                ForEach(calendarDays) { d in
                    Button {
                        if d.date != nil {
                            if let cur = selectedDate, cal.isDate(d.date!, inSameDayAs: cur) {
                                selectedDate = nil
                            } else {
                                selectedDate = d.date
                            }
                        }
                    } label: {
                        ZStack {
                            if let date = d.date, let sd = selectedDate, cal.isDate(date, inSameDayAs: sd) {
                                Circle().fill(Color.designAccentGreen).frame(width: cellSize - 2, height: cellSize - 2)
                            }
                            if d.isToday, selectedDate == nil || (d.date != nil && !cal.isDate(d.date!, inSameDayAs: selectedDate!)) {
                                Circle().stroke(Color.designAccentGreen, lineWidth: 1.5).frame(width: cellSize - 2, height: cellSize - 2)
                            }
                            VStack(spacing: 0) {
                                Text(d.day > 0 ? "\(d.day)" : "")
                                    .font(.system(size: 11, weight: d.isToday ? .semibold : .regular))
                                    .foregroundStyle(
                                        d.date != nil && selectedDate != nil && cal.isDate(d.date!, inSameDayAs: selectedDate!)
                                            ? Color.white : d.day > 0 ? Color.designOnSurface : Color.clear
                                    )
                                if d.hasTransactions, d.day > 0 {
                                    Circle().fill(Color.designAccentGreen.opacity(0.5)).frame(width: 2, height: 2)
                                }
                            }
                        }
                        .frame(width: cellSize, height: cellSize)
                    }
                    .buttonStyle(.plain)
                    .disabled(d.day == 0)
                }
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)
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
        transactions = result
    }

    private func shiftMonth(_ delta: Int) {
        selectedMonth = cal.date(byAdding: .month, value: delta, to: selectedMonth)?.startOfMonth ?? selectedMonth
    }
}

