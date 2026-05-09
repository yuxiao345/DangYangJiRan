import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CreditCardReconciliationView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.modelContext) private var modelContext

    let account: Account
    @State private var statements: [CreditCardStatement] = []
    @State private var showAddSheet = false

    var body: some View {
        List {
            if statements.isEmpty {
                Text("暂无对账记录，点击右上角 + 添加")
                    .foregroundStyle(.secondary)
            }

            ForEach(yearGroups, id: \.year) { group in
                Section("\(String(group.year))年") {
                    ForEach(group.statements) { stmt in
                        statementRow(stmt)
                    }
                }
            }
        }
        .navigationTitle("对账管理")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet, onDismiss: { loadStatements() }) {
            AddEditStatementView(account: account)
        }
        .task { loadStatements() }
    }

    private var yearGroups: [(year: Int, statements: [CreditCardStatement])] {
        let grouped = Dictionary(grouping: statements) { $0.periodYear }
        return grouped.map { ($0.key, $0.value.sorted { $0.periodMonth > $1.periodMonth }) }
            .sorted { $0.year > $1.year }
    }

    private func statementRow(_ stmt: CreditCardStatement) -> some View {
        let appAmount: Decimal = {
            if stmt.isReconciled, let saved = stmt.reconciledAppAmount {
                return saved
            }
            return appContainer.creditCardStatementService.calculateAppAmount(
                for: account, year: stmt.periodYear, month: stmt.periodMonth, context: modelContext
            )
        }()
        let bankAmount = stmt.statementAmount ?? 0
        let diff = bankAmount + appAmount

        return NavigationLink {
            StatementTransactionsView(account: account, statement: stmt, onUpdate: { loadStatements() })
        } label: {
            VStack(spacing: 6) {
                HStack {
                    Text("\(stmt.periodMonth)月")
                        .font(.headline)
                    Spacer()
                    if stmt.isReconciled {
                        Label("已核对", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else if diff != 0 {
                        Text("差额 ¥\(abs(diff).formatted(.number.precision(.fractionLength(2))))")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fontWeight(.semibold)
                    } else {
                        Text("差额 ¥0")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("银行账单")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        CurrencyText(amount: bankAmount, currencyCode: account.currencyCode, showSign: false, font: .subheadline)
                    }
                    Spacer()
                    VStack(alignment: .center, spacing: 2) {
                        Text("App记账")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        CurrencyText(amount: -appAmount, currencyCode: account.currencyCode, showSign: false, font: .subheadline)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("差额")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        CurrencyText(amount: diff, currencyCode: account.currencyCode, showSign: true, font: .subheadline, foregroundColor: diff == 0 ? .secondary : .red)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func loadStatements() {
        statements = (try? appContainer.creditCardStatementService.fetchStatements(for: account, context: modelContext)) ?? []
    }
}

struct StatementTransactionsView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let account: Account
    let statement: CreditCardStatement
    let onUpdate: () -> Void

    @State private var transactions: [Transaction] = []
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false

    var body: some View {
        List {
            Section("账单金额") {
                let bankAmount = statement.statementAmount ?? 0
                let rawAppAmount = totalAppAmount
                let diff = bankAmount + rawAppAmount

                LabeledContent("银行账单") {
                    CurrencyText(amount: bankAmount, currencyCode: account.currencyCode, showSign: false, font: .body)
                }
                LabeledContent("App记账") {
                    CurrencyText(amount: -rawAppAmount, currencyCode: account.currencyCode, showSign: false, font: .body)
                }
                LabeledContent("差额") {
                    CurrencyText(amount: diff, currencyCode: account.currencyCode, showSign: true, font: .body, foregroundColor: diff == 0 ? .secondary : .red)
                }
            }

            Section("App记账明细") {
                if transactions.isEmpty {
                    Text("该账期内无支出交易")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(transactions) { t in
                        TransactionRowView(transaction: t)
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    HStack {
                        Spacer()
                        Label("删除此对账记录", systemImage: "trash")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("\(statement.periodMonth)月明细")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showEditSheet = true } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $showEditSheet, onDismiss: {
            onUpdate()
            loadTransactions()
        }) {
            AddEditStatementView(account: account, editing: statement)
        }
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                try? appContainer.creditCardStatementService.deleteStatement(statement, context: modelContext)
                onUpdate()
                dismiss()
            }
        } message: {
            Text("删除此对账记录后，该账期内的交易将恢复为“未对账”状态，可重新参与对账。")
        }
        .task { loadTransactions() }
    }

    private var totalAppAmount: Decimal {
        if statement.isReconciled, let saved = statement.reconciledAppAmount {
            return saved
        }
        return transactions.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private func loadTransactions() {
        let billingDay = account.billingDay ?? 1
        let calendar = Calendar.current
        let year = statement.periodYear
        let month = statement.periodMonth

        var prevMonth = month - 1
        var prevYear = year
        if prevMonth < 1 { prevMonth = 12; prevYear -= 1 }

        var startComps = DateComponents(year: prevYear, month: prevMonth, day: billingDay)
        startComps.hour = 0; startComps.minute = 0; startComps.second = 0
        guard let startDate = calendar.date(from: startComps) else { return }

        var endComps = DateComponents(year: year, month: month, day: billingDay)
        endComps.hour = 23; endComps.minute = 59; endComps.second = 59
        guard let endDate = calendar.date(from: endComps) else { return }

        let accountID = account.id
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.account?.id == accountID && $0.isReconciled == false }
        )
        let all = (try? modelContext.fetch(descriptor)) ?? []
        transactions = all.filter { t in
            t.date >= startDate && t.date <= endDate && t.type == .expense
        }.sorted { $0.date > $1.date }
    }
}

struct AddEditStatementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer

    let account: Account
    let editing: CreditCardStatement?

    @State private var selectedYear: Int
    @State private var selectedMonth: Int
    @State private var bankAmount: Decimal = 0

    // CSV import
    @State private var csvData: Data?
    @State private var csvFileName: String = ""
    @State private var showFileImporter = false
    @State private var bankItems: [BankTransactionItem] = []
    @State private var matches: [ReconciliationMatch] = []
    @State private var userActions: [UUID: MatchAction] = [:]
    @State private var isMatching = false

    enum MatchAction {
        case confirmed(Transaction)
        case ignored
        case createNew
    }

    init(account: Account, editing: CreditCardStatement? = nil) {
        self.account = account
        self.editing = editing
        let now = Date()
        let calendar = Calendar.current
        _selectedYear = State(initialValue: editing?.periodYear ?? calendar.component(.year, from: now))
        _selectedMonth = State(initialValue: editing?.periodMonth ?? calendar.component(.month, from: now))
        _bankAmount = State(initialValue: editing?.statementAmount ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                monthSection
                csvSection
                amountSection
                if !matches.isEmpty { matchResultsSection }
                appAmountSection
            }
            .navigationTitle(editing != nil ? "编辑对账" : "新建对账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
        }
    }

    // MARK: - Sections

    private var monthSection: some View {
        Section("账单月份") {
            Picker("年份", selection: $selectedYear) {
                ForEach(2020...2030, id: \.self) { y in
                    Text("\(String(y))年").tag(y)
                }
            }
            Picker("月份", selection: $selectedMonth) {
                ForEach(1...12, id: \.self) { m in
                    Text("\(m)月").tag(m)
                }
            }
        }
    }

    private var csvSection: some View {
        Section("导入银行账单CSV") {
            if let _ = csvData {
                HStack {
                    Label("\(csvFileName)（\(bankItems.count)笔）", systemImage: "tablecells")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("清除") {
                        csvData = nil
                        csvFileName = ""
                        bankItems = []
                        matches = []
                        userActions = [:]
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
                if isMatching {
                    HStack { ProgressView(); Text("匹配中…").font(.caption).foregroundStyle(.secondary) }
                }
            } else {
                Button {
                    showFileImporter = true
                } label: {
                    Label("选择CSV文件", systemImage: "doc.badge.plus")
                }
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, UTType(filenameExtension: "csv") ?? .data]) { result in
            if case .success(let url) = result {
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url) {
                    csvData = data
                    csvFileName = url.lastPathComponent
                    parseAndMatch()
                }
            }
        }
    }

    private var amountSection: some View {
        Section("银行账单金额") {
            HStack {
                Text("¥").foregroundStyle(.secondary)
                TextField("账单金额", value: $bankAmount, format: .number)
                    .keyboardType(.decimalPad)
            }
            if !bankItems.isEmpty {
                let csvTotal = bankItems.compactMap { $0.amount }.reduce(Decimal.zero, +)
                Button("用CSV总额填充: ¥\(abs(csvTotal).formatted(.number.precision(.fractionLength(2))))") {
                    bankAmount = abs(csvTotal)
                }
                .font(.caption)
            }
        }
    }

    // MARK: - Match Results

    private var matchResultsSection: some View {
        Section("对账匹配") {
            // Summary
            HStack(spacing: 12) {
                miniStat("银行", "\(bankItems.count)", .primary)
                miniStat("匹配", "\(matchedCount)", .green)
                miniStat("冲突", "\(conflictedCount)", .orange)
                miniStat("未匹配", "\(unmatchedCount)", .red)
            }
            .padding(.vertical, 2)

            // Matched items (auto-confirmed on save, no action needed)
            ForEach(matches.filter { $0.status == .matched && userActions[$0.id] == nil }) { match in
                matchRow(match)
            }

            // Conflicted items
            ForEach(matches.filter { $0.status == .conflicted && userActions[$0.id] == nil }) { match in
                matchRow(match)
            }

            // Unmatched items
            ForEach(matches.filter { $0.status == .unmatched && userActions[$0.id] == nil }) { match in
                matchRow(match)
            }
        }
    }

    private var appAmountSection: some View {
        Section {
            LabeledContent("App记账金额") {
                CurrencyText(
                    amount: -appAmount,
                    currencyCode: account.currencyCode,
                    showSign: false,
                    font: .body
                )
            }
            LabeledContent("差额") {
                let diff = (bankAmount) + appAmount
                CurrencyText(amount: diff, currencyCode: account.currencyCode, showSign: true, font: .body, foregroundColor: diff == 0 ? .secondary : .red)
            }
        }
    }

    // MARK: - Match Row

    private func matchRow(_ match: ReconciliationMatch) -> some View {
        let action = userActions[match.id]
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let date = match.bankItem.transDate {
                    Text(date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                        .font(.caption)
                        .fontWeight(.medium)
                }
                if let desc = match.bankItem.desc {
                    Text(desc).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if let amount = match.bankItem.amount {
                    Text(amount, format: .number.precision(.fractionLength(2)))
                        .font(.caption).fontWeight(.bold).foregroundStyle(.red)
                }
                matchBadge(match, action: action)
            }

            // Action info
            if let action {
                switch action {
                case .confirmed(let txn):
                    Text("已确认匹配 App: ¥\(abs(txn.amount).formatted(.number.precision(.fractionLength(2))))")
                        .font(.caption2).foregroundStyle(.green)
                case .ignored:
                    Text("已忽略").font(.caption2).foregroundStyle(.secondary)
                case .createNew:
                    Text("将创建新交易").font(.caption2).foregroundStyle(.blue)
                }
            }

            // Action buttons (only for conflicted/unmatched; matched is auto-confirmed on save)
            if action == nil {
                HStack(spacing: 6) {
                    if match.status == .conflicted {
                        ForEach(Array(match.candidates.enumerated()), id: \.element.id) { (i, txn) in
                            Button {
                                userActions[match.id] = .confirmed(txn)
                            } label: {
                                VStack(spacing: 1) {
                                    Text("¥\(abs(txn.amount).formatted(.number.precision(.fractionLength(2))))")
                                        .font(.caption2)
                                    Text(txn.date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                                        .font(.caption2)
                                }
                            }.buttonStyle(.bordered).tint(.blue).controlSize(.mini)
                        }
                    }
                    if match.status == .unmatched {
                        Button { userActions[match.id] = .createNew } label: {
                            Text("创建").font(.caption2)
                        }.buttonStyle(.bordered).tint(.green).controlSize(.mini)
                    }
                    Button { userActions[match.id] = .ignored } label: {
                        Text("忽略").font(.caption2)
                    }.buttonStyle(.bordered).tint(.secondary).controlSize(.mini)
                }
            } else {
                Button("撤销") { userActions.removeValue(forKey: match.id) }
                    .font(.caption2).buttonStyle(.bordered).tint(.orange).controlSize(.mini)
            }
        }
    }

    private func matchBadge(_ match: ReconciliationMatch, action: MatchAction?) -> some View {
        Group {
            if let action {
                switch action {
                case .confirmed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .ignored: Image(systemName: "eye.slash.fill").foregroundStyle(.secondary)
                case .createNew: Image(systemName: "plus.circle.fill").foregroundStyle(.blue)
                }
            } else {
                switch match.status {
                case .matched: Image(systemName: "link").foregroundStyle(.green)
                case .conflicted: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                case .unmatched: Image(systemName: "questionmark.circle").foregroundStyle(.red)
                default: EmptyView()
                }
            }
        }
        .font(.caption)
    }

    private func miniStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.caption).fontWeight(.bold).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Computed

    private var matchedCount: Int { matches.count { $0.status == .matched && userActions[$0.id] == nil } }
    private var conflictedCount: Int { matches.count { $0.status == .conflicted && userActions[$0.id] == nil } }
    private var unmatchedCount: Int { matches.count { $0.status == .unmatched && userActions[$0.id] == nil } }

    private var appAmount: Decimal {
        appContainer.creditCardStatementService.calculateAppAmount(
            for: account, year: selectedYear, month: selectedMonth, context: modelContext
        )
    }

    // MARK: - Actions

    private func parseAndMatch() {
        guard let data = csvData else { return }
        isMatching = true
        bankItems = appContainer.bankOCRService.recognizeTransactions(fromCSV: data)
        let service = ReconciliationServiceImpl()
        matches = service.matchItems(bankItems, for: account, year: selectedYear, month: selectedMonth, context: modelContext)
        // Auto-fill bank amount from CSV total
        let total = bankItems.compactMap { $0.amount }.reduce(Decimal.zero, +)
        if bankAmount == 0 { bankAmount = abs(total) }
        isMatching = false
    }

    private func save() {
        guard let ledger = appContainer.currentLedger else { return }

        if !bankItems.isEmpty {
            // CSV reconciliation flow
            var finalMatches = matches
            for i in finalMatches.indices {
                if let action = userActions[finalMatches[i].id] {
                    switch action {
                    case .confirmed(let txn): finalMatches[i].userAction = .confirmed(txn)
                    case .ignored: finalMatches[i].userAction = .ignored
                    case .createNew: finalMatches[i].userAction = .createNew
                    }
                } else if finalMatches[i].status == .matched, let txn = finalMatches[i].candidates.first {
                    finalMatches[i].userAction = .confirmed(txn)
                }
            }
            let service = ReconciliationServiceImpl()
            _ = try? service.confirmReconciliation(
                matches: finalMatches, account: account,
                year: selectedYear, month: selectedMonth,
                bankAmount: bankAmount, ledger: ledger, context: modelContext
            )
        } else {
            // Manual input flow
            if let stmt = editing {
                stmt.periodYear = selectedYear
                stmt.periodMonth = selectedMonth
                stmt.statementAmount = bankAmount == 0 ? nil : bankAmount
                try? appContainer.creditCardStatementService.updateStatement(stmt, context: modelContext)
            } else {
                let stmt = CreditCardStatement(
                    account: account, periodYear: selectedYear, periodMonth: selectedMonth,
                    statementAmount: bankAmount == 0 ? nil : bankAmount
                )
                try? appContainer.creditCardStatementService.createStatement(stmt, ledger: ledger, context: modelContext)
            }
        }
        dismiss()
    }
}
