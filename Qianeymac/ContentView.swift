import SwiftUI
@preconcurrency import CoreData

// MARK: - Navigation

enum MacNavItem: String, CaseIterable, Identifiable {
    case dashboard = "总览"
    case accounts = "账户"
    case transactions = "流水"
    case reports = "报表"
    case settings = "设置"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: "rectangle.3.group"
        case .accounts: "creditcard"
        case .transactions: "list.bullet"
        case .reports: "chart.bar"
        case .settings: "gearshape"
        }
    }
}

// MARK: - Settings Navigation

enum SettingsMainItem: String, CaseIterable, Identifiable {
    case appearance = "外观"
    case ledgers = "账本"
    case about = "关于"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .appearance: "paintbrush"
        case .ledgers: "books.vertical"
        case .about: "info.circle"
        }
    }
}

enum LedgerSettingsItem: String, CaseIterable, Identifiable {
    case categories = "分类管理"
    case members = "成员管理"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .categories: "square.grid.2x2"
        case .members: "person.2"
        }
    }
}

// MARK: - Main Split View

struct MainSplitView: View {
    @Environment(AppContainer.self) private var appContainer
    @State private var selection: MacNavItem = .dashboard
    @State private var selectedAccount: Account?
    @State private var selectedTransaction: Transaction?
    @State private var settingsMainSelection: SettingsMainItem?
    @State private var settingsSelectedLedger: Ledger?
    @State private var settingsLedgerSubSelection: LedgerSettingsItem?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } content: {
            contentColumn
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 420)
        } detail: {
            detailColumn
        }
        .navigationTitle(appContainer.currentLedger?.name ?? "小金库")
        .onReceive(NotificationCenter.default.publisher(for: .macMenuNavigate)) { notif in
            if let item = notif.object as? MacNavItem {
                selection = item
                selectedAccount = nil
                selectedTransaction = nil
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List {
            ForEach(MacNavItem.allCases) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .padding(.vertical, 2)
                    .background(selection == item ? Color.accentColor.opacity(0.15) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onTapGesture {
                        if selection != item {
                            selection = item
                            selectedAccount = nil
                            selectedTransaction = nil
                        }
                    }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Content Column

    @ViewBuilder
    private var contentColumn: some View {
        switch selection {
        case .dashboard:
            DashboardContentColumn()
        case .accounts:
            AccountListContent(selection: $selectedAccount)
        case .transactions:
            TransactionListContent(selection: $selectedTransaction)
        case .reports:
            ReportTypeContent()
        case .settings:
            SettingsContentColumn(
                mainSelection: $settingsMainSelection,
                selectedLedger: $settingsSelectedLedger,
                ledgerSubSelection: $settingsLedgerSubSelection
            )
        }
    }

    // MARK: - Detail Column

    @ViewBuilder
    private var detailColumn: some View {
        switch selection {
        case .dashboard:
            DashboardDetailColumn()
        case .accounts:
            if let account = selectedAccount {
                AccountDetailContent(account: account)
            } else {
                EmptySelectionView(message: "选择账户查看详情")
            }
        case .transactions:
            if let transaction = selectedTransaction {
                TransactionDetailContent(transaction: transaction)
            } else {
                EmptySelectionView(message: "选择交易查看详情")
            }
        case .reports:
            ReportDetailContent()
        case .settings:
            SettingsDetailColumn(
                mainSelection: $settingsMainSelection,
                selectedLedger: $settingsSelectedLedger,
                ledgerSubSelection: $settingsLedgerSubSelection
            )
        }
    }
}

// MARK: - Empty Selection

struct EmptySelectionView: View {
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cursorarrow.motionlines")
                .font(.system(size: 36))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.3))
            Text(message).foregroundStyle(Color.designOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .designScreen()
    }
}

// MARK: - Dashboard (Content: 总资产+收支 | Detail: 最近交易)

struct DashboardContentColumn: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @State private var viewModel = DashboardViewModel(
        accountService: AccountServiceImpl(), transactionService: TransactionServiceImpl()
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                balanceCard
                incomeCard
                expenseCard
            }
            .padding(16)
        }
        .designScreen()
        .onAppear { viewModel.load(context: modelContext) }
        .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in
            viewModel.load(context: modelContext)
        }
        .onChange(of: appContainer.currentLedger?.id) { _, _ in
            viewModel.load(context: modelContext)
        }
    }

    private var currencyCode: String {
        appContainer.currentLedger?.defaultCurrencyCode ?? "CNY"
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("总资产").font(.caption).foregroundStyle(Color.designOnSurfaceVariant)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(CurrencyFormatter.currencySymbol(for: currencyCode))
                    .font(.title3).foregroundStyle(Color.designPrimaryFixedDim)
                Text(CurrencyFormatter.formatDecimal(amount: viewModel.totalBalance, fractionDigits: 2))
                    .font(.title2.weight(.bold)).foregroundStyle(Color.designOnSurface)
            }
            if let change = viewModel.balanceChange {
                Label(change >= 0 ? "较上月增长" : "较上月减少",
                      systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption)
                    .foregroundStyle(change >= 0 ? Color.designPrimaryFixedDim : Color.designAccentRed)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 12)
    }

    private var incomeCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("本月收入").font(.caption).foregroundStyle(Color.designOnSurfaceVariant)
            Text(CurrencyFormatter.formatDecimal(amount: viewModel.monthlyIncome, currencyCode: currencyCode))
                .font(.title3.weight(.semibold)).foregroundStyle(Color.designPrimaryFixedDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 12)
    }

    private var expenseCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("本月支出").font(.caption).foregroundStyle(Color.designOnSurfaceVariant)
            Text(CurrencyFormatter.formatDecimal(amount: viewModel.monthlyExpense, currencyCode: currencyCode))
                .font(.title3.weight(.semibold)).foregroundStyle(Color.designAccentRed)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 12)
    }
}

