import SwiftUI
import SwiftData

struct AddEditAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer

    @State private var name = ""
    @State private var accountType: AccountType = .cash
    @State private var currencyCode = "CNY"
    @State private var initialBalance: Decimal = 0
    @State private var creditLimit: Decimal = 0
    @State private var hasCreditLimit = false
    @State private var billDate: Date = Date()
    @State private var dueDate: Date = Date()

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
                    Section("信用额度") {
                        Toggle("设置额度", isOn: $hasCreditLimit)
                        if hasCreditLimit {
                            CurrencyTextField(label: "额度", value: $creditLimit)
                            DatePicker("账单日", selection: $billDate, displayedComponents: .date)
                            DatePicker("还款日", selection: $dueDate, displayedComponents: .date)
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

    private func save() {
        guard let ledger = appContainer.currentLedger else { return }
        let account = Account(
            name: name,
            currencyCode: currencyCode,
            type: accountType,
            initialBalance: initialBalance,
            creditLimit: hasCreditLimit ? creditLimit : nil,
            billDate: hasCreditLimit ? billDate : nil,
            dueDate: hasCreditLimit ? dueDate : nil
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
