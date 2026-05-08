import SwiftUI
import SwiftData

struct DashboardView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: DashboardViewModel
    @State private var showAddSheet = false
    @State private var editingTransaction: Transaction?

    init() {
        // ViewModel is set up in onAppear with real ledger
        _viewModel = StateObject(wrappedValue: DashboardViewModel(
            ledger: Ledger(name: ""), accountService: AccountServiceImpl(), transactionService: TransactionServiceImpl()
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Monthly Summary Card
                    summaryCard
                    // Account Balance Cards
                    accountSection
                    // Recent Transactions
                    recentSection
                }
                .padding()
            }
            .navigationTitle(appContainer.currentLedger?.name ?? "荡漾计然")
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

    private var summaryCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("本月收支")
                    .font(.headline)
                Spacer()
            }
            HStack(spacing: 24) {
                VStack {
                    Text("收入")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    CurrencyText(amount: viewModel.monthlyIncome, currencyCode: ledgerCurrency, showSign: true, font: .title3, foregroundColor: .green)
                        .fontWeight(.semibold)
                }
                VStack {
                    Text("支出")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    CurrencyText(amount: viewModel.monthlyExpense, currencyCode: ledgerCurrency, showSign: true, font: .title3, foregroundColor: .red)
                        .fontWeight(.semibold)
                }
                VStack {
                    Text("结余")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    CurrencyText(amount: viewModel.monthlyNet, currencyCode: ledgerCurrency, showSign: true, font: .title3, foregroundColor: viewModel.monthlyNet >= 0 ? .green : .red)
                        .fontWeight(.semibold)
                }
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var accountSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("账户")
                    .font(.headline)
                Spacer()
                NavigationLink("全部") {
                    AccountListView()
                }
            }
            if viewModel.accounts.isEmpty {
                Text("暂无账户")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.accounts.prefix(5)) { account in
                            NavigationLink(destination: AccountDetailView(account: account)) {
                                accountCard(account)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func accountCard(_ account: Account) -> some View {
        let bal = viewModel.accountBalances[account.id] ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            Label(account.name, systemImage: account.iconName ?? "creditcard")
                .font(.subheadline)
            CurrencyText(amount: bal, currencyCode: account.currencyCode, showSign: true, font: .caption, foregroundColor: bal >= 0 ? .green : .red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.background.tertiary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var recentSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("最近交易")
                    .font(.headline)
                Spacer()
                NavigationLink("全部") {
                    TransactionListView()
                }
            }
            if viewModel.recentTransactions.isEmpty {
                Text("暂无交易记录")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(viewModel.recentTransactions) { transaction in
                    NavigationLink(destination: TransactionDetailView(transaction: transaction)) {
                        TransactionRowView(transaction: transaction)
                    }
                }
            }
        }
    }

    private var ledgerCurrency: String {
        appContainer.currentLedger?.defaultCurrencyCode ?? "CNY"
    }

    private func refresh() {
        guard let ledger = appContainer.currentLedger else { return }
        let vm = DashboardViewModel(
            ledger: ledger,
            accountService: appContainer.accountService,
            transactionService: appContainer.transactionService
        )
        vm.load(context: modelContext)
        viewModel.monthlyIncome = vm.monthlyIncome
        viewModel.monthlyExpense = vm.monthlyExpense
        viewModel.recentTransactions = vm.recentTransactions
        viewModel.accounts = vm.accounts
        viewModel.accountBalances = vm.accountBalances
    }
}
