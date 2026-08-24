import SwiftUI
@preconcurrency import CoreData

struct DashboardView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: DashboardViewModel
    @State private var showAddSheet = false
    @State private var editingTransaction: Transaction?
    @State private var showBreakdown = false
    @State private var showNetWorth = false
    @State private var dotsPhase: DotsRevealPhase = .showingDots
    @State private var currentEffect: AmountHideEffect = .gentle
    @State private var amountIsVisible: Bool = true  // 默认 true（显示），init 后归零
    @State private var dotAnimationTask: Task<Void, Never>?
    @State private var amountAnimationTask: Task<Void, Never>?
    // Progress bar animated values (0→target on appear/data load)
    @State private var displayBudgetFraction: Double = 0
    @State private var displayIncomeFrac: Double = 0
    @State private var displayExpenseFrac: Double = 0

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
                            .accessibilityIdentifier("dashboard-hero-balance-card")
                        incomeExpenseGrid
                            .accessibilityIdentifier("dashboard-income-expense-grid")
                        budgetCard
                            .accessibilityIdentifier("dashboard-budget-card")
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
                        .accessibilityIdentifier("dashboard-recent-tx-all-link")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                    if viewModel.recentTransactions.isEmpty {
                        ContentUnavailableView(
                            "本月暂无交易记录",
                            systemImage: "tray",
                            description: Text("点击右上角 + 开始记一笔")
                        )
                        .padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.recentTransactions, id: \.objectID) { transaction in
                                NavigationLink(value: transaction.objectID) {
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
            .scrollClipDisabled()
            .designScreen()
            .navigationTitle(appContainer.currentLedger?.name ?? "小金库")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("记一笔"))
                    .accessibilityIdentifier("dashboard-add-tx-button")
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
            .navigationDestination(for: NSManagedObjectID.self) { id in
                if let tx = modelContext.object(with: id) as? Transaction {
                    TransactionDetailView(transaction: tx)
                }
            }
        }
    }

    // MARK: - Hero Balance Card

    private var heroBalanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Text("净资产")
                            .font(.designLabel)
                            .foregroundStyle(Color.designOnSurfaceVariant)
                            .tracking(1.2)

                        Button {
                            toggleNetWorth()
                        } label: {
                            Image(systemName: showNetWorth ? "eye" : "eye.slash")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.designOnSurfaceVariant)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(CurrencyFormatter.currencySymbol(for: ledgerCurrency))
                            .font(.custom("JetBrainsMono-Medium", fixedSize: 24))
                            .foregroundStyle(Color.designPrimaryFixedDim)
                        blurredAmountView
                    }
                }

                Spacer()

                if showBreakdown {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text("总资产")
                                .font(.designBodyCaption)
                                .foregroundStyle(Color.designOnSurfaceVariant)
                                .frame(width: 36, alignment: .leading)
                            CurrencyText(amount: totalAssets, currencyCode: ledgerCurrency, size: 11, foregroundColor: Color.designPrimaryFixedDim)
                                .frame(width: 78, alignment: .trailing)
                        }
                        HStack(spacing: 4) {
                            Text("总负债")
                                .font(.designBodyCaption)
                                .foregroundStyle(Color.designOnSurfaceVariant)
                                .frame(width: 36, alignment: .leading)
                            CurrencyText(amount: totalLiabilities, currencyCode: ledgerCurrency, size: 11, foregroundColor: Color.designAccentRed)
                                .frame(width: 78, alignment: .trailing)
                        }
                    }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
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
        .accessibilityLabel(Text(showBreakdown ? "收起明细" : "展开明细"))
        .accessibilityAddTraits(.isButton)
        .onTapGesture {
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) { showBreakdown.toggle() }
        }
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.designPrimaryFixedDim.opacity(0.15))
                .frame(width: 100, height: 100)
                .blur(radius: 30)
                .offset(x: 20, y: -20)
        }
    }

    // MARK: - Blurred Amount View

    /// 净资产金额显示，多阶段动画：
    /// - 显示金额：圆点逐个消失 → 金额动画出现
    /// - 隐藏金额：金额动画消失 → 圆点逐个出现
    private var blurredAmountView: some View {
        ZStack(alignment: Alignment(horizontal: .leading, vertical: .lastTextBaseline)) {
            dotsView
            amountView
        }
        .foregroundStyle(Color.designOnSurface)
        .tracking(-0.6)
    }

    @ViewBuilder
    private var amountView: some View {
        switch dotsPhase {
        case .showingAmount, .amountDisappearing:
            Text(formattedBalance)
                .font(.designDisplayMobile)
                .modifier(AmountEffectModifier(effect: currentEffect, isVisible: amountIsVisible))
        default:
            Text("")
                .font(.designDisplayMobile)
        }
    }

    @ViewBuilder
    private var dotsView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            ForEach(0..<5, id: \.self) { idx in
                CircleDot()
                    .opacity(dotOpacity(for: idx))
                    .animation(.easeOut(duration: 0.15).delay(Double(idx) * 0.06), value: dotsPhase)
            }
        }
    }

    /// 根据当前相位和 dot index 计算透明度
    private func dotOpacity(for idx: Int) -> Double {
        switch dotsPhase {
        case .showingDots:
            return 1.0
        case .dotsDisappearing:
            // 从右到左逐个消失
            return idx > (4 - dotsDisappearingIndex) ? 0.0 : 1.0
        case .showingAmount, .amountDisappearing:
            return 0.0
        case .dotsAppearing:
            // 从左到右逐个出现（关眼睛时）
            return idx <= dotsAppearingIndex ? 1.0 : 0.0
        }
    }

    /// dotsDisappearing 阶段当前消失到第几个（0=刚开始, 5=全消失）
    @State private var dotsDisappearingIndex: Int = 0
    /// dotsAppearing 阶段当前出现到第几个（0=全不可见, 5=全出现）
    @State private var dotsAppearingIndex: Int = 0

    // MARK: - Income / Expense Grid

    private var incomeExpenseGrid: some View {
        HStack(spacing: 12) {
            metricCard(
                label: "本月收入",
                amount: viewModel.monthlyIncome,
                progress: displayIncomeFrac,
                color: Color.designPrimaryFixedDim
            )
            metricCard(
                label: "本月支出",
                amount: viewModel.monthlyExpense,
                progress: displayExpenseFrac,
                color: Color.designAccentRed
            )
        }
    }

    private func metricCard(label: LocalizedStringKey, amount: Decimal, progress: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.designLabelSmall)
                .foregroundStyle(Color.designOnSurfaceVariant)
                .tracking(1.0)

            CurrencyText(amount: abs(amount), currencyCode: ledgerCurrency, showSign: false, size: 22, foregroundColor: color, fractionDigits: 0)

            PixelProgressBar(progress: progress, tint: color, totalBlocks: 20)
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
                        Text("已用 \(Text(viewModel.budgetFraction, format: .percent.precision(.fractionLength(0))))")
                            .font(.designMonoDataSmall)
                            .foregroundStyle(Color.designOnSurfaceVariant)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.designOnSurfaceVariant)
                    }

                    PixelProgressBar(
                        progress: displayBudgetFraction,
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

    /// Sum of positive balances (assets). Single-pass reduce over viewModel.accountBalances.
    private var totalAssets: Decimal {
        viewModel.accountBalances.values.reduce(Decimal.zero) { $0 + max($1, 0) }
    }

    /// Sum of negative balances as positive liabilities. Same single-pass reduce.
    private var totalLiabilities: Decimal {
        viewModel.accountBalances.values.reduce(Decimal.zero) { $0 + max(-$1, 0) }
    }

    private func formatBudgetAmount(_ amount: Decimal) -> String {
        CurrencyFormatter.formatDecimal(amount: amount, currencyCode: ledgerCurrency, fractionDigits: 0, showAbs: true)
    }

    private func budgetProgressColor(_ progress: Double) -> Color {
        Color.progressTint(for: progress)
    }

    private func toggleNetWorth() {
        currentEffect = AmountHideEffect.random

        if dotsPhase == .showingDots || dotsPhase == .dotsAppearing {
            // --- 开眼睛：圆点消失 → 金额出现 ---
            startDotsDisappearing()
        } else if dotsPhase == .showingAmount {
            // --- 关眼睛：金额消失 → 圆点出现 ---
            startAmountDisappearing()
        }
    }

    /// 阶段1：圆点从右到左逐个消失
    private func startDotsDisappearing() {
        if reduceMotion {
            // 跳过动画，直接显示金额
            dotsDisappearingIndex = 5
            dotsPhase = .showingAmount
            amountIsVisible = true
            return
        }
        dotAnimationTask?.cancel()
        dotsDisappearingIndex = 0
        dotsPhase = .dotsDisappearing

        dotAnimationTask = Task { @MainActor in
            // 逐步增加消失的点数（0...5: 0=刚开始, 5=全部消失）
            for i in 0...5 {
                try? await Task.sleep(for: .milliseconds(60))
                dotsDisappearingIndex = i
            }
            // 圆点全部消失，切换到金额显示
            try? await Task.sleep(for: .milliseconds(100))
            startAmountAppearing()
        }
    }

    /// 阶段2：金额动画出现
    private func startAmountAppearing() {
        dotsPhase = .showingAmount
        // 先隐藏（触发消失动画的终点），下一帧再显示（触发动画起点）
        amountIsVisible = false
        if reduceMotion {
            amountIsVisible = true
        } else {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(10))
                amountIsVisible = true
            }
        }
    }

    /// 阶段3：金额动画消失
    private func startAmountDisappearing() {
        if reduceMotion {
            dotsPhase = .showingDots
            dotsAppearingIndex = 5
            amountIsVisible = false
            return
        }
        amountAnimationTask?.cancel()
        dotsPhase = .amountDisappearing
        amountIsVisible = false

        amountAnimationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(currentEffect.duration + 0.1))
            startDotsAppearing()
        }
    }

    /// 阶段4：圆点从左到右逐个出现
    private func startDotsAppearing() {
        if reduceMotion {
            dotsPhase = .showingDots
            dotsAppearingIndex = 5
            return
        }
        dotAnimationTask?.cancel()
        dotsAppearingIndex = 0
        dotsPhase = .dotsAppearing

        dotAnimationTask = Task { @MainActor in
            for i in 0...5 {
                try? await Task.sleep(for: .milliseconds(60))
                dotsAppearingIndex = i
            }
            try? await Task.sleep(for: .milliseconds(100))
            dotsPhase = .showingDots
        }
    }

    private func refresh() {
        guard let ledger = appContainer.currentLedger else { return }
        viewModel.load(ledger: ledger, context: modelContext, budgetService: appContainer.budgetService)
        viewModel.loadBudget(context: modelContext, budgetService: appContainer.budgetService)
        // 先重置到 0，等一帧再用 spring 驱动 Animatable progress 从左到右填充
        displayBudgetFraction = 0
        displayIncomeFrac = 0
        displayExpenseFrac = 0
        amountIsVisible = true
        let maxRef = max(abs(viewModel.monthlyIncome), abs(viewModel.monthlyExpense))
        let bFrac = viewModel.budgetFraction
        let iFrac = maxRef > 0 ? Double(truncating: (abs(viewModel.monthlyIncome) / maxRef) as NSNumber) : 0
        let eFrac = maxRef > 0 ? Double(truncating: (abs(viewModel.monthlyExpense) / maxRef) as NSNumber) : 0
        withAnimation(.spring(response: 0.8, dampingFraction: 0.65)) {
            self.displayBudgetFraction = bFrac
            self.displayIncomeFrac = iFrac
            self.displayExpenseFrac = eFrac
        }
    }
}