struct DashboardDetailColumn: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @State private var viewModel = DashboardViewModel(
        accountService: AccountServiceImpl(), transactionService: TransactionServiceImpl()
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("最近交易").font(.headline).foregroundStyle(Color.designOnSurface)
                if viewModel.recentTransactions.isEmpty {
                    Text("本月暂无交易记录")
                        .foregroundStyle(Color.designOnSurfaceVariant).padding(.vertical, 40).frame(maxWidth: .infinity)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.recentTransactions) { t in
                            TransactionRowView(transaction: t)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .designScreen()
        .onAppear { viewModel.load(context: modelContext) }
        .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in
            viewModel.load(context: modelContext)
        }
        .onChange(of: appContainer.currentLedger?.id) { _, _ in
            viewModel.load(context: modelContext)
        }
    }
}

// MARK: - Accounts (Content + Detail)

struct AccountListContent: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @Binding var selection: Account?
    @State private var accounts: [Account] = []
    @State private var balances: [UUID: Decimal] = [:]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(groupedAccounts, id: \.key) { group in
                    Text(group.key).font(.caption).foregroundStyle(Color.designOnSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(group.value) { account in
                        accountRow(account)
                    }
                }
                if accounts.isEmpty {
                    Text("暂无账户").foregroundStyle(Color.designOnSurfaceVariant).padding(.top, 60)
                }
            }
            .padding(16)
        }
        .designScreen()
        .onAppear(perform: load)
        .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in load() }
    }

    private var groupedAccounts: [(key: String, value: [Account])] {
        Dictionary(grouping: accounts) { $0.type.displayName }
            .sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    private func accountRow(_ account: Account) -> some View {
        Button {
            selection = account
        } label: {
            HStack {
                Label(account.name, systemImage: account.type.systemIcon)
                Spacer()
                Text(CurrencyFormatter.formatDecimal(amount: balances[account.id] ?? 0, currencyCode: account.currencyCode))
                    .foregroundStyle((balances[account.id] ?? 0) >= 0 ? Color.designPrimaryFixedDim : Color.designAccentRed)
            }
            .padding(10)
            .background(selection?.id == account.id ? Color.accentColor.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func load() {
        guard let ledger = appContainer.currentLedger else { return }
        accounts = (try? appContainer.accountService.fetchAccounts(for: ledger, context: modelContext)) ?? []
        for a in accounts {
            balances[a.id] = appContainer.accountService.calculateBalance(for: a, context: modelContext)
        }
    }
}

struct AccountDetailContent: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    let account: Account
    @State private var transactions: [Transaction] = []
    @State private var balance: Decimal = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.name).font(.title2.weight(.semibold)).foregroundStyle(Color.designOnSurface)
                    Text(account.type.displayName).font(.caption).foregroundStyle(Color.designOnSurfaceVariant)
                }
                HStack(spacing: 4) {
                    Text(CurrencyFormatter.currencySymbol(for: account.currencyCode))
                        .font(.title3).foregroundStyle(Color.designPrimaryFixedDim)
                    Text(CurrencyFormatter.formatDecimal(amount: balance, fractionDigits: 2))
                        .font(.largeTitle.weight(.bold)).foregroundStyle(Color.designOnSurface)
                }
                Divider()
                Text("交易记录").font(.headline).foregroundStyle(Color.designOnSurface)
                if transactions.isEmpty {
                    Text("暂无交易记录")
                        .foregroundStyle(Color.designOnSurfaceVariant).padding(.top, 20)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(transactions) { t in
                            TransactionRowView(transaction: t)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .designScreen()
        .onAppear(perform: load)
    }

    private func load() {
        balance = appContainer.accountService.calculateBalance(for: account, context: modelContext)
        transactions = (try? appContainer.transactionService.fetchTransactions(
            for: appContainer.currentLedger!, context: modelContext, filters: TransactionFilters()
        ))?.filter { $0.account?.id == account.id || $0.toAccount?.id == account.id }
            .sorted { $0.date > $1.date } ?? []
    }
}

// MARK: - Transactions (Content + Detail)

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

struct TransactionDetailContent: View {
    let transaction: Transaction

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(transaction.type.displayName).font(.title2.weight(.semibold)).foregroundStyle(Color.designOnSurface)
                    Spacer()
                    Text(CurrencyFormatter.formatDecimal(amount: transaction.amount, currencyCode: transaction.currencyCode))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(transaction.amount >= 0 ? Color.designPrimaryFixedDim : Color.designAccentRed)
                }
                Divider()
                detailRow("日期", transaction.date.formatted(date: .long, time: .omitted))
                if let account = transaction.account {
                    detailRow("账户", account.name)
                }
                if let toAccount = transaction.toAccount {
                    detailRow(transaction.amount >= 0 ? "来源" : "去向", toAccount.name)
                }
                if let category = transaction.category {
                    detailRow("分类", category.name)
                }
                if let note = transaction.note, !note.isEmpty {
                    detailRow("备注", note)
                }
                if let project = transaction.project {
                    detailRow("项目", project.name)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .designScreen()
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.caption).foregroundStyle(Color.designOnSurfaceVariant).frame(width: 50, alignment: .leading)
            Text(value).font(.body).foregroundStyle(Color.designOnSurface)
        }
    }
}

