import SwiftUI
@preconcurrency import CoreData

enum ReportType: String, CaseIterable, Identifiable {
    case trend = "收支趋势"
    case category = "分类占比"
    case assets = "资产变化"
    case budget = "预算执行"
    case allocation = "资产配置"
    case member = "多维分析"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .trend: "chart.line.uptrend.xyaxis"
        case .category: "chart.pie"
        case .assets: "chart.bar"
        case .budget: "gauge.with.dots.needle.33percent"
        case .allocation: "wallet.pass"
        case .member: "chart.pie"
        }
    }

    var supportedPeriods: [ReportPeriod] {
        switch self {
        case .trend:     [.last6Months, .last12Months, .last18Months, .last2Years]
        case .category:  [.thisMonth, .last3Months, .last6Months]
        case .assets:    [.lastYear, .last2Years, .last3Years]
        case .budget:    [.thisMonth, .last3Months]
        case .allocation: [.thisMonth]
        case .member:    [.thisMonth, .thisYear]
        }
    }

    var defaultPeriod: ReportPeriod {
        switch self {
        case .trend:     .last6Months
        case .category:  .thisMonth
        case .assets:    .lastYear
        case .budget:    .thisMonth
        case .allocation: .thisMonth
        case .member:    .thisMonth
        }
    }
}

// MARK: - Report Detail Container

struct ReportDetailContent: View {
    let reportType: ReportType

    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext

    @State private var viewModel = ReportViewModel()
    @State private var showCustomRange = false
    @State private var bookPickerHighlighted = false
    @State private var selectedDimension: DimensionType = .merchant

    // Custom range: year + month state
    @State private var startYear = Calendar.current.component(.year, from: Self.defaultStartDate)
    @State private var startMonth = Calendar.current.component(.month, from: Self.defaultStartDate)
    @State private var endYear = Calendar.current.component(.year, from: Date())
    @State private var endMonth = Calendar.current.component(.month, from: Date())

    private static var defaultStartDate: Date {
        Calendar.current.date(byAdding: .month, value: -12, to: Date()) ?? Date()
    }

