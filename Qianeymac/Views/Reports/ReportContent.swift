import SwiftUI
@preconcurrency import CoreData

enum ReportType: String, CaseIterable, Identifiable {
    case trend = "收支趋势"
    case category = "分类占比"
    case assets = "资产变化"
    case budget = "预算执行"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .trend: "chart.line.uptrend.xyaxis"
        case .category: "chart.pie"
        case .assets: "chart.bar"
        case .budget: "gauge.with.dots.needle.33percent"
        }
    }

    var supportedPeriods: [ReportPeriod] {
        switch self {
        case .trend:     [.last6Months, .last12Months, .last18Months, .last2Years]
        case .category:  [.thisMonth, .last3Months, .last6Months]
        case .assets:    [.lastYear, .last2Years, .last3Years]
        case .budget:    [.thisMonth, .last3Months]
        }
    }

    var defaultPeriod: ReportPeriod {
        switch self {
        case .trend:     .last6Months
        case .category:  .thisMonth
        case .assets:    .lastYear
        case .budget:    .thisMonth
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
                    onSelectTransaction: nil
                )
            case .assets:
                MacAssetChartView(dataPoints: viewModel.assetData)
            case .budget:
                MacBudgetChartView(
                    items: viewModel.budgetItems,
                    books: viewModel.budgetBooks,
                    selectedBookID: $viewModel.selectedBudgetBookID,
                    dimension: $viewModel.budgetViewDimension
                )
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .designScreen()
        .task(id: reportType) {
            viewModel.selectedPeriod = reportType.defaultPeriod
            loadData()
        }
        .onChange(of: viewModel.selectedPeriod) { _, _ in loadData() }
        .onChange(of: viewModel.selectedBudgetBookID) { _, _ in loadData() }
        .onChange(of: viewModel.budgetViewDimension) { _, _ in loadData() }
        .onChange(of: appContainer.currentLedger?.id) { _, _ in loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in loadData() }
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

    /// 通用顶部选择器：预算→维度，其他报表→时间周期。UI 完全统一。
    private var reportPickerBar: some View {
        HStack(spacing: 0) {
            if reportType == .budget {
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
            } else {
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
                Picker(selection: $startYear) {
                    ForEach(years, id: \.self) { y in Text(String(y)).tag(y) }
                } label: { EmptyView() }
                .pickerStyle(.menu)
                .frame(width: 100)
                Picker(selection: $startMonth) {
                    ForEach(1...12, id: \.self) { m in Text(months[m-1]).tag(m) }
                } label: { EmptyView() }
                .pickerStyle(.menu)
                .frame(width: 90)
            }
            // End row
            HStack(spacing: 10) {
                Picker(selection: $endYear) {
                    ForEach(years, id: \.self) { y in Text(String(y)).tag(y) }
                } label: { EmptyView() }
                .pickerStyle(.menu)
                .frame(width: 100)
                Picker(selection: $endMonth) {
                    ForEach(1...12, id: \.self) { m in Text(months[m-1]).tag(m) }
                } label: { EmptyView() }
                .pickerStyle(.menu)
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
        }
    }
}
