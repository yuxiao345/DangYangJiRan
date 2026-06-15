import SwiftUI
@preconcurrency import CoreData

struct AddEditAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer

    let ledger: Ledger?
    let editing: Account?
    private var effectiveLedger: Ledger? { ledger ?? editing?.ledger ?? appContainer.currentLedger }
    private var isEditing: Bool { editing != nil }

    @State private var name = ""
    @State private var accountType: AccountType = .cash
    @State private var currencyCode = "CNY"
    @State private var selectedLogoID: String? = nil
    @State private var showLogoPicker = false
    @State private var initialBalance: Decimal = 0

    private let currencies: [String] = ["CNY", "USD", "EUR", "JPY", "GBP", "HKD", "AUD", "CAD", "KRW", "TWD", "SGD", "CHF", "NZD", "THB", "MYR", "INR"]
    @State private var creditLimit: Decimal = 0
    @State private var hasCreditLimit = false
    @State private var billingDay: Int = 1
    @State private var dueDay: Int = 5
    @State private var customTypeName: String = ""
    @State private var existingCustomTypes: [String] = []
    @State private var errorMessage: String?

    init(ledger: Ledger? = nil) {
        self.ledger = ledger
        self.editing = nil
    }

    init(editing account: Account) {
        self.ledger = nil
        self.editing = account
        _name = State(initialValue: account.name)
        _accountType = State(initialValue: account.type)
        _currencyCode = State(initialValue: account.currencyCode)
        _initialBalance = State(initialValue: account.initialBalance)
        _hasCreditLimit = State(initialValue: account.creditLimit != nil)
        _creditLimit = State(initialValue: account.creditLimit ?? 0)
        _billingDay = State(initialValue: account.billingDay == 0 ? 1 : Int(account.billingDay))
        _dueDay = State(initialValue: account.dueDay == 0 ? 5 : Int(account.dueDay))
        _customTypeName = State(initialValue: account.customTypeName ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("账户名称", text: $name)

                    if isEditing {
                        HStack {
                            Text("类型")
                            Spacer()
                            Text(accountType.displayName)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Picker("类型", selection: $accountType) {
                            ForEach(AccountType.allCases, id: \.self) { type in
                                Label(type.displayName, systemImage: type.systemIcon)
                                    .tag(type)
                            }
                        }
                    }

                    if accountType == .other {
                        HStack {
                            TextField("创建或选择自定义类型名称", text: $customTypeName)
                            if !existingCustomTypes.isEmpty {
                                Picker("已有类型", selection: $customTypeName) {
                                    ForEach(existingCustomTypes, id: \.self) { Text($0).tag($0) }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                        }
                    }

                    Picker("币种", selection: $currencyCode) {
                        ForEach(currencies, id: \.self) { code in
                            Text("\(code) (\(currencyName(code)))").tag(code)
                        }
                    }

                    Button {
                        showLogoPicker = true
                    } label: {
                        HStack {
                            Text("Logo")
                                .foregroundStyle(.primary)
                            Spacer()
                            if let logoID = selectedLogoID, let logo = BankLogoPresets.all.first(where: { $0.id == logoID }) {
                                HStack(spacing: 8) {
                                    Image(uiImage: logo.logoImage)
                                        .resizable()
                                        .frame(width: 28, height: 28)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    Text(logo.name)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("不选择（使用类型图标）")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("余额") {
                    NumpadAmountField(amount: $initialBalance)
                }

                if accountType == .creditCard {
                    Section("信用卡设置") {
                        Toggle("设置信用额度", isOn: $hasCreditLimit)
                        if hasCreditLimit {
                            NumpadAmountField(amount: $creditLimit)
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
            .sheet(isPresented: $showLogoPicker) {
                BankLogoPickerView(selectedLogoID: $selectedLogoID)
            }
            .navigationTitle(isEditing ? "编辑账户" : "新增账户")
            .navigationBarTitleDisplayMode(.inline)
            .errorAlert("保存失败", message: $errorMessage)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.isEmpty)
                }
            }
            .onAppear { loadExistingCustomTypes() }
            .onChange(of: accountType) { _, _ in loadExistingCustomTypes() }
        }
    }

    private func loadExistingCustomTypes() {
        guard let ledger = effectiveLedger, accountType == .other else { existingCustomTypes = []; return }
        let all = (try? appContainer.accountService.fetchAccounts(for: ledger, context: modelContext)) ?? []
        let names = all.compactMap { $0.customTypeName }.filter { !$0.isEmpty }
        if let editing, let current = editing.customTypeName, !current.isEmpty { existingCustomTypes = [current] + Array(Set(names)).filter { $0 != current }.sorted() }
        else { existingCustomTypes = Array(Set(names)).sorted() }
    }

    private func save() {
        guard let ledger = effectiveLedger else { return }
        if let dup = try? appContainer.accountService.findByName(name, ledger: ledger, context: modelContext),
           dup.id != editing?.id {
            errorMessage = "同名账户「\(name)」已存在"
            return
        }
        if let existing = editing {
            existing.name = name
            existing.currencyCode = currencyCode
            existing.initialBalance = initialBalance
            existing.creditLimit = hasCreditLimit ? creditLimit : nil
            existing.billingDay = accountType == .creditCard ? Int64(billingDay) : 0
            existing.dueDay = accountType == .creditCard ? Int64(dueDay) : 0
            existing.customTypeName = accountType == .other ? (customTypeName.isEmpty ? nil : customTypeName) : nil
            try? appContainer.accountService.updateAccount(existing, context: modelContext)
        } else {
            let account = Account(
                name: name,
                currencyCode: currencyCode,
                type: accountType,
                initialBalance: initialBalance,
                creditLimit: hasCreditLimit ? creditLimit : nil,
                billingDay: accountType == .creditCard ? billingDay : nil,
                dueDay: accountType == .creditCard ? dueDay : nil,
                context: modelContext
            )
            if accountType == .other, !customTypeName.isEmpty { account.customTypeName = customTypeName }
            try? appContainer.accountService.createAccount(account, ledger: ledger, context: modelContext)
        }
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