    var body: some View {
        VStack(spacing: 0) {
            reportPickerBar

            switch reportType {
            case .trend:
                MacTrendChartView(dataPoints: viewModel.trendData)
            case .category:
                MacCategoryChartView(
                    categories: viewModel.displayCategories,
                    totalExpense: viewModel.displayTotal,
                    centerTitle: viewModel.displayTitle,
                    isDrilledDown: viewModel.selectedCategoryID != nil,
                    isShowingTransactions: viewModel.isShowingTransactions,
                    transactions: viewModel.displayTransactions,
                    categoryType: $viewModel.categoryType,
                    onCategoryTap: { viewModel.selectCategory($0) },
                    onCenterTap: { viewModel.goBack() },
                    onSelectTransaction: nil,
                    isMemberSplitOn: $viewModel.isShowingMemberSplit,
                    memberDonutCategories: viewModel.memberDonutCategories,
                    memberTotalExpense: viewModel.memberDonutCategories.map(\.amount).reduce(0, +),
                    memberSplits: viewModel.categoryMemberSplits,
                    onToggleMemberSplit: {
                        guard let ledger = appContainer.currentLedger else { return }
                        if viewModel.selectedCategoryID == nil {
                            viewModel.buildMemberDonutCategories(
                                memberService: appContainer.memberService,
                                ledger: ledger,
                                context: modelContext
                            )
                        } else {
                            viewModel.computeCategoryMemberSplits(
                                for: viewModel.displayCategories,
                                memberService: appContainer.memberService,
                                ledger: ledger,
                                context: modelContext
                            )
                        }
                    }
                )
            case .assets:
                MacAssetChartView(dataPoints: viewModel.assetData)
            case .budget:
                MacBudgetChartView(
                    items: viewModel.budgetItems,
                    books: viewModel.budgetBooks,
                    overviewSummary: viewModel.overviewSummary,
                    dailyTrendByCategory: viewModel.dailyTrendByCategory,
                    burnRateData: viewModel.burnRateData,
                    selectedBookID: $viewModel.selectedBudgetBookID,
                    dimension: $viewModel.budgetViewDimension
                )
            case .allocation:
                MacAssetAllocationView(
                    items: viewModel.allocationData,
                    netWorth: viewModel.totalAllocationNetWorth,
                    filter: $viewModel.allocationFilter
                )
            case .member:
                dimensionContent
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .designScreen()
        .task(id: reportType) {
            viewModel.isShowingMemberSplit = false
            showCustomRange = false
            viewModel.selectedPeriod = reportType.defaultPeriod
            loadData()
        }
        .onChange(of: viewModel.selectedPeriod) { _, _ in
            viewModel.isShowingMemberSplit = false
            loadData()
        }
        .onChange(of: viewModel.selectedBudgetBookID) { _, _ in loadData() }
        .onChange(of: viewModel.budgetViewDimension) { _, _ in loadData() }
        .onChange(of: selectedDimension) { _, _ in loadData() }
        .onChange(of: appContainer.currentLedger?.id) { _, _ in
            viewModel.isShowingMemberSplit = false
            loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in
            viewModel.isShowingMemberSplit = false
            loadData()
        }
        #if DEBUG
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    guard let ledger = appContainer.currentLedger else { return }
                    viewModel.seedTestData(ledger: ledger, context: modelContext)
                    loadData()
                } label: {
                    Label("Seed", systemImage: "ant.fill")
                }
                .help("Generate 3 years of test data")
            }
        }
        #endif
    }

    // MARK: - Report Picker Bar (period or dimension)

    @Namespace private var pillAnim

    /// 通用顶部选择器：预算→维度，资产配置→筛选器，其他报表→时间周期。UI 完全统一。
    private var reportPickerBar: some View {
        HStack(spacing: 0) {
            if reportType == .allocation {
                ForEach(AllocationFilter.allCases, id: \.self) { option in
                    pickerButton(
                        label: option.label,
                        isActive: viewModel.allocationFilter == option,
                        action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.allocationFilter = option
                            }
                        }
                    )
                }
            } else if reportType == .budget {
                ForEach(BudgetViewDimension.allCases, id: \.self) { dim in
                    pickerButton(
                        label: dim.label,
                        isActive: viewModel.budgetViewDimension == dim,
                        action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.budgetViewDimension = dim
                            }
                        }
                    )
                }

                // 预算计划选择器（pill 最右端）
                if !viewModel.budgetBooks.isEmpty {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1, height: 16)
                        .padding(.horizontal, 4)

                    Menu {
                        ForEach(viewModel.budgetBooks, id: \.id) { book in
                            Button {
                                bookPickerHighlighted = true
                                viewModel.selectedBudgetBookID = book.id
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    viewModel.budgetViewDimension = .overall
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        bookPickerHighlighted = false
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(book.name)
                                    if book.id == viewModel.selectedBudgetBookID {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Text(viewModel.budgetBookName)
                            .lineLimit(1)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(
                                bookPickerHighlighted ? Color.designOnSurface : Color.designOnSurfaceVariant.opacity(0.7)
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                            .background {
                                if bookPickerHighlighted {
                                    Capsule()
                                        .fill(Color.white.opacity(0.06))
                                        .background(.regularMaterial, in: Capsule())
                                        .overlay { Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1) }
                                }
                            }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            } else if reportType == .member {
                periodPillsWithCustomRange
            } else {
                periodPillsWithCustomRange
            }
        }
        .padding(4)
        .background { Capsule().fill(Color.designGlassBg) }
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .overlay {
            Capsule().stroke(Color.white.opacity(0.04), lineWidth: 1).padding(1)
        }
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    private func pickerButton(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    isActive ? Color.designOnSurface : Color.designOnSurfaceVariant.opacity(0.7)
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .background(pillBackground(active: isActive))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var periodPillsWithCustomRange: some View {
        ForEach(reportType.supportedPeriods, id: \.self) { period in
            pickerButton(
                label: period.label,
                isActive: viewModel.selectedPeriod == period && !isCustomPeriod,
                action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewModel.selectedPeriod = period
                    }
                }
            )
        }

        Button {
            showCustomRange = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                if isCustomPeriod {
                    Text(customRangeLabel)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(
                isCustomPeriod ? Color.designOnSurface : Color.designOnSurfaceVariant.opacity(0.7)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(pillBackground(active: isCustomPeriod))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showCustomRange) {
            customRangePopover
        }
    }

    @ViewBuilder
    private func pillBackground(active: Bool) -> some View {
        if active {
            Capsule()
                .fill(Color.white.opacity(0.06))
                .background(.regularMaterial, in: Capsule())
                .overlay { Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1) }
                .matchedGeometryEffect(id: "reportPill", in: pillAnim)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
    }

    private var isCustomPeriod: Bool {
        if case .customRange = viewModel.selectedPeriod { return true }
        return false
    }

    private var customRangeLabel: String {
        String(format: "%d/%02d - %d/%02d", startYear, startMonth, endYear, endMonth)
    }

    private var customRangePopover: some View {
        let cal = Calendar.current
        let thisYear = cal.component(.year, from: Date())
        let years = Array((thisYear - 5)...thisYear)
        let months = cal.monthSymbols

        return VStack(spacing: 14) {
            Text("选择日期范围").font(.designBodyMedium)

            // Start row
            HStack(spacing: 10) {
                dateMenu(title: String(startYear), items: years.map { (String($0), $0) }, selection: $startYear)
                    .frame(width: 100)
                dateMenu(title: months[startMonth - 1], items: Array(zip(months, 1...12)), selection: $startMonth)
                    .frame(width: 90)
            }
            // End row
            HStack(spacing: 10) {
                dateMenu(title: String(endYear), items: years.map { (String($0), $0) }, selection: $endYear)
                    .frame(width: 100)
                dateMenu(title: months[endMonth - 1], items: Array(zip(months, 1...12)), selection: $endMonth)
                    .frame(width: 90)
            }

            HStack {
                Button("取消") { showCustomRange = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.designOnSurfaceVariant)
                Spacer()
                Button("应用") {
                    let startDate = cal.date(from: DateComponents(year: startYear, month: startMonth, day: 1)) ?? Date()
                    let endDate = cal.date(from: DateComponents(year: endYear, month: endMonth, day: 1))?.endOfMonth ?? Date()
                    viewModel.selectedPeriod = .customRange(
                        start: startDate,
                        end: Calendar.current.date(byAdding: .day, value: 1, to: endDate) ?? endDate
                    )
                    showCustomRange = false
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.designPrimaryContainer)
            }
        }
        .padding()
    }

    /// 带标签样式的日期选择 Menu，浅色/深色模式均可读
    private func dateMenu<T: Hashable>(title: String, items: [(String, T)], selection: Binding<T>) -> some View {
        Menu {
            ForEach(items, id: \.1) { label, value in
                Button(label) { selection.wrappedValue = value }
            }
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(Color.designOnSurface)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.designSurfaceContainer)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.designGlassBorderHighlight, lineWidth: 1)
                    }
            }
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Placeholder

    private func placeholderView(title: String, icon: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 48))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
            Text(title).font(.designHeadlineMedium).foregroundStyle(Color.designOnSurfaceVariant)
            Text("即将上线").font(.designBodyCaption)
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Dimension Content (多维分析)

    @ViewBuilder
    private var dimensionContent: some View {
        if viewModel.projectIsShowingTransactions {
            // State 1a: Project leaf category → transaction detail
            MacDimensionChartView(
                donutItems: [],
                allItems: [],
                totalExpense: 0,
                title: "",
                selectedDimension: $selectedDimension,
                isDrilledDown: true,
                transactions: viewModel.projectDisplayTransactions,
                drillDownTitle: viewModel.projectSelectedCategoryName,
                drillDownTotal: viewModel.projectDisplayTransactions.map { $0.netExpenseAmount }.reduce(0, +),
                drillDownCategories: [],
                onCategoryTap: { _ in },
                onCenterTap: { viewModel.goBackProjectLevel() },
                onDrillDownCategoryTap: { _ in }
            )
        } else if viewModel.selectedDimensionID != nil && selectedDimension == .merchant {
            // State 1b: Merchant drill-down → transaction detail
            MacDimensionChartView(
                donutItems: [],
                allItems: [],
                totalExpense: 0,
                title: "",
                selectedDimension: $selectedDimension,
                isDrilledDown: true,
                transactions: viewModel.dimensionDrillDownTransactions,
                drillDownTitle: viewModel.selectedDimensionName,
                drillDownTotal: viewModel.dimensionDrillDownTransactions.map { $0.netExpenseAmount }.reduce(0, +),
                drillDownCategories: [],
                onCategoryTap: { _ in },
                onCenterTap: { viewModel.goBackDimension() },
                onDrillDownCategoryTap: { _ in }
            )
        } else if viewModel.selectedDimensionID != nil && selectedDimension == .project {
            // State 2: Project category drill-down
            let cats = viewModel.projectDisplayCategories
            MacDimensionChartView(
                donutItems: [],
                allItems: [],
                totalExpense: 0,
                title: "",
                selectedDimension: $selectedDimension,
                isDrilledDown: true,
                transactions: [],
                drillDownTitle: viewModel.projectSelectedCategoryName,
                drillDownTotal: cats.map(\.amount).reduce(0, +),
                drillDownCategories: cats,
                onCategoryTap: { _ in },
                onCenterTap: { viewModel.goBackProjectLevel() },
                onDrillDownCategoryTap: { viewModel.selectProjectCategory($0) }
            )
        } else {
            // State 3: L1 Dimension overview
            MacDimensionChartView(
                donutItems: viewModel.dimensionDonutItems,
                allItems: viewModel.dimensionExpenses,
                totalExpense: viewModel.dimensionDonutItems.map(\.amount).reduce(0, +),
                title: selectedDimension.label,
                selectedDimension: $selectedDimension,
                isDrilledDown: false,
                transactions: [],
                drillDownTitle: "",
                drillDownTotal: 0,
                drillDownCategories: [],
                onCategoryTap: { id in
                    guard let ledger = appContainer.currentLedger else { return }
                    guard viewModel.dimensionExpenses.contains(where: { $0.id == id }) else { return }
                    viewModel.selectDimensionItem(
                        id,
                        type: selectedDimension,
                        categoryService: appContainer.categoryService,
                        ledger: ledger,
                        context: modelContext
                    )
                },
                onCenterTap: {},
                onDrillDownCategoryTap: { _ in }
            )
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let ledger = appContainer.currentLedger else { return }
        switch reportType {
        case .trend:
            viewModel.loadTrendData(
                ledger: ledger,
                transactionService: appContainer.transactionService,
                context: modelContext
            )
        case .category:
            viewModel.load(
                ledger: ledger,
                transactionService: appContainer.transactionService,
                categoryService: appContainer.categoryService,
                context: modelContext
            )
        case .assets:
            viewModel.loadAssetsData(
                ledger: ledger,
                accountService: appContainer.accountService,
                context: modelContext
            )
        case .budget:
            viewModel.loadBudgetData(
                ledger: ledger,
                budgetService: appContainer.budgetService,
                context: modelContext
            )
        case .allocation:
            viewModel.loadAllocationData(
                ledger: ledger,
                accountService: appContainer.accountService,
                context: modelContext
            )
        case .member:
            viewModel.loadDimensionData(
                type: selectedDimension,
                ledger: ledger,
                transactionService: appContainer.transactionService,
                merchantService: appContainer.merchantService,
                projectService: appContainer.projectService,
                categoryService: appContainer.categoryService,
                context: modelContext
            )
        }
    }
}
