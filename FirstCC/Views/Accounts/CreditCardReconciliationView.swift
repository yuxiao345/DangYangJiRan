import SwiftUI
@preconcurrency import CoreData
import UniformTypeIdentifiers

struct CreditCardReconciliationView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext

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
                .accessibilityLabel(Text("添加对账单"))
            }
        }
        .sheet(isPresented: $showAddSheet, onDismiss: { loadStatements() }) {
            AddEditStatementView(account: account)
        }
        .task { loadStatements() }
    }

    private var yearGroups: [(year: Int64, statements: [CreditCardStatement])] {
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
                for: account, year: Int(stmt.periodYear), month: Int(stmt.periodMonth), context: modelContext
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
                        .font(.designHeadlineMedium)
                    Spacer()
                    if stmt.isReconciled {
                        Label("已核对", systemImage: "checkmark.circle.fill")
                            .font(.designBodySmall)
                            .foregroundStyle(Color.designPrimaryFixedDim)
                    } else if diff != 0 {
                        Text("差额 ¥\(abs(diff).formatted(.number.precision(.fractionLength(2))))")
                            .font(.designBodySmall)
                            .foregroundStyle(.red)
                            .fontWeight(.semibold)
                    } else {
                        Text("差额 \(CurrencyFormatter.formatDecimal(amount: 0, currencyCode: account.currencyCode))")
                            .font(.designBodySmall)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("银行账单")
                            .font(.designBodySmall)
                            .foregroundStyle(.secondary)
                        CurrencyText(amount: bankAmount, currencyCode: account.currencyCode, showSign: false, size: 15)
                    }
                    Spacer()
                    VStack(alignment: .center, spacing: 2) {
                        Text("App记账")
                            .font(.designBodySmall)
                            .foregroundStyle(.secondary)
                        CurrencyText(amount: -appAmount, currencyCode: account.currencyCode, showSign: false, size: 15)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("差额")
                            .font(.designBodySmall)
                            .foregroundStyle(.secondary)
                        CurrencyText(amount: diff, currencyCode: account.currencyCode, showSign: true, size: 15, foregroundColor: diff == 0 ? .secondary : .red)
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
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
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
                    CurrencyText(amount: bankAmount, currencyCode: account.currencyCode, showSign: false, size: 17)
                }
                LabeledContent("App记账") {
                    CurrencyText(amount: -rawAppAmount, currencyCode: account.currencyCode, showSign: false, size: 17)
                }
                LabeledContent("差额") {
                    CurrencyText(amount: diff, currencyCode: account.currencyCode, showSign: true, size: 17, foregroundColor: diff == 0 ? .secondary : .red)
                }
            }

            Section("App记账明细") {
                if transactions.isEmpty {
                    Text("该账期内无支出交易")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(transactions, id: \.objectID) { t in
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
                .accessibilityLabel(Text("编辑对账单"))
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
        return transactions.reduce(Decimal.zero) { $0 + $1.ledgerAmount }
    }

    private func loadTransactions() {
        guard let period = CreditCardStatementPeriod(
            billingDay: account.billingDay == 0 ? 1 : Int(account.billingDay),
            year: Int(statement.periodYear),
            month: Int(statement.periodMonth)
        ) else {
            transactions = []
            return
        }

        let accountID = account.id
        let fetch = NSFetchRequest<Transaction>(entityName: "Transaction")
        fetch.predicate = NSPredicate(format: "account.id == %@ AND parentTransaction == nil", accountID as CVarArg)
        fetch.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        let accountTxns = (try? modelContext.fetch(fetch)) ?? []
        transactions = accountTxns.filter { $0.type == .expense && period.contains($0.date) }
    }
}

struct AddEditStatementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer

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
    @State private var editingTransaction: Transaction?
    @State private var unmatchedAppTxns: [Transaction] = []

    enum MatchAction {
        case confirmed(Transaction)
        case ignored
        case createNew
    }

    init(account: Account, editing: CreditCardStatement? = nil) {
        self.account = account
        self.editing = editing
        let now = Date.now
        let calendar = Calendar.current
        _selectedYear = State(initialValue: Int(editing?.periodYear ?? Int64(calendar.component(.year, from: now))))
        _selectedMonth = State(initialValue: Int(editing?.periodMonth ?? Int64(calendar.component(.month, from: now))))
        _bankAmount = State(initialValue: editing?.statementAmount ?? 0)
        _csvData = State(initialValue: nil)
        _csvFileName = State(initialValue: editing?.bankCSVFileName?.components(separatedBy: "/").last ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                monthSection
                csvSection
                amountSection
                if !matches.isEmpty { matchResultsSection }
                if !unmatchedAppTxns.isEmpty { unmatchedAppSection }
                appAmountSection
                confirmSection
            }
            .navigationTitle(editing != nil ? "编辑对账" : "新建对账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .task { loadEditingCSV() }
            .sheet(item: $editingTransaction, onDismiss: { parseAndMatch() }) { txn in
                AddEditTransactionView(editing: txn)
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
                        .foregroundStyle(Color.designPrimaryFixedDim)
                    Spacer()
                    Button("清除") {
                        csvData = nil
                        csvFileName = ""
                        bankItems = []
                        matches = []
                        userActions = [:]
                    }
                    .font(.designBodySmall)
                    .foregroundStyle(.red)
                }
                if isMatching {
                    HStack { ProgressView(); Text("匹配中…").font(.designBodySmall).foregroundStyle(.secondary) }
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
                Text(CurrencyFormatter.currencySymbol(for: account.currencyCode)).foregroundStyle(.secondary)
                TextField("账单金额", value: $bankAmount, format: .number)
                    .keyboardType(.decimalPad)
            }
            if !bankItems.isEmpty {
                let csvTotal = bankItems.compactMap { $0.amount }.reduce(Decimal.zero, +)
                Button("用CSV总额填充: ¥\(abs(csvTotal).formatted(.number.precision(.fractionLength(2))))") {
                    bankAmount = abs(csvTotal)
                }
                .font(.designBodySmall)
            }
        }
    }

    // MARK: - Match Results

    private var matchResultsSection: some View {
        Section("对账匹配") {
            HStack(spacing: 12) {
                miniStat("银行", "\(bankItems.count)", .primary)
                miniStat("匹配", "\(matchedCount)", .green)
                miniStat("日期疑", "\(suspectedDateCount)", .orange)
                miniStat("金额疑", "\(suspectedAmountCount)", .yellow)
                miniStat("未匹配", "\(unmatchedCount)", .red)
            }
            .padding(.vertical, 2)

            ForEach(visibleMatches) { match in
                matchRow(match)
            }
        }
    }

    private var unmatchedAppSection: some View {
        Section("App未匹配明细（\(unmatchedAppTxns.count)笔）") {
            ForEach(unmatchedAppTxns) { txn in
                Button {
                    editingTransaction = txn
                } label: {
                    HStack {
                        Text(txn.date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                            .font(.designBodySmall)
                            .fontWeight(.medium)
                        if let note = txn.note, !note.isEmpty {
                            Text(note).font(.designBodySmall).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(txn.amount, format: .number.precision(.fractionLength(2)))
                            .font(.designBodySmall.weight(.bold)).foregroundStyle(.red)
                        Image(systemName: "pencil.circle")
                            .font(.designBodySmall)
                            .foregroundStyle(Color.designPrimaryContainer)
                    }
                }
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
                    size: 17
                )
            }
            LabeledContent("差额") {
                let diff = (bankAmount) + appAmount
                CurrencyText(amount: diff, currencyCode: account.currencyCode, showSign: true, size: 17, foregroundColor: diff == 0 ? .secondary : .red)
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
                        .font(.designBodySmall)
                        .fontWeight(.medium)
                }
                if let desc = match.bankItem.desc {
                    Text(desc).font(.designBodySmall).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if let amount = match.bankItem.amount {
                    Text(amount, format: .number.precision(.fractionLength(2)))
                        .font(.designBodySmall.weight(.bold)).foregroundStyle(.red)
                }
                matchBadge(match, action: action)
            }

            // Action info
            if let action {
                switch action {
                case .confirmed(let txn):
                    Text("已确认匹配 App: ¥\(abs(txn.amount).formatted(.number.precision(.fractionLength(2))))")
                        .font(.designBodySmall).foregroundStyle(Color.designPrimaryFixedDim)
                case .ignored:
                    Text("已忽略").font(.designBodySmall).foregroundStyle(.secondary)
                case .createNew:
                    Text("将创建新交易").font(.designBodySmall).foregroundStyle(Color.designPrimaryContainer)
                }
            }

            // Action buttons
            if action == nil {
                HStack(spacing: 6) {
                    if match.status == .conflicted {
                        ForEach(Array(match.candidates.enumerated()), id: \.element.id) { (i, txn) in
                            Button {
                                userActions[match.id] = .confirmed(txn)
                            } label: {
                                VStack(spacing: 1) {
                                    Text("¥\(abs(txn.amount).formatted(.number.precision(.fractionLength(2))))")
                                        .font(.designBodySmall)
                                    Text(txn.date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                                        .font(.designBodySmall)
                                }
                            }.buttonStyle(.bordered).tint(.blue).controlSize(.mini)
                        }
                    }
                    if match.status == .suspectedDateMismatch || match.status == .suspectedAmountMismatch {
                        if let txn = match.candidates.first {
                            Button {
                                editingTransaction = txn
                            } label: {
                                VStack(spacing: 1) {
                                    HStack(spacing: 2) {
                                        Image(systemName: "pencil")
                                        Text("编辑")
                                    }
                                    .font(.designBodySmall)
                                    Text(suspectedHint(for: match))
                                        .font(.designBodySmall)
                                        .foregroundStyle(.orange)
                                }
                            }.buttonStyle(.bordered).tint(.orange).controlSize(.mini)
                        }
                    }
                    if match.status == .unmatched {
                        Button {
                            let newTxn = Transaction(
                                type: .expense,
                                amount: match.bankItem.amount ?? 0,
                                currencyCode: account.currencyCode,
                                note: match.bankItem.desc,
                                date: match.bankItem.transDate ?? Date(),
                                context: modelContext
                            )
                            newTxn.account = account
                            newTxn.ledger = appContainer.currentLedger
                            try? modelContext.save()
                            editingTransaction = newTxn
                        } label: {
                            Text("创建").font(.designBodySmall)
                        }.buttonStyle(.bordered).tint(.green).controlSize(.mini)
                    }
                    Button { userActions[match.id] = .ignored } label: {
                        Text("忽略").font(.designBodySmall)
                    }.buttonStyle(.bordered).tint(.secondary).controlSize(.mini)
                }
            } else {
                Button("撤销") { userActions.removeValue(forKey: match.id) }
                    .font(.designBodySmall).buttonStyle(.bordered).tint(.orange).controlSize(.mini)
            }
        }
    }

    private func matchBadge(_ match: ReconciliationMatch, action: MatchAction?) -> some View {
        Group {
            if let action {
                switch action {
                case .confirmed: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.designPrimaryFixedDim)
                case .ignored: Image(systemName: "eye.slash.fill").foregroundStyle(.secondary)
                case .createNew: Image(systemName: "plus.circle.fill").foregroundStyle(Color.designPrimaryContainer)
                }
            } else {
                switch match.status {
                case .matched: Image(systemName: "link").foregroundStyle(Color.designPrimaryFixedDim)
                case .conflicted: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                case .suspectedDateMismatch: Image(systemName: "calendar.badge.clock").foregroundStyle(.orange)
                case .suspectedAmountMismatch: Image(systemName: "yensign.circle").foregroundStyle(.yellow)
                case .unmatched: Image(systemName: "questionmark.circle").foregroundStyle(.red)
                default: EmptyView()
                }
            }
        }
        .font(.designBodySmall)
    }

    private func suspectedHint(for match: ReconciliationMatch) -> String {
        guard let txn = match.candidates.first,
              let bankDate = match.bankItem.transDate,
              let bankAmount = match.bankItem.amount else { return "" }
        switch match.status {
        case .suspectedDateMismatch:
            let dayDiff = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: bankDate), to: Calendar.current.startOfDay(for: txn.date)).day ?? 0
            return String(localized: "日期差\(abs(dayDiff))天")
        case .suspectedAmountMismatch:
            let diff = abs(bankAmount - txn.amount)
            return String(localized: "金额差¥\(diff.formatted(.number.precision(.fractionLength(2))))")
        default: return ""
        }
    }

    private func miniStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.designBodySmall.weight(.bold)).foregroundStyle(color)
            Text(LocalizedStringKey(label)).font(.designBodySmall).foregroundStyle(.secondary)
        }
    }

    // MARK: - Computed

    private var visibleMatches: [ReconciliationMatch] {
        matches.filter { userActions[$0.id] == nil }
    }

    private var matchedCount: Int { visibleMatches.count { $0.status == .matched } }
    private var conflictedCount: Int { visibleMatches.count { $0.status == .conflicted } }
    private var suspectedDateCount: Int { visibleMatches.count { $0.status == .suspectedDateMismatch } }
    private var suspectedAmountCount: Int { visibleMatches.count { $0.status == .suspectedAmountMismatch } }
    private var unmatchedCount: Int { visibleMatches.count { $0.status == .unmatched } }

    private var appAmount: Decimal {
        appContainer.creditCardStatementService.calculateAppAmount(
            for: account, year: selectedYear, month: selectedMonth, context: modelContext
        )
    }

    private var resolvedMatches: [ReconciliationMatch] {
        var resolved = matches
        for index in resolved.indices {
            if let action = userActions[resolved[index].id] {
                switch action {
                case .confirmed(let txn):
                    resolved[index].userAction = .confirmed(txn)
                case .ignored:
                    resolved[index].userAction = .ignored
                case .createNew:
                    resolved[index].userAction = .createNew
                }
            } else if resolved[index].status == .matched,
                      let txn = resolved[index].candidates.first {
                resolved[index].userAction = .confirmed(txn)
            }
        }
        return resolved
    }

    // MARK: - Actions

    private func parseAndMatch() {
        guard let data = csvData else { return }
        isMatching = true
        bankItems = appContainer.bankOCRService.recognizeTransactions(fromCSV: data)
        matches = appContainer.reconciliationService.matchItems(
            bankItems,
            for: account,
            year: selectedYear,
            month: selectedMonth,
            context: modelContext
        )
        // Auto-fill bank amount from CSV total
        let total = bankItems.compactMap { $0.amount }.reduce(Decimal.zero, +)
        if bankAmount == 0 { bankAmount = abs(total) }

        // Compute unmatched App transactions (in period but not matched to any bank item)
        let matchedIDs = Set(matches.compactMap { $0.candidates.first?.id })
        guard let period = CreditCardStatementPeriod(
            billingDay: account.billingDay == 0 ? 1 : Int(account.billingDay),
            year: selectedYear,
            month: selectedMonth
        ) else {
            unmatchedAppTxns = []
            isMatching = false
            return
        }
        let accountID = account.id
        let fetchAll = NSFetchRequest<Transaction>(entityName: "Transaction")
        fetchAll.predicate = NSPredicate(format: "account.id == %@ AND parentTransaction == nil", accountID as CVarArg)
        let allTxns = (try? modelContext.fetch(fetchAll)) ?? []
        unmatchedAppTxns = allTxns.filter {
            $0.type == .expense && period.contains($0.date) && !matchedIDs.contains($0.id)
        }.sorted { $0.date > $1.date }

        isMatching = false
    }

    private func save() {
        guard let ledger = appContainer.currentLedger else { return }

        let stmt: CreditCardStatement
        if let existing = editing {
            existing.periodYear = Int64(selectedYear)
            existing.periodMonth = Int64(selectedMonth)
            existing.statementAmount = bankAmount == 0 ? nil : bankAmount
            // Persist CSV data to local file, store only path in CoreData
            if let data = csvData {
                existing.bankCSVFileName = CSVStorage.save(data, statementId: existing.id)
            } else {
                if let oldPath = existing.bankCSVFileName { CSVStorage.delete(path: oldPath) }
                existing.bankCSVFileName = nil
            }
            try? appContainer.creditCardStatementService.updateStatement(existing, context: modelContext)
            stmt = existing
        } else {
            stmt = CreditCardStatement(
                account: account,
                periodYear: selectedYear,
                periodMonth: selectedMonth,
                statementAmount: bankAmount == 0 ? nil : bankAmount,
                bankCSVFileName: nil,
                context: modelContext
            )
            // Save CSV after we have an ID
            if let data = csvData {
                stmt.bankCSVFileName = CSVStorage.save(data, statementId: stmt.id)
            }
            try? appContainer.creditCardStatementService.createStatement(stmt, ledger: ledger, context: modelContext)
        }

        dismiss()
    }

    private func loadEditingCSV() {
        guard let existing = editing,
              let path = existing.bankCSVFileName,
              let data = CSVStorage.load(path: path),
              bankItems.isEmpty else { return }
        csvData = data
        csvFileName = path.components(separatedBy: "/").last ?? ""
        parseAndMatch()
    }

    private func confirmAction() {
        guard let ledger = appContainer.currentLedger else { return }

        _ = try? appContainer.reconciliationService.confirmReconciliation(
            matches: resolvedMatches,
            account: account,
            year: selectedYear,
            month: selectedMonth,
            bankAmount: bankAmount,
            ledger: ledger,
            context: modelContext
        )

        // Update statement to mark as reconciled
        if let stmt = editing {
            stmt.isReconciled = true
            stmt.reconciledAt = Date.now
            try? appContainer.creditCardStatementService.updateStatement(stmt, context: modelContext)
        }

        dismiss()
    }

    private var confirmSection: some View {
        Group {
            if editing != nil, !bankItems.isEmpty, !isMatching,
               resolvedMatches.allSatisfy({ if case .pending = $0.userAction { return false }; return true }) {
                Section {
                    Button {
                        confirmAction()
                    } label: {
                        HStack {
                            Spacer()
                            Label("确认对账（完成核对）", systemImage: "checkmark.seal.fill")
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
        }
    }
}