// MARK: - Privacy Placeholder Dot

// MARK: - Dots Reveal Phase

/// 圆点和金额切换的多阶段动画状态机
enum DotsRevealPhase: Equatable {
    case showingDots       // 默认，圆点显示
    case dotsDisappearing  // 圆点逐个消失（开眼睛第一阶段）
    case showingAmount     // 金额显示
    case amountDisappearing // 金额消失（关眼睛第一阶段）
    case dotsAppearing     // 圆点逐个出现（关眼睛第二阶段）
}

/// 金额隐藏动画效果，随机选中一种
enum AmountHideEffect: CaseIterable {
    case gentle    // 柔和淡入淡出
    case slam      // 砸下去消失
    case ripple    // 涟漪扩散消失
    case echo      // 反复放大消失
    case spotlight // 聚光效果

    static var random: AmountHideEffect {
        allCases.randomElement()!
    }
}

/// 每个效果对应的 ViewModifier，isVisible 控制显隐
struct AmountEffectModifier: ViewModifier {
    let effect: AmountHideEffect
    let isVisible: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : effect.scale)
            .offset(y: isVisible ? 0 : effect.offsetY)
            .brightness(isVisible ? 0 : effect.brightness)
            .animation(effect.effectAnimation, value: isVisible)
    }
}

