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

// MARK: - Main Split View

struct MainSplitView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @State private var selection: MacNavItem? = .dashboard

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(MacNavItem.allCases) { item in
                    NavigationLink(
                        tag: item,
                        selection: $selection
                    ) {
                        detailView(for: item)
                    } label: {
                        Label(item.rawValue, systemImage: item.icon)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle(appContainer.currentLedger?.name ?? "小金库")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            if let selection {
                detailView(for: selection)
            } else {
                DashboardMacView()
            }
        }
    }

    @ViewBuilder
    private func detailView(for item: MacNavItem) -> some View {
        switch item {
        case .dashboard: DashboardMacView()
        case .accounts: AccountsMacView()
        case .transactions: TransactionsMacView()
        case .reports: ReportsMacView()
        case .settings: SettingsMacView()
        }
    }
}

// MARK: - Dashboard

struct DashboardMacView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.managedObjectContext) private var modelContext
    @StateObject private var viewModel = DashboardViewModel(
        accountService: AccountServiceImpl(), transactionService: TransactionServiceImpl()
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                balanceCard
                incomeExpenseRow
                recentTransactionsSection
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .designScreen()
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in refresh() }
        .onChange(of: appContainer.currentLedger?.id) { _, _ in refresh() }
    }

    private var currencyCode: String {
        appContainer.currentLedger?.defaultCurrencyCode ?? "CNY"
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("总资产").font(.caption).foregroundStyle(Color.designOnSurfaceVariant)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(CurrencyFormatter.currencySymbol(for: currencyCode))
                    .font(.title2).foregroundStyle(Color.designPrimaryFixedDim)
                Text(CurrencyFormatter.formatDecimal(amount: viewModel.totalBalance, fractionDigits: 2))
                    .font(.largeTitle.weight(.bold)).foregroundStyle(Color.designOnSurface)
            }
            if let change = viewModel.balanceChange {
                Label(change >= 0 ? "较上月增长" : "较上月减少",
                      systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption)
                    .foregroundStyle(change >= 0 ? Color.designPrimaryFixedDim : Color.designAccentRed)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .glassCard(cornerRadius: 20)
    }

    private var incomeExpenseRow: some View {
        HStack(spacing: 16) {
            metricCard(title: "本月收入", amount: viewModel.monthlyIncome, color: Color.designPrimaryFixedDim)
            metricCard(title: "本月支出", amount: viewModel.monthlyExpense, color: Color.designAccentRed)
        }
    }

    private func metricCard(title: String, amount: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Color.designOnSurfaceVariant)
            Text(CurrencyFormatter.formatDecimal(amount: amount, currencyCode: currencyCode))
                .font(.title3.weight(.semibold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 16)
    }

    private var recentTransactionsSection: some View {
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
    }

    private func refresh() {
        viewModel.load(context: modelContext)
    }
}

// MARK: - Accounts

struct AccountsMacView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.managedObjectContext) private var modelContext
    @State private var accounts: [Account] = []
    @State private var balances: [UUID: Decimal] = [:]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
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
            .padding(32)
        }
        .designScreen()
        .onAppear(perform: load)
    }

    private var groupedAccounts: [(key: String, value: [Account])] {
        Dictionary(grouping: accounts) { $0.type.displayName }
            .sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    private func accountRow(_ account: Account) -> some View {
        HStack {
            Label(account.name, systemImage: account.type.systemIcon)
            Spacer()
            Text(CurrencyFormatter.formatDecimal(amount: balances[account.id] ?? 0, currencyCode: account.currencyCode))
                .foregroundStyle((balances[account.id] ?? 0) >= 0 ? Color.designPrimaryFixedDim : Color.designAccentRed)
        }
        .padding(12)
        .glassCard(cornerRadius: 12)
    }

    private func load() {
        guard let ledger = appContainer.currentLedger else { return }
        accounts = (try? appContainer.accountService.fetchAccounts(for: ledger, context: modelContext)) ?? []
        for a in accounts {
            balances[a.id] = appContainer.accountService.calculateBalance(for: a, context: modelContext)
        }
    }
}

