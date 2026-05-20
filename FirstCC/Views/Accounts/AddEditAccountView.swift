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

    private let currencies: [String] = ["CNY", "USD", "EUR", "JPY", "GBP", "HKD", "AUD", "CAD", "KRW", "TWD", "SGD", "CHF", "NZD", "THB", "MYR", "INR"]
    @State private var creditLimit: Decimal = 0
    @State private var hasCreditLimit = false
    @State private var billingDay: Int = 1
    @State private var dueDay: Int = 5

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
                        ForEach(currencies, id: \.self) { code in
                            Text("\(code) (\(currencyName(code)))").tag(code)
                        }
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
                        Picker("还款日", selection: $dueDay) {
                            ForEach(1...31, id: \.self) { day in
                                Text("每月\(day)日").tag(day)
                            }
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
        guard let ledger = effectiveLedger else { return }
        let account = Account(
            name: name,
            currencyCode: currencyCode,
            type: accountType,
            initialBalance: initialBalance,
            creditLimit: hasCreditLimit ? creditLimit : nil,
            billingDay: accountType == .creditCard ? billingDay : nil,
            dueDay: accountType == .creditCard ? dueDay : nil
        )
        try? appContainer.accountService.createAccount(account, ledger: ledger, context: modelContext)
        dismiss()
    }

    private func currencyName(_ code: String) -> String {
        switch code {
        case "CNY": return "人民币"
        case "USD": return "美元"
        case "EUR": return "欧元"
        case "JPY": return "日元"
        case "GBP": return "英镑"
        case "HKD": return "港币"
        case "AUD": return "澳元"
        case "CAD": return "加元"
        case "KRW": return "韩元"
        case "TWD": return "新台币"
        case "SGD": return "新加坡元"
        case "CHF": return "瑞士法郎"
        case "NZD": return "新西兰元"
        case "THB": return "泰铢"
        case "MYR": return "马币"
        case "INR": return "印度卢比"
        default: return code
        }
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