extension AmountHideEffect {
    var effectAnimation: Animation {
        switch self {
        case .gentle:    return .easeInOut(duration: 0.6)
        case .slam:       return .easeIn(duration: 0.15)
        case .ripple:     return .easeOut(duration: 0.35)
        case .echo:       return .easeInOut(duration: 0.4)
        case .spotlight: return .easeInOut(duration: 0.5)
        }
    }

    var duration: Double {
        switch self {
        case .gentle:    return 0.6
        case .slam:       return 0.15
        case .ripple:     return 0.35
        case .echo:       return 0.4
        case .spotlight: return 0.5
        }
    }

    /// 消失时放大/缩小的倍数
    var scale: CGFloat {
        switch self {
        case .gentle:    return 0.8
        case .slam:      return 1.3
        case .ripple:    return 0.5
        case .echo:      return 2.0
        case .spotlight: return 1.0
        }
    }

    /// 消失时的 Y 轴偏移
    var offsetY: CGFloat {
        switch self {
        case .slam:      return -30
        default:         return 0
        }
    }

    /// 消失时的亮度增益
    var brightness: Double {
        switch self {
        case .spotlight: return 0.8
        default:         return 0
        }
    }
}

private struct CircleDot: View {
    @State private var isHovered = false

    var body: some View {
        Circle()
            .fill(Color.designOnSurfaceVariant.opacity(isHovered ? 0.85 : 0.5))
            .frame(width: 12, height: 12)
            .offset(x: 3, y: -4) // 14px圆心对齐24pt字体的x-height中心
            .animation(.easeInOut(duration: 0.25), value: isHovered)
            .onHover { inside in
                isHovered = inside
            }
    }
}
