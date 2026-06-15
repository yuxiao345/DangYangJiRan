import SwiftUI
@preconcurrency import CoreData

struct DashboardView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @State private var viewModel: DashboardViewModel
    @State private var showAddSheet = false
    @State private var editingTransaction: Transaction?
    @State private var showBreakdown = false

    init() {
        _viewModel = State(initialValue: DashboardViewModel(
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
                            ForEach(viewModel.recentTransactions, id: \.objectID) { transaction in
                                NavigationLink(destination: TransactionDetailView(transaction: transaction)) {
                                    TransactionRowView(transaction: transaction)
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
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("净资产")
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
                }

                Spacer()

                if showBreakdown {
                    VStack(alignment: .leading, spacing: 4) {
                        let assets = viewModel.accountBalances.values.filter { $0 > 0 }.reduce(Decimal.zero, +)
                        let liabilities = abs(viewModel.accountBalances.values.filter { $0 < 0 }.reduce(Decimal.zero, +))
                        HStack(spacing: 4) {
                            Text("总资产")
                                .font(.designBodyCaption)
                                .foregroundStyle(Color.designOnSurfaceVariant)
                                .frame(width: 36, alignment: .leading)
                            CurrencyText(amount: assets, currencyCode: ledgerCurrency, size: 11, foregroundColor: Color.designPrimaryFixedDim)
                                .frame(width: 78, alignment: .trailing)
                        }
                        HStack(spacing: 4) {
                            Text("总负债")
                                .font(.designBodyCaption)
                                .foregroundStyle(Color.designOnSurfaceVariant)
                                .frame(width: 36, alignment: .leading)
                            CurrencyText(amount: liabilities, currencyCode: ledgerCurrency, size: 11, foregroundColor: Color.designAccentRed)
                                .frame(width: 78, alignment: .trailing)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
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
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) { showBreakdown.toggle() }
        }
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

            let maxRef = max(abs(viewModel.monthlyIncome), abs(viewModel.monthlyExpense))
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
        viewModel.load(ledger: ledger, context: modelContext)
        viewModel.loadBudget(context: modelContext, budgetService: appContainer.budgetService)
    }
}