// MARK: - Reports (Content + Detail)

enum ReportType: String, CaseIterable, Identifiable {
    case trend = "收支趋势"
    case category = "分类占比"
    case assets = "资产变化"
    case budget = "预算执行"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .trend: "chart.line.uptrend.xyaxis"
        case .category: "chart.pie"
        case .assets: "chart.bar"
        case .budget: "gauge.with.dots.needle.33percent"
        }
    }
}

struct ReportTypeContent: View {
    @State private var selectedReport: ReportType?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        List(ReportType.allCases, selection: $selectedReport) { report in
            Label(report.rawValue, systemImage: report.icon)
                .padding(.vertical, 4)
        }
        .scrollContentBackground(.hidden)
        .designScreen()
    }
}

struct ReportDetailContent: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 48))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
            Text("报表功能即将上线").font(.title3).foregroundStyle(Color.designOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .designScreen()
    }
}

// MARK: - Settings Content Column

struct SettingsContentColumn: View {
    @Binding var mainSelection: SettingsMainItem?
    @Binding var selectedLedger: Ledger?
    @Binding var ledgerSubSelection: LedgerSettingsItem?

    var body: some View {
        Group {
            if let ledger = selectedLedger {
                ledgerSubList(ledger)
            } else {
                mainList
            }
        }
    }

    // MARK: Main settings list

