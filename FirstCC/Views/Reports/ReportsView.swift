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
        case .member: String(localized: "成员支出")
        }
    }

    var supportedPeriods: [ReportPeriod] {
        switch self {
        case .category: [.thisMonth, .thisYear]
        case .trend: [.lastYear, .last2Years, .last3Years]
        case .member: [.thisMonth, .last3Months, .last6Months, .lastYear]
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
    @State private var customStartDate = Date().startOfMonth
    @State private var customEndDate = Date()

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
                    .padding(.vertical, 8)

                    if isUsingCustomRange {
                        customDatePickers
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }

                    switch selectedReport {
                    case .category:
                        categoryContent
                    case .trend:
                        trendReport
                    case .member:
                        memberContent
                    }
                }
            }
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

            // 自定义 button — toggle date pickers, keep data on hide
            Button {
                if isUsingCustomRange {
                    isUsingCustomRange = false
                } else {
                    isUsingCustomRange = true
                    if case .customRange = viewModel.selectedPeriod {
                        // reuse existing dates
                    } else {
                        customStartDate = Date().startOfMonth
                        customEndDate = Date()
                    }
                    viewModel.selectedPeriod = .customRange(start: customStartDate, end: customEndDate)
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
        HStack(spacing: 12) {
            DatePicker(
                String(localized: "起始日期"),
                selection: $customStartDate,
                in: ...customEndDate,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .font(.custom("JetBrainsMono-Medium", fixedSize: 11))
            .onChange(of: customStartDate) { _, newStart in
                viewModel.selectedPeriod = .customRange(start: newStart, end: customEndDate)
            }

            Text("–")
                .font(.custom("JetBrainsMono-Medium", fixedSize: 11))
                .foregroundStyle(Color.designOnSurfaceVariant)

            DatePicker(
                String(localized: "截止日期"),
                selection: $customEndDate,
                in: customStartDate...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .font(.custom("JetBrainsMono-Medium", fixedSize: 11))
            .onChange(of: customEndDate) { _, newEnd in
                viewModel.selectedPeriod = .customRange(start: customStartDate, end: newEnd)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassCard(cornerRadius: 14)
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
                let isDrilledDown = viewModel.selectedCategoryID != nil || viewModel.selectedMemberID != nil
                guard isDrilledDown else { return }
                // 仅响应从左边缘发起的水平右滑
                let isFromLeftEdge = value.startLocation.x < 44
                let isRightSwipe = value.translation.width > 80
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                if isFromLeftEdge && isRightSwipe && isHorizontal {
                    if viewModel.selectedMemberID != nil {
                        viewModel.goBackMember()
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
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var trendReport: some View {
        TrendChartView(dataPoints: viewModel.trendData)
    }

    // MARK: - Member Content

    @ViewBuilder
    private var memberContent: some View {
        if viewModel.memberExpenses.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "person.2")
                    .font(.largeTitle)
                    .foregroundStyle(Color.designOnSurfaceVariant)
                Text(String(localized: "暂无成员支出数据"))
                    .font(.designBodyMedium)
                    .foregroundStyle(Color.designOnSurfaceVariant)
                Text(String(localized: "记一笔时点击\"成员\"可为交易标记成员"))
                    .font(.designBodySmall)
                    .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 120)
        } else if viewModel.selectedMemberID != nil {
            // L2: Member category drill-down (data pre-computed in ViewModel)
            CategoryPieChartView(
                categories: viewModel.memberCategoryExpenses,
                totalExpense: viewModel.memberCategoryExpenses.map(\.amount).reduce(0, +),
                centerTitle: viewModel.selectedMemberName,
                isDrilledDown: true,
                onCategoryTap: { _ in },
                onCenterTap: { viewModel.goBackMember() },
                onSelectTransaction: { tx in selectedTransaction = tx },
                transactions: nil
            )
            .padding(.vertical, 8)
        } else {
            // L1 + L3: Member overview + cross table
            ScrollView {
                VStack(spacing: 12) {
                    MemberPieChartView(
                        members: viewModel.memberExpenses,
                        onMemberTap: { mid in
                            guard let ledger = appContainer.currentLedger else { return }
                            viewModel.selectMember(
                                mid,
                                categoryService: appContainer.categoryService,
                                ledger: ledger,
                                context: modelContext
                            )
                        }
                    )

                    if !viewModel.memberCategoryCross.isEmpty {
                        MemberCategoryCrossView(items: viewModel.memberCategoryCross)
                    }
                }
                .padding(.vertical, 8)
            }
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
            viewModel.loadMemberData(
                ledger: ledger,
                transactionService: appContainer.transactionService,
                categoryService: appContainer.categoryService,
                memberService: appContainer.memberService,
                context: modelContext
            )
        }
    }
}
