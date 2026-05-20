import SwiftUI
import SwiftData

enum ReportType: CaseIterable {
    case category
    case trend

    var label: String {
        switch self {
        case .category: "分类占比"
        case .trend: "收支趋势"
        }
    }

    var supportedPeriods: [ReportPeriod] {
        switch self {
        case .category: [.thisMonth, .last3Months, .last6Months]
        case .trend: [.last6Months, .lastYear, .last3Years]
        }
    }

    var defaultPeriod: ReportPeriod {
        switch self {
        case .category: .thisMonth
        case .trend: .last6Months
        }
    }
}

struct ReportsView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ReportViewModel()
    @State private var selectedReport: ReportType = .category
    @State private var selectedTransaction: Transaction?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("报表类型", selection: $selectedReport) {
                    ForEach(ReportType.allCases, id: \.self) { type in
                        Text(type.label).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Picker("时段", selection: $viewModel.selectedPeriod) {
                    ForEach(selectedReport.supportedPeriods, id: \.self) { period in
                        Text(period.label).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // Temporary seed button
                Button("生成测试数据") {
                    guard let ledger = appContainer.currentLedger else { return }
                    viewModel.seedTestData(ledger: ledger, context: modelContext)
                }
                .font(.designBodySmall)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

                switch selectedReport {
                case .category:
                    categoryReport
                case .trend:
                    trendReport
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .navigationTitle("报表")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedTransaction) { tx in
                TransactionDetailView(transaction: tx)
            }
        }
        .designScreen()
        .onAppear { loadData() }
        .onChange(of: viewModel.selectedPeriod) { _, _ in loadData() }
        .onChange(of: selectedReport) { _, newType in
            if !newType.supportedPeriods.contains(viewModel.selectedPeriod) {
                viewModel.selectedPeriod = newType.defaultPeriod
            } else {
                loadData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in
            loadData()
        }
    }

    @ViewBuilder
    private var categoryReport: some View {
        if viewModel.categoryExpenses.isEmpty {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "chart.pie")
                    .font(.largeTitle)
                    .foregroundStyle(Color.designOnSurfaceVariant)
                Text("暂无支出数据")
                    .font(.designBodyMedium)
                    .foregroundStyle(Color.designOnSurfaceVariant)
            }
            Spacer()
        } else {
            ScrollView {
                CategoryPieChartView(
                    categories: viewModel.displayCategories,
                    totalExpense: viewModel.displayTotal,
                    centerTitle: viewModel.displayTitle,
                    isDrilledDown: viewModel.selectedCategoryID != nil,
                    onCategoryTap: { viewModel.selectCategory($0) },
                    onCenterTap: { viewModel.selectCategory(nil) },
                    onSelectTransaction: { tx in selectedTransaction = tx },
                    transactions: viewModel.isShowingTransactions ? viewModel.displayTransactions : nil
                )
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private var trendReport: some View {
        TrendChartView(dataPoints: viewModel.trendData, period: viewModel.selectedPeriod)
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
        }
    }
}