    private var mainList: some View {
        List(selection: $mainSelection) {
            ForEach(SettingsMainItem.allCases) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .padding(.vertical, 3)
                    .tag(item)
            }
        }
        .scrollContentBackground(.hidden)
        .designScreen()
    }

    // MARK: Ledger sub-items list

    private func ledgerSubList(_ ledger: Ledger) -> some View {
        List(selection: $ledgerSubSelection) {
            Section {
                ForEach(LedgerSettingsItem.allCases) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .padding(.vertical, 3)
                        .tag(item)
                }
            } header: {
                HStack {
                    Button {
                        self.selectedLedger = nil
                        self.ledgerSubSelection = nil
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    Text(ledger.name).font(.headline)
                }
                .padding(.bottom, 4)
            }
        }
        .scrollContentBackground(.hidden)
        .designScreen()
    }
}

// MARK: - Settings Detail Column

struct SettingsDetailColumn: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @Binding var mainSelection: SettingsMainItem?
    @Binding var selectedLedger: Ledger?
    @Binding var ledgerSubSelection: LedgerSettingsItem?

    var body: some View {
        Group {
            if let main = mainSelection {
                switch main {
                case .appearance:
                    AppearanceSettingsView()
                case .ledgers:
                    if let ledger = selectedLedger, let sub = ledgerSubSelection {
                        ledgerSubDetail(ledger: ledger, sub: sub)
                    } else {
                        LedgerListSettingsView(onSelect: { ledger in
                            selectedLedger = ledger
                            ledgerSubSelection = nil
                        })
                    }
                case .about:
                    AboutSettingsView()
                }
            } else {
                EmptySelectionView(message: "选择设置项")
            }
        }
    }

    @ViewBuilder
    private func ledgerSubDetail(ledger: Ledger, sub: LedgerSettingsItem) -> some View {
        switch sub {
        case .categories:
            MacCategoryListView(ledger: ledger)
        case .members:
            MacMemberListView(ledger: ledger)
        }
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("外观").font(.headline).foregroundStyle(Color.designOnSurface)
                    Picker("外观模式", selection: $appearanceMode) {
                        Text("跟随系统").tag(AppearanceMode.system)
                        Text("浅色").tag(AppearanceMode.light)
                        Text("深色").tag(AppearanceMode.dark)
                    }
                    .pickerStyle(.segmented).frame(maxWidth: 300)
                }
                .padding(24).glassCard(cornerRadius: 16)
            }
            .padding(32).frame(maxWidth: 600)
        }
        .designScreen()
    }
}

// MARK: - About Settings

struct AboutSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("关于").font(.headline).foregroundStyle(Color.designOnSurface)
                    Text("钱伲 — 家庭记账与资产管理")
                        .foregroundStyle(Color.designOnSurfaceVariant)
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                       let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                        Text("版本 \(version) (\(build))")
                            .font(.caption)
                            .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.6))
                    }
                }
                .padding(24).glassCard(cornerRadius: 16)
            }
            .padding(32).frame(maxWidth: 600)
        }
        .designScreen()
    }
}

// MARK: - Ledger List Settings

