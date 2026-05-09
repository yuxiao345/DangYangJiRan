import SwiftUI
import SwiftData
import PhotosUI

struct AccountsManagementView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.modelContext) private var modelContext
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
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            let bal = balances[account.id] ?? 0
            CurrencyText(amount: bal, currencyCode: account.currencyCode, showSign: true, font: .subheadline, foregroundColor: bal >= 0 ? .green : .red)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
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
        Group {
            if let data = account.customIconData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: account.iconName ?? "creditcard")
                    .frame(width: 32)
                    .foregroundStyle(account.colorHex.map { Color(hex: $0) } ?? .blue)
            }
        }
    }

    private func loadAccounts() {
        guard let ledger = effectiveLedger else { return }
        accounts = (try? appContainer.accountService.fetchAccounts(for: ledger, context: modelContext)) ?? []
        for a in accounts {
            balances[a.id] = appContainer.accountService.calculateBalance(for: a, context: modelContext)
        }
    }
}

struct EditAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer

    let account: Account

    @State private var name: String
    @State private var currencyCode: String
    @State private var initialBalance: Decimal
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var customIconData: Data?
    @State private var hasCreditLimit: Bool
    @State private var creditLimit: Decimal
    @State private var billingDay: Int
    @State private var dueDay: Int

    init(account: Account) {
        self.account = account
        _name = State(initialValue: account.name)
        _currencyCode = State(initialValue: account.currencyCode)
        _initialBalance = State(initialValue: account.initialBalance)
        _customIconData = State(initialValue: account.customIconData)
        _hasCreditLimit = State(initialValue: account.creditLimit != nil)
        _creditLimit = State(initialValue: account.creditLimit ?? 0)
        _billingDay = State(initialValue: account.billingDay ?? 1)
        _dueDay = State(initialValue: account.dueDay ?? 5)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("账户名称", text: $name)
                    HStack {
                        Text("类型")
                        Spacer()
                        Text(account.type.displayName)
                            .foregroundStyle(.secondary)
                    }
                    Picker("币种", selection: $currencyCode) {
                        Text("CNY").tag("CNY")
                        Text("USD").tag("USD")
                    }
                }

                Section("余额") {
                    CurrencyTextField(label: "初始余额", value: $initialBalance)
                }

                Section("图标") {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            if let data = customIconData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            } else {
                                Image(systemName: account.iconName ?? "creditcard")
                                    .font(.system(size: 50))
                                    .frame(width: 80, height: 80)
                                    .foregroundStyle(.blue)
                            }
                        }
                        Spacer()
                    }
                    Text("点击更换图标")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            .onChange(of: selectedPhoto) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self) {
                        customIconData = data
                    }
                }
            }
        }
    }

    private func save() {
        account.name = name
        account.currencyCode = currencyCode
        account.initialBalance = initialBalance
        account.customIconData = customIconData
        if account.type == .creditCard {
            account.creditLimit = hasCreditLimit ? creditLimit : nil
            account.billingDay = billingDay
            account.dueDay = dueDay
        }
        try? appContainer.accountService.updateAccount(account, context: modelContext)
        dismiss()
    }
}