// MARK: - Transactions

struct TransactionsMacView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.managedObjectContext) private var modelContext
    @State private var transactions: [Transaction] = []
    @State private var filterType: TransactionType?
    @State private var selectedMonth: Date = Date().startOfMonth

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            ScrollView {
                LazyVStack(spacing: 12) {
                    if transactions.isEmpty {
                        Text("暂无交易记录").foregroundStyle(Color.designOnSurfaceVariant).padding(.top, 60)
                    } else {
                        ForEach(groupedByDate, id: \.key) { group in
                            dateHeader(group.key, transactions: group.value)
                            ForEach(group.value) { t in
                                TransactionRowView(transaction: t)
                            }
                        }
                    }
                }
                .padding(24)
            }
            .designScreen()
        }
        .onAppear(perform: load)
        .onChange(of: filterType) { _, _ in load() }
        .onChange(of: selectedMonth) { _, _ in load() }
        .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in load() }
    }

    private var filterBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                Text(selectedMonth.monthDisplay).font(.headline)
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
            }
            Spacer()
            Picker("类型", selection: $filterType) {
                Text("全部").tag(nil as TransactionType?)
                Text(TransactionType.expense.displayName).tag(TransactionType.expense as TransactionType?)
                Text(TransactionType.income.displayName).tag(TransactionType.income as TransactionType?)
                Text(TransactionType.transfer.displayName).tag(TransactionType.transfer as TransactionType?)
                Text(TransactionType.lending.displayName).tag(TransactionType.lending as TransactionType?)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 400)
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
    }

    private func dateHeader(_ key: String, transactions: [Transaction]) -> some View {
        let nonTransfer = transactions.filter { $0.type != .transfer }
        let total = nonTransfer.reduce(Decimal.zero) { $0 + $1.amount }
        let code = transactions.first?.currencyCode ?? "CNY"
        return HStack {
            Text(key).font(.caption).foregroundStyle(Color.designOnSurfaceVariant)
            Spacer()
            if !nonTransfer.isEmpty {
                Text(total >= 0
                     ? "+\(CurrencyFormatter.formatDecimal(amount: total, currencyCode: code))"
                     : "-\(CurrencyFormatter.formatDecimal(amount: total, currencyCode: code, showAbs: true))"
                ).font(.caption).foregroundStyle(total >= 0 ? Color.designPrimaryFixedDim : Color.designAccentRed)
            }
        }.padding(.top, 8)
    }

    private var groupedByDate: [(key: String, value: [Transaction])] {
        transactions.groupedByRelativeDate()
    }

    private func load() {
        guard let ledger = appContainer.currentLedger else { return }
        let cal = Calendar.current
        let start = selectedMonth
        guard let end = cal.date(byAdding: .month, value: 1, to: start) else { return }
        var filters = TransactionFilters()
        filters.dateRange = start..<end
        let all = (try? appContainer.transactionService.fetchTransactions(for: ledger, context: modelContext, filters: filters)) ?? []
        var seen = Set<UUID>()
        var result = all.filter { t in
            if t.type == .transfer, let gid = t.transferGroupId {
                if seen.contains(gid) { return false }
                if t.amount < 0 { seen.insert(gid); return true }
                return false
            }
            return true
        }
        if let type = filterType { result = result.filter { $0.type == type } }
        transactions = result
    }

    private func shiftMonth(_ delta: Int) {
        let cal = Calendar.current
        selectedMonth = cal.date(byAdding: .month, value: delta, to: selectedMonth)?.startOfMonth ?? selectedMonth
    }
}

// MARK: - Reports

struct ReportsMacView: View {
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

// MARK: - Settings

struct SettingsMacView: View {
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

                VStack(alignment: .leading, spacing: 8) {
                    Text("关于").font(.headline).foregroundStyle(Color.designOnSurface)
                    Text("钱伲 — 家庭记账与资产管理").foregroundStyle(Color.designOnSurfaceVariant)
                }
                .padding(24).glassCard(cornerRadius: 16)
            }
            .padding(32).frame(maxWidth: 600)
        }
        .designScreen()
    }
}