struct LedgerListSettingsView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @State private var ledgers: [Ledger] = []
    @State private var showCreateSheet = false
    @State private var showDeleteAlert = false
    @State private var ledgerToDelete: Ledger?

    let onSelect: (Ledger) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("账本管理").font(.headline).foregroundStyle(Color.designOnSurface)
                    Spacer()
                    Button { showCreateSheet = true } label: {
                        Image(systemName: "plus").fontWeight(.semibold)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.bottom, 4)

                ForEach(ledgers) { ledger in
                    ledgerRow(ledger)
                }

                if ledgers.isEmpty {
                    Text("暂无账本").foregroundStyle(Color.designOnSurfaceVariant).padding(.top, 20)
                }
            }
            .padding(24).frame(maxWidth: 600)
        }
        .designScreen()
        .onAppear(perform: load)
        .sheet(isPresented: $showCreateSheet, onDismiss: { load() }) {
            CreateLedgerSheet { newLedger in
                appContainer.currentLedger = newLedger
                UserDefaults.standard.set(newLedger.id.uuidString, forKey: "currentLedgerID")
                load()
            }
        }
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { confirmDelete() }
        } message: {
            if let ledger = ledgerToDelete, ledger.isShared {
                Text("这是共享账本。删除后其他成员将无法访问，数据将保留在你的本地。")
            } else {
                Text("删除账本会同时删除该账本下的所有数据，此操作不可撤销。")
            }
        }
    }

    private func ledgerRow(_ ledger: Ledger) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ledger.iconName)
                .foregroundStyle(ledger.isShared ? Color.designPrimaryFixed : Color.designPrimaryContainer)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(ledger.name).font(.body).foregroundStyle(Color.designOnSurface)
                    if ledger.isShared {
                        Image(systemName: "person.2.fill").font(.caption2)
                            .foregroundStyle(Color.designPrimaryFixed)
                    }
                }
                Text("\(ledger.type.displayName) · \(ledger.defaultCurrencyCode)")
                    .font(.caption).foregroundStyle(Color.designOnSurfaceVariant)
            }
            Spacer()
            if ledger.id == appContainer.currentLedger?.id {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.designPrimaryContainer).fontWeight(.semibold)
            }
            if ledgers.count > 1 && (!ledger.isShared || appContainer.isOwner(of: ledger)) {
                Button {
                    ledgerToDelete = ledger
                    showDeleteAlert = true
                } label: {
                    Image(systemName: "trash").foregroundStyle(Color.designAccentRed)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .background(Color.designGlassBg.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {
            if ledger.id != appContainer.currentLedger?.id {
                appContainer.currentLedger = ledger
                UserDefaults.standard.set(ledger.id.uuidString, forKey: "currentLedgerID")
            }
            onSelect(ledger)
        }
    }

    private func load() {
        let all = (try? appContainer.ledgerService.fetchLedgers(context: modelContext)) ?? []
        ledgers = all.filter { !appContainer.exitedSharedLedgerIDs.contains($0.id) }
    }

    private func confirmDelete() {
        guard let ledger = ledgerToDelete, ledgers.count > 1 else { return }
        let wasCurrent = ledger.id == appContainer.currentLedger?.id
        do {
            try appContainer.ledgerService.deleteLedger(ledger, context: modelContext)
        } catch {
            DiagnosticLog.log("LedgerListSettings: delete FAILED \(error.localizedDescription)")
        }
        if wasCurrent, let next = (try? appContainer.ledgerService.fetchLedgers(context: modelContext))?.first {
            appContainer.currentLedger = next
            UserDefaults.standard.set(next.id.uuidString, forKey: "currentLedgerID")
        }
        load()
    }
}

// MARK: - Create Ledger Sheet

struct CreateLedgerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    @State private var name = ""
    @State private var type: LedgerType = .personal
    @State private var currencyCode = "CNY"

    let onCreated: (Ledger) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("新建账本").font(.title2.weight(.semibold))
            Form {
                TextField("账本名称", text: $name)
                Picker("类型", selection: $type) {
                    ForEach(LedgerType.allCases, id: \.self) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                Picker("默认货币", selection: $currencyCode) {
                    ForEach(["CNY", "USD", "EUR", "JPY", "GBP", "HKD"], id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
            }
            .formStyle(.grouped)
            HStack(spacing: 12) {
                Button("取消") { dismiss() }.keyboardShortcut(.escape)
                Button("创建") { create() }.keyboardShortcut(.return).disabled(name.isEmpty)
            }
        }
        .padding(24).frame(width: 360, height: 300)
    }

    private func create() {
        let ledger = Ledger(context: modelContext)
        ledger.id = UUID()
        ledger.name = name
        ledger.type = type
        ledger.defaultCurrencyCode = currencyCode
        ledger.iconName = type.systemIcon
        ledger.createdAt = Date()
        try? modelContext.save()
        onCreated(ledger)
        dismiss()
    }
}

// MARK: - Mac Category List

struct MacCategoryListView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    let ledger: Ledger?
    @State private var incomeCategories: [Category] = []
    @State private var expenseCategories: [Category] = []
    @State private var showAddSheet = false
    @State private var editingCategory: Category?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("分类管理").font(.headline).foregroundStyle(Color.designOnSurface)
                    Spacer()
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus").fontWeight(.semibold)
                    }
                    .buttonStyle(.borderless)
                }

                if !expenseCategories.isEmpty {
                    Text("支出分类").font(.caption).foregroundStyle(Color.designOnSurfaceVariant)
                    ForEach(flatExpense) { cat in
                        categoryRow(cat)
                    }
                }
                if !incomeCategories.isEmpty {
                    Text("收入分类").font(.caption).foregroundStyle(Color.designOnSurfaceVariant).padding(.top, 8)
                    ForEach(flatIncome) { cat in
                        categoryRow(cat)
                    }
                }
            }
            .padding(24).frame(maxWidth: 600)
        }
        .designScreen()
        .onAppear(perform: load)
        .sheet(isPresented: $showAddSheet, onDismiss: { load() }) {
            MacCategoryEditSheet(ledger: effectiveLedger)
        }
        .sheet(item: $editingCategory, onDismiss: { load() }) { category in
            MacCategoryEditSheet(editing: category, ledger: effectiveLedger)
        }
    }

    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }

    private var flatExpense: [Category] {
        flattenTree(expenseCategories.filter { $0.parent == nil })
    }
    private var flatIncome: [Category] {
        flattenTree(incomeCategories.filter { $0.parent == nil })
    }

    private func flattenTree(_ parents: [Category]) -> [Category] {
        var result: [Category] = []
        for parent in parents.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            result.append(parent)
            for child in (parent.children as? Set<Category> ?? []).sorted(by: { $0.sortOrder < $1.sortOrder }) {
                result.append(child)
            }
        }
        return result
    }

    private func categoryRow(_ cat: Category) -> some View {
        HStack(spacing: 8) {
            Image(systemName: cat.iconName)
                .foregroundStyle(Color(hex: cat.colorHex))
            Text(LocalizedStringKey(cat.name)).font(.body)
            if cat.isSystem {
                Text("内置").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { !cat.isHidden },
                set: { newVal in
                    cat.isHidden = !newVal
                    try? modelContext.save()
                    load()
                }
            ))
            .labelsHidden().scaleEffect(0.8)
        }
        .padding(.leading, cat.parent != nil ? 20 : 0)
        .contentShape(Rectangle())
        .onTapGesture { editingCategory = cat }
    }

    private func load() {
        guard let l = effectiveLedger else { return }
        incomeCategories = (try? appContainer.categoryService.fetchAllCategories(for: l, type: .income, context: modelContext)) ?? []
        expenseCategories = (try? appContainer.categoryService.fetchAllCategories(for: l, type: .expense, context: modelContext)) ?? []
    }
}

