import SwiftUI
@preconcurrency import CoreData

struct MacExportView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var filterType: TransactionType?
    @State private var transactionCount = 0
    @State private var statusMessage: String?

    init() {
        let cal = Calendar.current
        let now = Date.now
        _startDate = State(initialValue: cal.date(byAdding: .month, value: -3, to: now.startOfMonth) ?? now)
        _endDate = State(initialValue: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("数据导出").font(.designHeadlineMedium).foregroundStyle(Color.designOnSurface)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)

            VStack(spacing: 20) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("开始日期：").gridColumnAlignment(.trailing)
                        DatePicker("", selection: $startDate, displayedComponents: .date).labelsHidden()
                    }
                    GridRow {
                        Text("结束日期：")
                        DatePicker("", selection: $endDate, displayedComponents: .date).labelsHidden()
                    }
                    GridRow {
                        Text("交易类型：")
                        Picker("", selection: $filterType) {
                            Text("全部").tag(nil as TransactionType?)
                            ForEach(TransactionType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type as TransactionType?)
                            }
                        }
                        .pickerStyle(.menu).labelsHidden()
                    }
                    GridRow {
                        Text("匹配数量：")
                        Text("\(transactionCount) 笔")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonSizing(.flexible)
                .frame(width: 320)
                .frame(maxWidth: .infinity, alignment: .center)

                if let msg = statusMessage {
                    Text(msg)
                        .font(.designBodyCaption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button { exportCSV() } label: {
                        Label("导出 CSV", systemImage: "doc.text")
                            .frame(minWidth: 140)
                    }
                    .disabled(transactionCount == 0)

                    Button { exportJSON() } label: {
                        Label("导出 JSON", systemImage: "curlybraces")
                            .frame(minWidth: 140)
                    }
                    .disabled(transactionCount == 0)
                }
            }
            .padding(32)
        }
        .frame(minWidth: 420, maxWidth: 560, minHeight: 380)
        .designScreen()
        .onAppear { loadCount() }
        .onChange(of: startDate) { _, _ in loadCount() }
        .onChange(of: endDate) { _, _ in loadCount() }
        .onChange(of: filterType) { _, _ in loadCount() }
    }

    // MARK: - Load Count

    private func loadCount() {
        guard let ledger = appContainer.currentLedger,
              let range = dateRange() else { return }
        var filters = TransactionFilters()
        filters.dateRange = range
        filters.type = filterType
        let results = (try? appContainer.transactionService.fetchTransactions(
            for: ledger, context: modelContext, filters: filters
        )) ?? []
        transactionCount = results.count
    }

    private func dateRange() -> Range<Date>? {
        let cal = Calendar.current
        let lower = startDate.startOfDay
        guard let upper = cal.date(byAdding: .day, value: 1, to: endDate.startOfDay) else { return nil }
        guard lower < upper else { return lower..<max(upper, lower.addingTimeInterval(1)) }
        return lower..<upper
    }

    // MARK: - Fetch

    private func fetchTransactions() -> [Transaction] {
        guard let ledger = appContainer.currentLedger,
              let range = dateRange() else { return [] }
        var filters = TransactionFilters()
        filters.dateRange = range
        filters.type = filterType
        return (try? appContainer.transactionService.fetchTransactions(
            for: ledger, context: modelContext, filters: filters
        )) ?? []
    }

    // MARK: - Export

    private func exportCSV() {
        guard let exportService = appContainer.exportService else {
            statusMessage = "导出服务不可用"
            return
        }
        let transactions = fetchTransactions()
        guard !transactions.isEmpty else {
            statusMessage = "没有匹配的交易"
            return
        }
        guard let url = try? exportService.exportToCSV(transactions: transactions) else {
            statusMessage = "生成 CSV 失败"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        statusMessage = "文件已生成，从 Finder 拖到目标位置即可"
    }

    private func exportJSON() {
        guard let exportService = appContainer.exportService else {
            statusMessage = "导出服务不可用"
            return
        }
        let transactions = fetchTransactions()
        guard !transactions.isEmpty else {
            statusMessage = "没有匹配的交易"
            return
        }
        guard let url = try? exportService.exportToJSON(transactions: transactions) else {
            statusMessage = "生成 JSON 失败"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        statusMessage = "文件已生成，从 Finder 拖到目标位置即可"
    }
}
