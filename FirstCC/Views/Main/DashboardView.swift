import SwiftUI
@preconcurrency import CoreData

struct DashboardView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.managedObjectContext) private var modelContext
    @StateObject private var viewModel: DashboardViewModel
    @State private var showAddSheet = false
    @State private var editingTransaction: Transaction?

    init() {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(
            accountService: AccountServiceImpl(), transactionService: TransactionServiceImpl()
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 16) {
                        heroBalanceCard
                        incomeExpenseGrid
                        budgetCard
                    }
                    .padding(16)

                    HStack {
                        Text("最近交易")
                            .font(.designBodyMedium.weight(.bold))
                            .foregroundStyle(Color.designOnSurface)
                        Spacer()
                        NavigationLink("全部") {
                            TransactionListView()
                        }
                        .font(.designBodyCaption)
                        .foregroundStyle(Color.designAccentGreen)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                    if viewModel.recentTransactions.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.system(size: 40))
                                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
                            Text("本月暂无交易记录")
                                .font(.designBodyMedium)
                                .foregroundStyle(Color.designOnSurfaceVariant)
                        }
                        .padding(.top, 60)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.recentTransactions) { transaction in
                                NavigationLink(destination: TransactionDetailView(transaction: transaction)) {
                                    transactionCard(transaction)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
            .designScreen()
            .navigationTitle(appContainer.currentLedger?.name ?? "小金库")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SyncStatusBadge()
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear { refresh() }
            .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in
                refresh()
            }
            .onChange(of: appContainer.currentLedger?.id) { _, _ in
                refresh()
            }
            .sheet(isPresented: $showAddSheet) {
                AddEditTransactionView()
            }
            .sheet(item: $editingTransaction) { transaction in
                AddEditTransactionView(editing: transaction)
            }
        }
    }

    // MARK: - Hero Balance Card

    private var heroBalanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("总资产")
                .font(.designLabel)
                .foregroundStyle(Color.designOnSurfaceVariant)
                .tracking(1.2)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(CurrencyFormatter.currencySymbol(for: ledgerCurrency))
                    .font(.custom("JetBrainsMono-Medium", fixedSize: 24))
                    .foregroundStyle(Color.designPrimaryFixedDim)
                Text(formattedBalance)
                    .font(.designDisplayMobile)
                    .foregroundStyle(Color.designOnSurface)
                    .tracking(-0.6)
            }

            if let change = viewModel.balanceChange {
                HStack(spacing: 4) {
                    Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10).weight(.bold))
                    CurrencyText(amount: change, currencyCode: ledgerCurrency, showSign: true, size: 13, foregroundColor: change >= 0 ? Color.designPrimaryFixedDim : Color.designAccentRed)
                    if let pct = viewModel.balanceChangePercent {
                        Text(String(format: "(%@%.1f%%)", pct >= 0 ? "+" : "", Double(truncating: pct as NSNumber)))
                            .font(.designBodyCaption)
                    }
                    Text("较上月")
                        .font(.designBodyCaption)
                        .foregroundStyle(Color.designOnSurfaceVariant)
                }
                .foregroundStyle(change >= 0 ? Color.designPrimaryFixedDim : Color.designAccentRed)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background {
                    Capsule()
                        .fill((change >= 0 ? Color.designPrimaryFixedDim : Color.designAccentRed).opacity(0.12))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(cornerRadius: 24)
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.designPrimaryFixedDim.opacity(0.15))
                .frame(width: 100, height: 100)
                .blur(radius: 30)
                .offset(x: 20, y: -20)
        }
    }

    // MARK: - Income / Expense Grid

    private var incomeExpenseGrid: some View {
        HStack(spacing: 12) {
            metricCard(
                label: "本月收入",
                amount: viewModel.monthlyIncome,
                color: Color.designPrimaryFixedDim
            )
            metricCard(
                label: "本月支出",
                amount: viewModel.monthlyExpense,
                color: Color.designAccentRed
            )
        }
    }

    private func metricCard(label: String, amount: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.designLabelSmall)
                .foregroundStyle(Color.designOnSurfaceVariant)
                .tracking(1.0)

            CurrencyText(amount: abs(amount), currencyCode: ledgerCurrency, showSign: false, size: 22, foregroundColor: color, fractionDigits: 0)

            let maxRef = max(viewModel.monthlyIncome, viewModel.monthlyExpense)
            let frac = maxRef > 0 ? Double(truncating: (abs(amount) / maxRef) as NSNumber) : 0
            PixelProgressBar(progress: frac, tint: color.opacity(0.6), totalBlocks: 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 16)
    }

    // MARK: - Budget Card

    @ViewBuilder
    private var budgetCard: some View {
        if viewModel.hasBudget {
            NavigationLink {
                if let book = viewModel.activeBudgetBook {
                    BudgetBookDetailView(book: book)
                }
            } label: {
                VStack(spacing: 12) {
                    HStack {
                        Text("本月预算")
                            .font(.designBodyMedium.weight(.bold))
                            .foregroundStyle(Color.designOnSurface)
                        Spacer()
                        Text("已用 \(String(format: "%.0f%%", viewModel.budgetFraction * 100))")
                            .font(.designMonoDataSmall)
                            .foregroundStyle(Color.designOnSurfaceVariant)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.designOnSurfaceVariant)
                    }

                    PixelProgressBar(
                        progress: viewModel.budgetFraction,
                        tint: budgetProgressColor(viewModel.budgetFraction),
                        totalBlocks: 20
                    )

                    HStack {
                        Text("已支出 \(formatBudgetAmount(viewModel.budgetSpent))")
                            .font(.designBodyCaption)
                            .foregroundStyle(Color.designOnSurfaceVariant)
                        Spacer()
                        Text("预算 \(formatBudgetAmount(viewModel.budgetLimit))")
                            .font(.designBodyCaption)
                            .foregroundStyle(Color.designOnSurfaceVariant)
                    }
                }
                .padding(16)
                .glassCard(cornerRadius: 16)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                BudgetBookListView(ledger: appContainer.currentLedger)
            } label: {
                VStack(spacing: 8) {
                    Text("本月预算")
                        .font(.designBodyMedium.weight(.bold))
                        .foregroundStyle(Color.designOnSurface)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack {
                        Image(systemName: "plus.circle")
                            .font(.title3)
                        Text("设置预算，掌控每月开支")
                            .font(.designBodyMedium)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.designOnSurfaceVariant)
                }
                .padding(16)
                .glassCard(cornerRadius: 16)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Transaction Card

    private func transactionCard(_ transaction: Transaction) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.designSurfaceContainer)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.designOutlineVariant.opacity(0.3), lineWidth: 1)
                }
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: transactionIcon(transaction))
                        .font(.system(size: 16))
                        .foregroundStyle(transactionIconColor(transaction))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(transactionTitle(transaction)))
                    .font(.designBodyMedium.weight(.medium))
                    .foregroundStyle(Color.designOnSurface)
                    .lineLimit(1)
                Text(transactionSubtitle(transaction))
                    .font(.designBodyCaption)
                    .foregroundStyle(Color.designOnSurfaceVariant)
                    .lineLimit(1)
            }

            Spacer()

            transactionAmountView(transaction)
        }
        .padding(12)
        .glassCard(cornerRadius: 12)
    }

    private func transactionIcon(_ tx: Transaction) -> String {
        if let d = tx.lendingDirection { return d.systemIcon }
        return tx.category?.iconName ?? tx.type.systemIcon
    }

    private func transactionIconColor(_ tx: Transaction) -> Color {
        if tx.isLending { return .orange }
        switch tx.type {
        case .income: return Color.designPrimaryFixedDim
        case .expense: return Color.designAccentRed
        default: return Color.designOnSurfaceVariant
        }
    }

    private func transactionTitle(_ tx: Transaction) -> String {
        if let d = tx.lendingDirection { return d.displayName }
        if tx.type == .transfer { return tx.type.displayName }
        return tx.merchant?.name ?? tx.category?.name ?? tx.type.displayName
    }

    private func transactionSubtitle(_ tx: Transaction) -> String {
        if tx.isLending || tx.type == .transfer {
            let from = tx.account?.name ?? "—"
            let to = tx.toAccount?.name ?? "—"
            return "\(from) → \(to)"
        }
        let cat = tx.category?.name ?? tx.type.displayName
        return "\(cat) · \(relativeDateString(tx.date))"
    }

    private func relativeDateString(_ date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day ?? 0
        switch days {
        case 0: return "今天"
        case 1: return "昨天"
        default: return "\(days)天前"
        }
    }

    @ViewBuilder
    private func transactionAmountView(_ tx: Transaction) -> some View {
        let color: Color = {
            switch tx.type {
            case .income: return Color.designPrimaryFixedDim
            case .expense: return Color.designAccentRed
            case .transfer: return .blue
            case .lending: return tx.amount >= 0 ? Color.designPrimaryFixedDim : .orange
            case .adjustment: return tx.amount >= 0 ? Color.designPrimaryFixedDim : Color.designAccentRed
            }
        }()
        CurrencyText(amount: tx.amount, currencyCode: tx.currencyCode, showSign: true, size: 15, foregroundColor: color)
    }

    // MARK: - Helpers

    private var formattedBalance: String {
        CurrencyFormatter.formatDecimal(amount: viewModel.totalBalance, fractionDigits: 2)
    }

    private var ledgerCurrency: String {
        appContainer.currentLedger?.defaultCurrencyCode ?? "CNY"
    }

    private func formatBudgetAmount(_ amount: Decimal) -> String {
        let symbol = CurrencyFormatter.currencySymbol(for: ledgerCurrency)
        let raw = CurrencyFormatter.formatDecimal(amount: amount, fractionDigits: 0, showAbs: true)
        return "\(symbol)\(raw)"
    }

    private func budgetProgressColor(_ progress: Double) -> Color {
        if progress > 1.0 { return .designAccentRed }
        switch progress {
        case ..<0.5: return .designPrimaryFixedDim
        case ..<0.8: return .yellow
        default: return .orange
        }
    }

    private func refresh() {
        guard let ledger = appContainer.currentLedger else { return }
        let vm = DashboardViewModel(
            accountService: appContainer.accountService,
            transactionService: appContainer.transactionService,
            ledger: ledger
        )
        vm.load(context: modelContext)
        vm.loadBudget(context: modelContext, budgetService: appContainer.budgetService)
        viewModel.monthlyIncome = vm.monthlyIncome
        viewModel.monthlyExpense = vm.monthlyExpense
        viewModel.recentTransactions = vm.recentTransactions
        viewModel.accounts = vm.accounts
        viewModel.accountBalances = vm.accountBalances
        viewModel.totalBalance = vm.totalBalance
        viewModel.previousMonthBalance = vm.previousMonthBalance
        viewModel.balanceChange = vm.balanceChange
        viewModel.balanceChangePercent = vm.balanceChangePercent
        viewModel.budgetSpent = vm.budgetSpent
        viewModel.budgetLimit = vm.budgetLimit
        viewModel.hasBudget = vm.hasBudget
        viewModel.activeBudgetBook = vm.activeBudgetBook
    }
}
