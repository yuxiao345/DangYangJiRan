import SwiftUI
@preconcurrency import CoreData

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
        case .trend: [.lastYear, .last2Years, .last3Years]
        }
    }

    var defaultPeriod: ReportPeriod {
        switch self {
        case .category: .thisMonth
        case .trend: .lastYear
        }
    }
}

struct ReportsView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @State private var viewModel = ReportViewModel()
    @State private var selectedReport: ReportType = .category
    @State private var selectedTransaction: Transaction?

    var body: some View {
        NavigationStack {
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

                HStack(spacing: 8) {
                    ForEach(selectedReport.supportedPeriods, id: \.self) { period in
                        Button {
                            viewModel.selectedPeriod = period
                        } label: {
                            Text(period.label)
                                .font(.custom("JetBrainsMono-Medium", fixedSize: 12))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    viewModel.selectedPeriod == period
                                        ? Color.designPrimaryContainer.opacity(0.2)
                                        : Color.designSurfaceContainer.opacity(0.6)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .foregroundStyle(
                            viewModel.selectedPeriod == period
                                ? Color.designOnSurface
                                : Color.designOnSurfaceVariant
                        )
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .glassCard(cornerRadius: 14)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                switch selectedReport {
                case .category:
                    categoryReport
                case .trend:
                    trendReport
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .navigationTitle("报表")
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
                    onCenterTap: { viewModel.goBack() },
                    onSelectTransaction: { tx in selectedTransaction = tx },
                    transactions: viewModel.isShowingTransactions ? viewModel.displayTransactions : nil
                )
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private var trendReport: some View {
        TrendChartView(dataPoints: viewModel.trendData)
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
