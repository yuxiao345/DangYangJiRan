import SwiftUI
import SwiftData

struct AddEditAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer

    let ledger: Ledger?
    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }

    @State private var name = ""
    @State private var accountType: AccountType = .cash
    @State private var currencyCode = "CNY"
    @State private var initialBalance: Decimal = 0
    @State private var creditLimit: Decimal = 0
    @State private var hasCreditLimit = false
    @State private var billingDay: Int = 1
    @State private var graceDays: Int = 20

    init(ledger: Ledger? = nil) {
        self.ledger = ledger
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("账户名称", text: $name)
                    Picker("类型", selection: $accountType) {
                        ForEach(AccountType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.systemIcon)
                                .tag(type)
                        }
                    }
                    Picker("币种", selection: $currencyCode) {
                        Text("CNY").tag("CNY")
                        Text("USD").tag("USD")
                    }
                }

                Section("余额") {
                    CurrencyTextField(label: "初始余额", value: $initialBalance)
                }

                if accountType == .creditCard {
                    Section("信用卡设置") {
                        Toggle("设置信用额度", isOn: $hasCreditLimit)
                        if hasCreditLimit {
                            CurrencyTextField(label: "额度", value: $creditLimit)
                        }
                        Picker("账单日", selection: $billingDay) {
                            ForEach(1...28, id: \.self) { day in
                                Text("每月\(day)日").tag(day)
                            }
                        }
                        HStack {
                            Text("账期")
                            TextField("天数", value: $graceDays, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                        HStack {
                            Text("还款日")
                            Spacer()
                            Text(computedDueDateText)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("新增账户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.isEmpty)
                }
            }
        }
    }

    private var computedDueDateText: String {
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month], from: Date())
        comps.day = min(billingDay, 28)
        comps.hour = 0; comps.minute = 0; comps.second = 0
        guard let billingDate = calendar.date(from: comps),
              let due = calendar.date(byAdding: .day, value: graceDays, to: billingDate) else {
            return "—"
        }
        let dc = calendar.dateComponents([.month, .day], from: due)
        return "\(dc.month ?? 0)月\(dc.day ?? 0)日"
    }

    private func save() {
        guard let ledger = effectiveLedger else { return }
        let account = Account(
            name: name,
            currencyCode: currencyCode,
            type: accountType,
            initialBalance: initialBalance,
            creditLimit: hasCreditLimit ? creditLimit : nil,
            billingDay: accountType == .creditCard ? billingDay : nil,
            graceDays: accountType == .creditCard ? graceDays : nil
        )
        try? appContainer.accountService.createAccount(account, ledger: ledger, context: modelContext)
        dismiss()
    }
}

struct CurrencyTextField: View {
    let label: String
    @Binding var value: Decimal
    @State private var text: String = ""

    var body: some View {
        TextField(label, text: $text)
            .keyboardType(.decimalPad)
            .onAppear {
                text = value == 0 ? "" : value.description
            }
            .onChange(of: text) { _, newValue in
                value = Decimal(string: newValue) ?? 0
            }
    }
}
