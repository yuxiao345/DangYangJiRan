import SwiftUI
@preconcurrency import CoreData

/// 预算项明细页（Mac）：自绘顶栏 + scope 切换器 + 交易列表。
/// 交易集合由 BudgetService 用与金额统计完全相同的规则与日期区间算好后直接下传，
/// TransactionListContent 既不需要知道 BudgetScope，也不会再自行过滤一遍。
struct BudgetItemTransactionListMacView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    let entry: BudgetItemNavEntry
    /// 返回上一级。由 BudgetBookDetailMacView 清空 navBudgetEntry 完成，
    /// 不依赖 dismiss 在 NavigationStack 里的语义。
    let onBack: () -> Void

    @State private var currentScope: BudgetScope
    @State private var transactions: [Transaction]?

    init(entry: BudgetItemNavEntry, onBack: @escaping () -> Void) {
        self.entry = entry
        self.onBack = onBack
        // entry.scope 只用于决定初始选中项，之后由 currentScope 独立持有
        self._currentScope = State(initialValue: entry.scope)
    }

    private var item: BudgetItem { entry.item }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let transactions {
                // 只下传 preset：分类与日期口径已由 service 按金额同一条路径算好，列表不再自行过滤
                TransactionListContent(
                    selectedDate: .constant(nil),
                    options: [.hideTypeFilter, .hideAddButton, .hideScreenBackground],
                    presetTransactions: transactions
                )
            }
        }
        // 背景在窗口根节点画一次，列表内部已用 .hideScreenBackground 关掉自己的那层
        .designScreen()
        // 系统工具栏整条隐藏：返回按钮的样式由全局 tint 决定，做不成这里要的磨砂圆按钮；
        // 隐藏后内容才能铺满窗口，内沿高光线也才贴得住窗口边缘
        .toolbar(.hidden, for: .windowToolbar)
        .overlay { windowHighlight }
        .task(id: currentScope) { reload() }
        // entry 变化也要重载：id 只含 item+scope，若 SwiftUI 复用了 destination 视图，
        // 只盯 currentScope 会漏掉区间不同的新 entry
        .onChange(of: entry) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in reload() }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(spacing: 10) {
            ZStack {
                titleText
                    .font(.designBodyMedium)
                    .foregroundStyle(Color.designOnSurface)
                HStack {
                    Button {
                        onBack()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(DesignGlassCircleButton())
                    .help("返回")
                    .accessibilityLabel(Text("返回"))
                    Spacer()
                }
            }
            GlassPillToggle(options: BudgetScope.allCases, selection: $currentScope) { scope in
                scope.displayName
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 17)
        .padding(.bottom, 10)
    }

    private var titleText: Text {
        // 分类名是用户数据不翻译，「未分类」是系统文案，所以先取本地化名字再插值
        Text("\(item.category?.name ?? String(localized: "未分类")) · 支出明细")
    }

    /// 窗口内沿 0.5pt 高光线，让整块玻璃像一片有厚度的切片。
    /// macOS sheet 的圆角由系统给，半径对不上时要按实机效果微调。
    private var windowHighlight: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.designGlassBorderHighlight, lineWidth: 0.5)
            .allowsHitTesting(false)
    }

    private func reload() {
        transactions = appContainer.budgetService.expenseTransactions(
            for: item,
            scope: currentScope,
            in: entry.dateRange(for: currentScope),
            context: modelContext
        )
    }
}
