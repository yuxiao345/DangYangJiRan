import SwiftUI
import SwiftData

struct CreditCardReconciliationView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.modelContext) private var modelContext

    let account: Account
    @State private var statements: [CreditCardStatement] = []
    @State private var showAddSheet = false
    @State private var editingStatement: CreditCardStatement?
    @State private var viewingMonth: (year: Int, month: Int)?

    private let months = Calendar.current.monthSymbols

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
        .sheet(item: $editingStatement, onDismiss: { loadStatements() }) { stmt in
            AddEditStatementView(account: account, editing: stmt)
        }
        .task { loadStatements() }
    }

    private var yearGroups: [(year: Int, statements: [CreditCardStatement])] {
        let grouped = Dictionary(grouping: statements) { $0.periodYear }
        return grouped.map { ($0.key, $0.value.sorted { $0.periodMonth > $1.periodMonth }) }
            .sorted { $0.year > $1.year }
    }

    private func statementRow(_ stmt: CreditCardStatement) -> some View {
        let appAmount = appContainer.creditCardStatementService.calculateAppAmount(
            for: account, year: stmt.periodYear, month: stmt.periodMonth, context: modelContext
        )
        let bankAmount = stmt.statementAmount ?? 0
        let diff = bankAmount + appAmount

        return VStack(spacing: 6) {
            HStack {
                Text("\(months[stmt.periodMonth - 1])月")
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
        .contentShape(Rectangle())
        .onTapGesture { editingStatement = stmt }
        .swipeActions(edge: .trailing) {
            Button {
                stmt.isReconciled = !stmt.isReconciled
                stmt.reconciledAt = stmt.isReconciled ? Date() : nil
                try? appContainer.creditCardStatementService.updateStatement(stmt, context: modelContext)
                loadStatements()
            } label: {
                Label(stmt.isReconciled ? "取消核对" : "核对", systemImage: stmt.isReconciled ? "xmark.circle" : "checkmark.circle")
            }
            .tint(stmt.isReconciled ? .orange : .green)

            Button(role: .destructive) {
                try? appContainer.creditCardStatementService.deleteStatement(stmt, context: modelContext)
                loadStatements()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func loadStatements() {
        statements = (try? appContainer.creditCardStatementService.fetchStatements(for: account, context: modelContext)) ?? []
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

                Section("银行账单") {
                    HStack {
                        Text("¥").foregroundStyle(.secondary)
                        TextField("账单金额", value: $bankAmount, format: .number)
                            .keyboardType(.decimalPad)
                    }
                }

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

    private var appAmount: Decimal {
        appContainer.creditCardStatementService.calculateAppAmount(
            for: account, year: selectedYear, month: selectedMonth, context: modelContext
        )
    }

    private func save() {
        guard let ledger = appContainer.currentLedger else { return }
        if let stmt = editing {
            stmt.periodYear = selectedYear
            stmt.periodMonth = selectedMonth
            stmt.statementAmount = bankAmount == 0 ? nil : bankAmount
            try? appContainer.creditCardStatementService.updateStatement(stmt, context: modelContext)
        } else {
            let stmt = CreditCardStatement(
                account: account,
                periodYear: selectedYear,
                periodMonth: selectedMonth,
                statementAmount: bankAmount == 0 ? nil : bankAmount
            )
            try? appContainer.creditCardStatementService.createStatement(stmt, ledger: ledger, context: modelContext)
        }
        dismiss()
    }
}
