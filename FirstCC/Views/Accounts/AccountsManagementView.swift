import SwiftUI
@preconcurrency import CoreData

struct AccountsManagementView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @State private var accounts: [Account] = []
    @State private var balances: [UUID: Decimal] = [:]
    @State private var showAddSheet = false
    @State private var editingAccount: Account?

    let ledger: Ledger?
    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }

    init(ledger: Ledger? = nil) {
        self.ledger = ledger
    }

    var body: some View {
        List {
            if accounts.isEmpty {
                Text("暂无账户，点击右上角 + 添加")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(accountGroups, id: \.type) { group in
                    Section(group.type.displayName) {
                        ForEach(group.accounts) { account in
                            accountRow(account)
                        }
                    }
                }
            }

            Section("归档账户") {
                ForEach(archivedAccounts) { account in
                    HStack {
                        accountIcon(account)
                        Text(LocalizedStringKey(account.name))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("账户管理")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet, onDismiss: { loadAccounts() }) {
            AddEditAccountView(ledger: effectiveLedger)
        }
        .sheet(item: $editingAccount, onDismiss: { loadAccounts() }) { account in
            EditAccountView(account: account)
        }
        .onAppear(perform: loadAccounts)
    }

    private var accountGroups: [(type: AccountType, accounts: [Account])] {
        var groups: [(AccountType, [Account])] = []
        for type in AccountType.allCases {
            let matched = accounts.filter { $0.type == type && !$0.isArchived }
            if !matched.isEmpty {
                groups.append((type, matched))
            }
        }
        return groups
    }

    private var archivedAccounts: [Account] {
        accounts.filter { $0.isArchived }
    }

    private func accountRow(_ account: Account) -> some View {
        HStack {
            accountIcon(account)
            VStack(alignment: .leading) {
                Text(LocalizedStringKey(account.name))
                Text(account.currencyCode)
                    .font(.designBodySmall)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            let bal = balances[account.id] ?? 0
            CurrencyText(amount: bal, currencyCode: account.currencyCode, showSign: true, size: 15, foregroundColor: bal >= 0 ? .green : .red)
            Image(systemName: "chevron.right")
                .font(.designBodySmall)
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
        }
        .contentShape(Rectangle())
        .onTapGesture { editingAccount = account }
        .swipeActions(edge: .trailing) {
            Button {
                account.isArchived = !account.isArchived
                try? modelContext.save()
                loadAccounts()
            } label: {
                Label(account.isArchived ? "恢复" : "归档", systemImage: "archivebox")
            }
            .tint(account.isArchived ? .green : .orange)

            if account.isArchived {
                Button(role: .destructive) {
                    try? appContainer.accountService.deleteAccount(account, context: modelContext)
                    loadAccounts()
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    private func accountIcon(_ account: Account) -> some View {
        Image(systemName: account.iconName ?? "creditcard")
            .frame(width: 32)
            .foregroundStyle(account.colorHex.map { Color(hex: $0) } ?? .blue)
    }

    private func loadAccounts() {
        guard let ledger = effectiveLedger else { return }
        accounts = (try? appContainer.accountService.fetchAccounts(for: ledger, includeArchived: true, context: modelContext)) ?? []
        for a in accounts {
            balances[a.id] = appContainer.accountService.calculateBalance(for: a, context: modelContext)
        }
    }
}

struct EditAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer

    let account: Account

    @State private var name: String
    @State private var currencyCode: String
    @State private var initialBalance: Decimal
    @State private var selectedLogoID: String? = nil
    @State private var showLogoPicker = false
    @State private var hasCreditLimit: Bool
    @State private var creditLimit: Decimal
    @State private var billingDay: Int
    @State private var dueDay: Int

    init(account: Account) {
        self.account = account
        _name = State(initialValue: account.name)
        _currencyCode = State(initialValue: account.currencyCode)
        _initialBalance = State(initialValue: account.initialBalance)
        _hasCreditLimit = State(initialValue: account.creditLimit != nil)
        _creditLimit = State(initialValue: account.creditLimit ?? 0)
        _billingDay = State(initialValue: account.billingDay == 0 ? 1 : Int(account.billingDay))
        _dueDay = State(initialValue: account.dueDay == 0 ? 5 : Int(account.dueDay))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("账户名称", text: $name)
                    HStack {
                        Text("类型")
                        Spacer()
                        Text(account.typeDisplayName)
                            .foregroundStyle(.secondary)
                    }
                    Picker("币种", selection: $currencyCode) {
                        Text("CNY (人民币)").tag("CNY")
                        Text("USD (美元)").tag("USD")
                        Text("EUR (欧元)").tag("EUR")
                        Text("JPY (日元)").tag("JPY")
                        Text("GBP (英镑)").tag("GBP")
                        Text("HKD (港币)").tag("HKD")
                    }
                }

                Section("余额") {
                    NumpadAmountField(amount: $initialBalance, allowSignToggle: true)
                }

                Section("Logo") {
                    Button {
                        showLogoPicker = true
                    } label: {
                        HStack {
                            Text("选择Logo")
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
                                Image(systemName: account.iconName ?? "creditcard")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.secondary)
                                Text("不选择（使用类型图标）")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if account.type == .creditCard {
                    Section("信用卡设置") {
                        Toggle("设置信用额度", isOn: $hasCreditLimit)
                        if hasCreditLimit {
                            HStack {
                                Text("¥").foregroundStyle(.secondary)
                                TextField("额度", value: $creditLimit, format: .number)
                                    .keyboardType(.decimalPad)
                            }
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
            .navigationTitle("编辑账户")
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
            .sheet(isPresented: $showLogoPicker) {
                BankLogoPickerView(selectedLogoID: $selectedLogoID)
            }
        }
    }

    private func save() {
        account.name = name
        account.currencyCode = currencyCode
        account.initialBalance = initialBalance
        if account.type == .creditCard {
            account.creditLimit = hasCreditLimit ? creditLimit : nil
            account.billingDay = Int64(billingDay)
            account.dueDay = Int64(dueDay)
        }
        try? appContainer.accountService.updateAccount(account, context: modelContext)
        dismiss()
    }
}
