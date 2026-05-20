import SwiftUI

struct ExportView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.modelContext) private var modelContext
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var filterType: TransactionType?
    @State private var transactionCount = 0
    @State private var isExporting = false

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    init() {
        let cal = Calendar.current
        let now = Date()
        _startDate = State(initialValue: cal.date(byAdding: .month, value: -3, to: now.startOfMonth) ?? now)
        _endDate = State(initialValue: now)
    }

    var body: some View {
        Form {
            dateSection
            filterSection
            previewSection
            exportSection
        }
        .navigationTitle("数据导出")
        .onAppear { loadCount() }
        .onChange(of: startDate) { _, _ in loadCount() }
        .onChange(of: endDate) { _, _ in loadCount() }
        .onChange(of: filterType) { _, _ in loadCount() }
    }

    // MARK: - Date Range

    private var dateSection: some View {
        Section("时间范围") {
            DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
            DatePicker("结束日期", selection: $endDate, displayedComponents: .date)
        }
    }

    // MARK: - Filter

    private var filterSection: some View {
        Section("筛选") {
            Picker("交易类型", selection: $filterType) {
                Text("全部").tag(nil as TransactionType?)
                ForEach(TransactionType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type as TransactionType?)
                }
            }
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        Section("预览") {
            HStack {
                Text("匹配交易数")
                Spacer()
                Text("\(transactionCount) 笔")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Export

    private var exportSection: some View {
        Section("导出") {
            Button {
                exportCSV()
            } label: {
                HStack {
                    Image(systemName: "doc.text")
                    Text("导出 CSV")
                    Spacer()
                    if isExporting {
                        ProgressView()
                    }
                }
            }
            .disabled(transactionCount == 0 || isExporting)

            Button {
                exportJSON()
            } label: {
                HStack {
                    Image(systemName: "curlybraces")
                    Text("导出 JSON")
                    Spacer()
                }
            }
            .disabled(transactionCount == 0)
        }
    }

    // MARK: - Load Count

    private func loadCount() {
        guard let ledger = appContainer.currentLedger else { return }
        var filters = TransactionFilters()
        let cal = Calendar.current
        filters.dateRange = startDate.startOfDay..<cal.date(byAdding: .day, value: 1, to: endDate.startOfDay)!
        filters.type = filterType
        let results = (try? appContainer.transactionService.fetchTransactions(
            for: ledger, context: modelContext, filters: filters
        )) ?? []
        transactionCount = results.count
    }

    // MARK: - Export Actions

    private func exportCSV() {
        guard let ledger = appContainer.currentLedger,
              let exportService = appContainer.exportService else { return }
        isExporting = true

        var filters = TransactionFilters()
        let cal = Calendar.current
        filters.dateRange = startDate.startOfDay..<cal.date(byAdding: .day, value: 1, to: endDate.startOfDay)!
        filters.type = filterType

        let results = (try? appContainer.transactionService.fetchTransactions(
            for: ledger, context: modelContext, filters: filters
        )) ?? []

        if let url = try? exportService.exportToCSV(transactions: results) {
            exportService.shareURL(url)
        }
        isExporting = false
    }

    private func exportJSON() {
        guard let ledger = appContainer.currentLedger,
              let exportService = appContainer.exportService else { return }

        var filters = TransactionFilters()
        let cal = Calendar.current
        filters.dateRange = startDate.startOfDay..<cal.date(byAdding: .day, value: 1, to: endDate.startOfDay)!
        filters.type = filterType

        let results = (try? appContainer.transactionService.fetchTransactions(
            for: ledger, context: modelContext, filters: filters
        )) ?? []

        if let url = try? exportService.exportToJSON(transactions: results) {
            exportService.shareURL(url)
        }
    }
}
