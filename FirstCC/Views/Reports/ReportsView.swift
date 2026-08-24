import SwiftUI
@preconcurrency import CoreData

enum ReportType: CaseIterable {
    case category
    case trend
    case member

    var label: String {
        switch self {
        case .category: String(localized: "分类占比")
        case .trend: String(localized: "收支趋势")
        case .member: String(localized: "多维分析")
        }
    }

    var supportedPeriods: [ReportPeriod] {
        switch self {
        case .category: [.thisMonth, .thisYear]
        case .trend: [.thisYear, .lastYear]
        case .member: [.thisMonth, .thisYear]
        }
    }

    var defaultPeriod: ReportPeriod {
        switch self {
        case .category: .thisMonth
        case .trend: .lastYear
        case .member: .thisMonth
        }
    }
}

struct ReportsView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @State private var viewModel = ReportViewModel()
    @State private var selectedReport: ReportType = .category
    @State private var selectedTransaction: Transaction?
    @State private var isUsingCustomRange = false
    @State private var customStartDate = Date.now.startOfMonth
    @State private var customEndDate = Date.now
    @State private var selectedDimension: DimensionType = .merchant

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(ReportType.allCases, id: \.self) { type in
                            Button {
                                selectedReport = type
                            } label: {
                                Text(type.label)
                                    .font(.designLabel)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        selectedReport == type
                                            ? Color.designPrimaryContainer.opacity(0.25)
                                            : Color.clear
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .foregroundStyle(
                                selectedReport == type
                                    ? Color.designOnSurface
                                    : Color.designOnSurfaceVariant
                            )
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .glassCard(cornerRadius: 14)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    periodPicker
                    .padding(4)
                    .glassCard(cornerRadius: 14)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    if isUsingCustomRange {
                        customDatePickers
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if selectedReport == .member {
                        dimensionPicker
                            .padding(4)
                            .glassCard(cornerRadius: 14)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }

                    switch selectedReport {
                    case .category:
                        categoryContent
                    case .trend:
                        trendReport
                    case .member:
                        dimensionContent
                    }
                }
            }
            .scrollClipDisabled()
            .navigationTitle("报表")
            .navigationDestination(item: $selectedTransaction) { tx in
                TransactionDetailView(transaction: tx)
            }
        }
        .simultaneousGesture(backSwipe)
        .designScreen()
        .onAppear { loadData() }
        .onChange(of: viewModel.selectedPeriod) { _, _ in
            viewModel.isShowingMemberSplit = false
            loadData()
        }
        .onChange(of: selectedReport) { _, newType in
            viewModel.isShowingMemberSplit = false
            isUsingCustomRange = false
            if !newType.supportedPeriods.contains(viewModel.selectedPeriod) {
                viewModel.selectedPeriod = newType.defaultPeriod
            } else {
                loadData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in
            viewModel.isShowingMemberSplit = false
            loadData()
        }
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        HStack(spacing: 8) {
            ForEach(selectedReport.supportedPeriods, id: \.self) { period in
                Button {
                    isUsingCustomRange = false
                    viewModel.selectedPeriod = period
                } label: {
                    Text(period.label)
                        .font(.custom("JetBrainsMono-Medium", fixedSize: 12))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(periodBackground(for: period))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .foregroundStyle(
                    isPeriodActive(period) ? Color.designOnSurface : Color.designOnSurfaceVariant
                )
                .buttonStyle(.plain)
            }

            // 自定义 button — toggle date pickers with animation
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    if isUsingCustomRange {
                        isUsingCustomRange = false
                    } else {
                        isUsingCustomRange = true
                        if case .customRange = viewModel.selectedPeriod {
                            // reuse existing dates
                        } else {
                            customStartDate = Date.now.startOfMonth
                            customEndDate = Date.now
                        }
                        viewModel.selectedPeriod = .customRange(start: customStartDate, end: customEndDate)
                    }
                }
            } label: {
                Text(String(localized: "自定义"))
                    .font(.custom("JetBrainsMono-Medium", fixedSize: 12))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(isCustomActive ? Color.designPrimaryContainer.opacity(0.2) : Color.designSurfaceContainer.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .foregroundStyle(isCustomActive ? Color.designOnSurface : Color.designOnSurfaceVariant)
            .buttonStyle(.plain)
        }
    }

    private var customDatePickers: some View {
        HStack(spacing: 8) {
            compactDateButton(
                date: $customStartDate,
                in: Date.distantPast...customEndDate
            )
            .onChange(of: customStartDate) { _, newStart in
                viewModel.selectedPeriod = .customRange(start: newStart, end: customEndDate)
            }

            Text("–")
                .font(.custom("JetBrainsMono-Medium", fixedSize: 11))
                .foregroundStyle(Color.designOnSurfaceVariant)

            compactDateButton(
                date: $customEndDate,
                in: customStartDate...Date()
            )
            .onChange(of: customEndDate) { _, newEnd in
                viewModel.selectedPeriod = .customRange(start: customStartDate, end: newEnd)
            }
        }
        .glassCard(cornerRadius: 14)
    }

    /// Custom date label — full-width, system DatePicker overlaid transparently.
    private func compactDateButton(date: Binding<Date>, in range: ClosedRange<Date>) -> some View {
        Text(date.wrappedValue.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)))
            .font(.custom("JetBrainsMono-Medium", fixedSize: 11))
            .foregroundStyle(Color.designOnSurface)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(Color.designSurfaceContainer.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                DatePicker("", selection: date, in: range, displayedComponents: .date)
                    .labelsHidden()
                    .colorMultiply(.clear)
            }
    }

    private func periodBackground(for period: ReportPeriod) -> some View {
        if isPeriodActive(period) {
            Color.designPrimaryContainer.opacity(0.2)
        } else {
            Color.designSurfaceContainer.opacity(0.6)
        }
    }

    private func isPeriodActive(_ period: ReportPeriod) -> Bool {
        if case .customRange = viewModel.selectedPeriod { return false }
        return viewModel.selectedPeriod == period
    }

    private var isCustomActive: Bool {
        if case .customRange = viewModel.selectedPeriod { return true }
        return false
    }

    // MARK: - Swipe Back Gesture

    /// 从屏幕左边缘右滑返回上一级（仅在下钻状态下生效）
    private var backSwipe: some Gesture {
        DragGesture(minimumDistance: 40, coordinateSpace: .global)
            .onEnded { value in
                let isDrilledDown = viewModel.selectedCategoryID != nil || viewModel.selectedMemberID != nil || viewModel.selectedDimensionID != nil
                guard isDrilledDown else { return }
                let isFromLeftEdge = value.startLocation.x < 44
                let isRightSwipe = value.translation.width > 80
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                if isFromLeftEdge && isRightSwipe && isHorizontal {
                    if viewModel.selectedMemberID != nil {
                        viewModel.goBackMember()
                    } else if viewModel.selectedDimensionID != nil {
                        if viewModel.projectSelectedCategoryID != nil {
                            viewModel.goBackProjectLevel()
                        } else {
                            viewModel.goBackDimension()
                        }
                    } else {
                        viewModel.goBack()
                    }
                }
            }
    }

    @ViewBuilder
    private var categoryContent: some View {
        if viewModel.categoryExpenses.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "chart.pie")
                    .font(.largeTitle)
                    .foregroundStyle(Color.designOnSurfaceVariant)
                Text("暂无支出数据")
                    .font(.designBodyMedium)
                    .foregroundStyle(Color.designOnSurfaceVariant)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 120)
        } else {
            let isL1MemberMode = viewModel.isShowingMemberSplit && viewModel.selectedCategoryID == nil
            let isL2MemberMode = viewModel.isShowingMemberSplit && viewModel.selectedCategoryID != nil

            CategoryPieChartView(
                categories: isL1MemberMode ? viewModel.memberDonutCategories : viewModel.displayCategories,
                totalExpense: isL1MemberMode
                    ? viewModel.memberDonutCategories.map(\.amount).reduce(0, +)
                    : viewModel.displayTotal,
                centerTitle: isL1MemberMode
                    ? String(localized: "成员占比")
                    : viewModel.displayTitle,
                isDrilledDown: viewModel.selectedCategoryID != nil,
                onCategoryTap: { id in
                    if !viewModel.isShowingMemberSplit {
                        viewModel.selectCategory(id)
                    }
                },
                onCenterTap: {
                    if viewModel.isShowingMemberSplit {
                        viewModel.isShowingMemberSplit = false
                    } else {
                        viewModel.goBack()
                    }
                },
                onSelectTransaction: { tx in selectedTransaction = tx },
                transactions: (!viewModel.isShowingMemberSplit && viewModel.isShowingTransactions)
                    ? viewModel.displayTransactions : nil,
                memberSplits: viewModel.categoryMemberSplits,
                isMemberSplitOn: $viewModel.isShowingMemberSplit,
                showMemberToggle: true,
                onToggleMemberSplit: {
                    guard let ledger = appContainer.currentLedger else { return }
                    if viewModel.selectedCategoryID == nil {
                        // L1: build member donut categories
                        viewModel.buildMemberDonutCategories(
                            memberService: appContainer.memberService,
                            ledger: ledger,
                            context: modelContext
                        )
                    } else {
                        // L2: compute member splits for current display categories
                        viewModel.computeCategoryMemberSplits(
                            for: viewModel.displayCategories,
                            memberService: appContainer.memberService,
                            ledger: ledger,
                            context: modelContext
                        )
                    }
                },
                memberSplitDonutItems: isL2MemberMode
                    ? ReportViewModel.buildMemberSplitDonutItems(
                        categories: viewModel.displayCategories,
                        splits: viewModel.categoryMemberSplits
                    )
                    : []
            )
            .padding(.vertical, isUsingCustomRange ? 6 : 8)
        }
    }

    @ViewBuilder
    private var trendReport: some View {
        TrendChartView(dataPoints: viewModel.trendData)
    }

    // MARK: - Dimension Picker

    private var dimensionPicker: some View {
        HStack(spacing: 8) {
            ForEach(DimensionType.allCases, id: \.self) { dim in
                Button {
                    selectedDimension = dim
                    loadData()
                } label: {
                    Text(dim.label)
                        .font(.custom("JetBrainsMono-Medium", fixedSize: 12))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selectedDimension == dim ? Color.designPrimaryContainer.opacity(0.2) : Color.designSurfaceContainer.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .foregroundStyle(selectedDimension == dim ? Color.designOnSurface : Color.designOnSurfaceVariant)
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Dimension Content (多维分析)

    @ViewBuilder
    private var dimensionContent: some View {
        if viewModel.dimensionExpenses.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: selectedDimension == .merchant ? "bag" : "folder")
                    .font(.largeTitle)
                    .foregroundStyle(Color.designOnSurfaceVariant)
                Text(selectedDimension == .merchant
                    ? String(localized: "暂无商家支出数据")
                    : String(localized: "暂无项目支出数据"))
                    .font(.designBodyMedium)
                    .foregroundStyle(Color.designOnSurfaceVariant)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 120)
        } else if viewModel.selectedDimensionID != nil, selectedDimension == .merchant {
            // 商家 → 直接展示交易明细
            CategoryPieChartView(
                categories: [],
                totalExpense: viewModel.dimensionDrillDownTransactions.map { $0.netExpenseAmount }.reduce(0, +),
                centerTitle: viewModel.selectedDimensionName,
                isDrilledDown: true,
                onCategoryTap: { _ in },
                onCenterTap: { viewModel.goBackDimension() },
                onSelectTransaction: { tx in selectedTransaction = tx },
                transactions: viewModel.dimensionDrillDownTransactions
            )
            .padding(.vertical, 8)
        } else if viewModel.selectedDimensionID != nil, selectedDimension == .project {
            // 项目 → 层级下钻
            if viewModel.projectIsShowingTransactions {
                // Leaf category → transactions
                CategoryPieChartView(
                    categories: [],
                    totalExpense: viewModel.projectDisplayTransactions.map { $0.netExpenseAmount }.reduce(0, +),
                    centerTitle: viewModel.projectSelectedCategoryName,
                    isDrilledDown: true,
                    onCategoryTap: { _ in },
                    onCenterTap: { viewModel.goBackProjectLevel() },
                    onSelectTransaction: { tx in selectedTransaction = tx },
                    transactions: viewModel.projectDisplayTransactions
                )
                .padding(.vertical, 8)
            } else {
                // Category level
                let cats = viewModel.projectDisplayCategories
                CategoryPieChartView(
                    categories: cats,
                    totalExpense: cats.map(\.amount).reduce(0, +),
                    centerTitle: viewModel.projectSelectedCategoryName,
                    isDrilledDown: viewModel.projectSelectedCategoryID != nil,
                    onCategoryTap: { id in viewModel.selectProjectCategory(id) },
                    onCenterTap: { viewModel.goBackProjectLevel() },
                    onSelectTransaction: { tx in selectedTransaction = tx },
                    transactions: nil
                )
                .padding(.vertical, 8)
            }
        } else {
            // L1: Dimension overview
            CategoryPieChartView(
                categories: viewModel.dimensionExpenses,
                donutCategories: viewModel.dimensionDonutItems,
                totalExpense: viewModel.dimensionDonutItems.map(\.amount).reduce(0, +),
                centerTitle: selectedDimension.label,
                isDrilledDown: false,
                onCategoryTap: { id in
                    guard let ledger = appContainer.currentLedger else { return }
                    // "其他" aggregate entry is not drill-down-able
                    guard viewModel.dimensionExpenses.contains(where: { $0.id == id }) else { return }
                    viewModel.selectDimensionItem(id, type: selectedDimension, categoryService: appContainer.categoryService, ledger: ledger, context: modelContext)
                },
                onCenterTap: {},
                onSelectTransaction: { tx in selectedTransaction = tx },
                transactions: nil
            )
            .padding(.vertical, 8)
        }
    }

    private func loadData() {
        guard let ledger = appContainer.currentLedger else { return }
        switch selectedReport {
        case .category:
            viewModel.load(
                ledger: ledger,
                transactionService: appContainer.transactionService,
                categoryService: appContainer.categoryService,
                context: modelContext
            )
        case .trend:
            viewModel.loadTrendData(
                ledger: ledger,
                transactionService: appContainer.transactionService,
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