// MARK: - Mac Member List

struct MacMemberListView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    let ledger: Ledger?
    @State private var members: [Member] = []
    @State private var showAddAlert = false
    @State private var newName = ""
    @State private var editingMember: Member?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("成员管理").font(.headline).foregroundStyle(Color.designOnSurface)
                    Spacer()
                    Button { showAddAlert = true } label: {
                        Image(systemName: "plus").fontWeight(.semibold)
                    }
                    .buttonStyle(.borderless)
                }

                ForEach(members) { member in
                    memberRow(member)
                }
                if members.isEmpty {
                    Text("暂无联系人").foregroundStyle(Color.designOnSurfaceVariant).padding(.top, 20)
                }
            }
            .padding(24).frame(maxWidth: 600)
        }
        .designScreen()
        .onAppear(perform: load)
        .alert("添加联系人", isPresented: $showAddAlert) {
            TextField("姓名", text: $newName)
            Button("取消", role: .cancel) { newName = "" }
            Button("添加") { addMember(); newName = "" }
                .disabled(newName.isEmpty)
        }
        .sheet(item: $editingMember) { member in
            MacMemberEditSheet(member: member)
        }
        .onChange(of: editingMember) { _, newValue in
            if newValue == nil { load() }
        }
    }

    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }

    private func memberRow(_ member: Member) -> some View {
        HStack(spacing: 8) {
            Image(systemName: member.avatar)
                .foregroundStyle(Color.designPrimaryContainer)
            Text(LocalizedStringKey(member.name)).font(.body)
            if !member.isActive {
                Text("已停用").font(.caption).foregroundStyle(Color.designOnSurfaceVariant)
            }
            Spacer()
            Button {
                try? appContainer.memberService.deleteMember(member, context: modelContext)
                load()
            } label: {
                Image(systemName: "trash").foregroundStyle(Color.designAccentRed)
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color.designGlassBg.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { editingMember = member }
    }

    private func addMember() {
        guard let l = effectiveLedger else { return }
        let member = Member(name: newName, sortOrder: members.count, context: modelContext)
        try? appContainer.memberService.createMember(member, ledger: l, context: modelContext)
        load()
    }

    private func load() {
        guard let l = effectiveLedger else { return }
        members = (try? appContainer.memberService.fetchMembers(for: l, context: modelContext)) ?? []
    }
}

// MARK: - Inline Sheets

struct MacCategoryEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    var editing: Category?
    let ledger: Ledger?

    @State private var name: String = ""
    @State private var iconName: String = "tag"
    @State private var colorHex: String = "#00D16B"
    @State private var catType: TransactionType = .expense
    @State private var selectedParent: Category?
    @State private var parentOptions: [Category] = []

    private let iconOptions = ["tag", "cart", "fork.knife", "car", "house", "film", "heart", "gamecontroller", "book", "iphone", "cross.case", "airplane", "bus", "gift", "party.popper", "pawprint", "tshirt", "wrench", "leaf", "flame"]
    private let colorOptions = ["#00D16B", "#FF6B6B", "#FFD93D", "#6BCB77", "#4D96FF", "#9B59B6", "#E67E22", "#1ABC9C", "#E74C3C", "#3498DB"]

    var body: some View {
        VStack(spacing: 16) {
            Text(editing != nil ? "编辑分类" : "新建分类")
                .font(.title2.weight(.semibold))
            Form {
                TextField("名称", text: $name)
                Picker("类型", selection: $catType) {
                    Text("支出").tag(TransactionType.expense)
                    Text("收入").tag(TransactionType.income)
                }
                Picker("图标", selection: $iconName) {
                    ForEach(iconOptions, id: \.self) { icon in
                        Label(icon, systemImage: icon).tag(icon)
                    }
                }
                Picker("颜色", selection: $colorHex) {
                    ForEach(colorOptions, id: \.self) { c in
                        HStack {
                            Circle().fill(Color(hex: c)).frame(width: 16, height: 16)
                            Text(c)
                        }.tag(c)
                    }
                }
            }
            .formStyle(.grouped)
            HStack(spacing: 12) {
                Button("取消") { dismiss() }.keyboardShortcut(.escape)
                Button("保存") { save() }.keyboardShortcut(.return).disabled(name.isEmpty)
            }
        }
        .padding(24).frame(width: 380, height: 420)
        .onAppear {
            if let cat = editing {
                name = cat.name
                iconName = cat.iconName
                colorHex = cat.colorHex
                catType = cat.type
            }
            if let l = ledger ?? appContainer.currentLedger {
                parentOptions = (try? appContainer.categoryService.fetchAllCategories(for: l, type: catType, context: modelContext))?.filter { $0.parent == nil } ?? []
            }
        }
    }

    private func save() {
        let cat = editing ?? Category(context: modelContext)
        if editing == nil {
            cat.id = UUID()
            cat.sortOrder = 999
            if let l = ledger ?? appContainer.currentLedger {
                cat.ledger = l
            }
        }
        cat.name = name
        cat.iconName = iconName
        cat.colorHex = colorHex
        cat.type = catType
        try? modelContext.save()
        dismiss()
    }
}

