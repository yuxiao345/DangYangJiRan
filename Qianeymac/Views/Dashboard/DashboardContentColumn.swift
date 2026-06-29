import SwiftUI
@preconcurrency import CoreData

struct DashboardContentColumn: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @State private var viewModel = DashboardViewModel(
        accountService: AccountServiceImpl(), transactionService: TransactionServiceImpl()
    )
    @State private var showBudgetDetail = false
    @State private var showBreakdown = false
    @State private var isBudgetHovered = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                netWorthCard
                incomeExpenseRow
                if viewModel.hasBudget {
                    budgetSummaryCard
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                        .onHover { inside in
                            withAnimation(.easeOut(duration: 0.15)) { isBudgetHovered = inside }
                            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                        .onTapGesture { showBudgetDetail = true }
                } else {
                    emptyBudgetCard
                }
                recentTransactionsSection
            }
            .padding(24)
        }
        .designScreen()
        .onAppear { loadAll() }
        .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in loadAll() }
        .onChange(of: appContainer.currentLedger?.id) { _, _ in loadAll() }
        .sheet(isPresented: $showBudgetDetail) {
            if let book = viewModel.activeBudgetBook {
                BudgetBookDetailMacView(book: book)
            } else if let ledger = appContainer.currentLedger {
                BudgetBookListView(ledger: ledger)
            }
        }
    }

    private func loadAll() {
        guard let ledger = appContainer.currentLedger else { return }
        let vm = DashboardViewModel(
            accountService: appContainer.accountService,
            transactionService: appContainer.transactionService,
            ledger: ledger
        )
        vm.load(context: modelContext, budgetService: appContainer.budgetService)
        vm.loadBudget(context: modelContext, budgetService: appContainer.budgetService)
        viewModel.copyFrom(vm)
    }

    private var currencyCode: String {
        appContainer.currentLedger?.defaultCurrencyCode ?? "CNY"
    }

    // MARK: - 净资产

    private var netWorthCard: some View {
        let assets = viewModel.accountBalances.values.filter { $0 > 0 }.reduce(Decimal.zero, +)
        let liabilities = abs(viewModel.accountBalances.values.filter { $0 < 0 }.reduce(Decimal.zero, +))
        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("净资产")
                        .font(.designLabel)
                        .foregroundStyle(Color.designOnSurfaceVariant)
                        .tracking(1.2)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(CurrencyFormatter.currencySymbol(for: currencyCode))
                            .font(.custom("JetBrainsMono-Medium", fixedSize: 24))
                            .foregroundStyle(Color.designPrimaryFixedDim)
                        Text(CurrencyFormatter.formatDecimal(amount: viewModel.totalBalance, fractionDigits: 2))
                            .font(.designDisplayMobile)
                            .foregroundStyle(Color.designOnSurface)
                            .tracking(-0.6)
                    }
                }
                Spacer()
                if showBreakdown {
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("总资产").font(.designBodyCaption).foregroundStyle(Color.designOnSurfaceVariant).fixedSize()
                            CurrencyText(amount: assets, currencyCode: currencyCode, size: 13, foregroundColor: Color.designPrimaryFixedDim)
                                .frame(width: 82, alignment: .trailing)
                        }
                        HStack(spacing: 8) {
                            Text("总负债").font(.designBodyCaption).foregroundStyle(Color.designOnSurfaceVariant).fixedSize()
                            CurrencyText(amount: liabilities, currencyCode: currencyCode, size: 13, foregroundColor: Color.designAccentRed)
                                .frame(width: 82, alignment: .trailing)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            if let change = viewModel.balanceChange, let pct = viewModel.balanceChangePercent {
                HStack(spacing: 4) {
                    Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("\(change >= 0 ? "+" : "")\(CurrencyFormatter.formatDecimal(amount: change, fractionDigits: 0)) (\(String(format: "%.1f", Double(truncating: pct as NSNumber)))%)")
                        .font(.designMonoData)
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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

    // MARK: - 收入/支出/结余

    private var incomeExpenseRow: some View {
        let balance = viewModel.monthlyIncome + viewModel.monthlyExpense
        let maxRef = max(abs(viewModel.monthlyIncome), abs(viewModel.monthlyExpense))
        return HStack(spacing: 12) {
            metricCell(label: "本月收入", amount: viewModel.monthlyIncome, maxRef: maxRef, color: Color.designPrimaryFixedDim)
            metricCell(label: "本月支出", amount: abs(viewModel.monthlyExpense), maxRef: maxRef, color: Color.designAccentRed)
            metricCell(label: "本月结余", amount: balance, maxRef: maxRef, color: balance >= 0 ? Color.designPrimaryFixedDim : Color.designAccentRed)
        }
    }

    private func metricCell(label: String, amount: Decimal, maxRef: Decimal, color: Color) -> some View {
        let frac = maxRef > 0 ? CGFloat(truncating: (abs(amount) / maxRef) as NSNumber) : 0
        return VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.designLabelSmall)
                .foregroundStyle(Color.designOnSurfaceVariant)
                .tracking(1.0)
            CurrencyText(amount: amount, currencyCode: currencyCode, showSign: false, size: 22, foregroundColor: color, fractionDigits: 0)
            PixelProgressBar(progress: Double(frac), tint: color.opacity(0.6), totalBlocks: 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 16)
    }

    // MARK: - 预算

    private var budgetSummaryCard: some View {
        let spent = viewModel.budgetSpent
        let limit = viewModel.budgetLimit
        let percent = limit > 0 ? Double(truncating: (spent / limit) as NSNumber) : 0
        let remaining = limit - spent
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("本月预算")
                    .font(.designBodyMedium.weight(.bold))
                    .foregroundStyle(isBudgetHovered ? Color.designAccentGreen : Color.designOnSurface)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.designBodyCaption)
                    .foregroundStyle(isBudgetHovered ? Color.designAccentGreen : Color.secondary)
                    .offset(x: isBudgetHovered ? 2 : 0)
            }
            PixelProgressBar(progress: min(percent, 1), tint: progressColor(percent), totalBlocks: 20)
            HStack {
                Text("已支出 \(CurrencyFormatter.formatDecimal(amount: spent, fractionDigits: 0, showAbs: true))")
                    .font(.designBodyCaption)
                    .foregroundStyle(Color.designOnSurfaceVariant)
                Spacer()
                Text("预算 \(CurrencyFormatter.formatDecimal(amount: limit, fractionDigits: 0, showAbs: true))")
                    .font(.designBodyCaption)
                    .foregroundStyle(Color.designOnSurfaceVariant)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 16)
    }

    private var emptyBudgetCard: some View {
        VStack(spacing: 8) {
            Text("本月预算")
                .font(.designBodyMedium.weight(.bold))
                .foregroundStyle(isBudgetHovered ? Color.designAccentGreen : Color.designOnSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Image(systemName: "plus.circle")
                    .font(.designHeadlineMedium)
                Text("设置预算，掌控每月开支")
                    .font(.designBodyMedium)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.designBodyCaption)
            }
            .foregroundStyle(Color.designOnSurfaceVariant)
        }
        .padding(16)
        .glassCard(cornerRadius: 16)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) { isBudgetHovered = inside }
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onTapGesture { showBudgetDetail = true }
    }

    // MARK: - 最近交易

    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近交易")
                .font(.designBodyMedium.weight(.bold))
                .foregroundStyle(Color.designOnSurface)

            if viewModel.recentTransactions.isEmpty {
                Text("本月暂无交易记录")
                    .font(.designBodyMedium)
                    .foregroundStyle(Color.designOnSurfaceVariant)
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.recentTransactions.prefix(10), id: \.objectID) { t in
                        TransactionRowView(transaction: t)
                    }
                }
            }
        }
    }

    struct OverflowLayout: Layout {
        var spacing: CGFloat = 12
        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            layout(proposal: proposal, subviews: subviews).size
        }
        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let result = layout(proposal: proposal, subviews: subviews)
            for (i, subview) in subviews.enumerated() {
                subview.place(at: CGPoint(x: bounds.minX + result.positions[i].x, y: bounds.minY + result.positions[i].y), proposal: proposal)
            }
        }
        func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
            let maxWidth = proposal.width ?? .infinity
            var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
            var positions: [CGPoint] = []
            for sub in subviews {
                let size = sub.sizeThatFits(proposal)
                if x + size.width > maxWidth && x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
                positions.append(CGPoint(x: x, y: y))
                x += size.width + spacing
                rowHeight = max(rowHeight, size.height)
            }
            return (CGSize(width: maxWidth, height: y + rowHeight), positions)
        }
    }
}