struct MacMemberEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    let member: Member
    @State private var name: String
    @State private var avatar: String
    @State private var isActive: Bool

    init(member: Member) {
        self.member = member
        _name = State(initialValue: member.name)
        _avatar = State(initialValue: member.avatar)
        _isActive = State(initialValue: member.isActive)
    }

    private let avatarOptions = [
        "person.circle", "person.circle.fill", "face.smiling", "heart.circle",
        "star.circle", "figure.child", "figure.walk", "teddybear"
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("编辑联系人").font(.title2.weight(.semibold))
            Form {
                TextField("姓名", text: $name)
                Picker("头像", selection: $avatar) {
                    ForEach(avatarOptions, id: \.self) { icon in
                        Label(icon, systemImage: icon).tag(icon)
                    }
                }
                Toggle("启用", isOn: $isActive)
            }
            .formStyle(.grouped)
            HStack(spacing: 12) {
                Button("取消") { dismiss() }.keyboardShortcut(.escape)
                Button("保存") { save() }.keyboardShortcut(.return).disabled(name.isEmpty)
            }
        }
        .padding(24).frame(width: 360, height: 320)
    }

    private func save() {
        member.name = name
        member.avatar = avatar
        member.isActive = isActive
        try? appContainer.memberService.updateMember(member, context: modelContext)
        dismiss()
    }
}
