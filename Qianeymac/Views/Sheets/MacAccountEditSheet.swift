import SwiftUI
@preconcurrency import CoreData

/// Mac-native account editor: standard form layout with LabeledContent + right-aligned colons.
/// Shares AccountService / Ledger / Account models with iOS but uses Mac-native UI.
struct MacAccountEditSheet: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let editing: Account?          // nil = creating new
    let ledger: Ledger

    // MARK: - State
    @State private var name: String
    @State private var accountType: AccountType
    @State private var currencyCode: String
    @State private var initialBalance: Decimal
    @State private var balanceString: String
    @State private var hasCreditLimit: Bool
    @State private var creditLimit: Decimal
    @State private var creditLimitString: String
    @State private var billingDay: Int
    @State private var dueDay: Int
    @State private var colorHex: String
    @State private var iconName: String
    @State private var isArchived: Bool
    @State private var customTypeName: String
    @State private var existingCustomTypes: [String] = []
    @State private var errorMessage: String?
    @State private var showErrorAlert: Bool = false

    private var effectiveLedger: Ledger { ledger }

    private let currencies = ["CNY", "USD", "EUR", "JPY", "GBP", "HKD", "AUD", "CAD", "KRW", "TWD", "SGD", "CHF", "NZD", "THB", "MYR", "INR"]
    private let billingDays = Array(1...28)
    private let dueDays = Array(1...31)
    private let accountIcons = [
        "creditcard", "banknote", "wallet.pass", "building.columns", "chart.line.uptrend.xyaxis",
        "house", "shield.checkered", "arrow.triangle.swap", "square.grid.2x2"
    ]
    private let accountColors: [(String, Color)] = [
        ("#007AFF", .blue), ("#34C759", .green), ("#FF9500", .orange), ("#FF3B30", .red),
        ("#AF52DE", .purple), ("#5856D6", .indigo), ("#00C7BE", .teal), ("#FF2D55", .pink)
    ]

    private var isEditing: Bool { editing != nil }

    init(editing: Account? = nil, ledger: Ledger) {
        self.editing = editing
        self.ledger = ledger
        let account = editing
        _name = State(initialValue: account?.name ?? "")
        _accountType = State(initialValue: account?.type ?? .cash)
        _currencyCode = State(initialValue: account?.currencyCode ?? "CNY")
        _initialBalance = State(initialValue: account?.initialBalance ?? 0)
        _balanceString = State(initialValue: account != nil ? String(describing: account!.initialBalance) : "")
        _hasCreditLimit = State(initialValue: (account?.creditLimit) != nil)
        _creditLimit = State(initialValue: account?.creditLimit ?? 0)
        _creditLimitString = State(initialValue: account?.creditLimit != nil ? String(describing: account!.creditLimit!) : "")
        _billingDay = State(initialValue: Int(account?.billingDay ?? 1))
        _dueDay = State(initialValue: Int(account?.dueDay ?? 5))
        _colorHex = State(initialValue: account?.colorHex ?? "#007AFF")
        _iconName = State(initialValue: account?.iconName ?? "creditcard")
        _isArchived = State(initialValue: account?.isArchived ?? false)
        _customTypeName = State(initialValue: account?.customTypeName ?? "")
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Icon + Color picker
                iconColorSection

                allFieldsGrid
                Divider()
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .designScreen()
        .frame(minWidth: 400, idealWidth: 460, minHeight: 380)
        .navigationTitle(isEditing ? "编辑账户" : "新增账户")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.keyboardShortcut(.defaultAction) }
        }
        .onAppear { loadExistingCustomTypes() }
        .onChange(of: accountType) { _, _ in loadExistingCustomTypes() }
        .alert("保存失败", isPresented: $showErrorAlert) {
        } message: { Text(errorMessage ?? "") }
    }

    // MARK: - Icon & Color

    private var iconColorSection: some View {
        VStack(spacing: 10) {
            // Icon grid
            VStack(spacing: 4) {
                Text("图标").font(.designBodyCaption).foregroundStyle(Color.designOnSurfaceVariant)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 4) {
                    ForEach(accountIcons, id: \.self) { icon in
                        Button { iconName = icon } label: {
                            Image(systemName: icon)
                                .font(.system(size: 22))
                                .frame(width: 40, height: 40)
                                .background(iconName == icon ? Color.accentColor.opacity(0.15) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                                    iconName == icon ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            // Color grid
            VStack(spacing: 4) {
                Text("颜色").font(.designBodyCaption).foregroundStyle(Color.designOnSurfaceVariant)
                HStack(spacing: 6) {
                    ForEach(accountColors, id: \.0) { hex, color in
                        Button { colorHex = hex } label: {
                            Circle().fill(color)
                                .frame(width: 24, height: 24)
                                .overlay(Circle().stroke(colorHex == hex ? Color.white : Color.clear, lineWidth: 2))
                                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - All Fields Grid

    private var allFieldsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("名称：")
                    .gridColumnAlignment(.trailing)
                TextField("", text: $name).textFieldStyle(.roundedBorder)
            }
            GridRow {
                Text("类型：")
                Picker("", selection: $accountType) {
                    ForEach(AccountType.allCases, id: \.self) { t in Text(t.displayName).tag(t) }
                }
                .pickerStyle(.menu).labelsHidden()
            }
            if accountType == .other {
                GridRow {
                    Text("")
                    HStack(spacing: 6) {
                        TextField(String(localized: "创建或选择自定义类型名称"), text: $customTypeName)
                        if !existingCustomTypes.isEmpty {
                            Picker("已有类型", selection: $customTypeName) {
                                ForEach(existingCustomTypes, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu).labelsHidden()
                        }
                    }
                }
            }
            GridRow {
                Text("币种：")
                Picker("", selection: $currencyCode) {
                    ForEach(currencies, id: \.self) { code in
                        Text("\(code) \(CurrencyFormatter.currencySymbol(for: code))").tag(code)
                    }
                }
                .pickerStyle(.menu).labelsHidden()
                .disabled(isEditing)
            }
            GridRow {
                Text("余额：")
                TextField("0.00", text: $balanceString)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: balanceString) { _, v in
                        balanceString = v.filter { "0123456789.".contains($0) }
                        initialBalance = Decimal(string: balanceString) ?? 0
                    }
            }
            if isEditing {
                GridRow {
                    Text("归档：")
                    Toggle("", isOn: $isArchived).labelsHidden()
                }
            }
            // Credit card fields — same Grid, same column alignment
            if accountType == .creditCard {
                GridRow {
                    Text("信用额度：")
                    TextField("0.00", text: $creditLimitString)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: creditLimitString) { _, v in
                            creditLimitString = v.filter { "0123456789.".contains($0) }
                            creditLimit = Decimal(string: creditLimitString) ?? 0
                        }
                }
                GridRow {
                    Text("账单日：")
                    Picker("", selection: $billingDay) {
                        ForEach(billingDays, id: \.self) { d in Text("\(d)日").tag(d) }
                    }
                    .pickerStyle(.menu).labelsHidden()
                }
                GridRow {
                    Text("还款日：")
                    Picker("", selection: $dueDay) {
                        ForEach(dueDays, id: \.self) { d in Text("\(d)日").tag(d) }
                    }
                    .pickerStyle(.menu).labelsHidden()
                }
            }
        }
        .buttonSizing(.flexible)
        .frame(width: 350)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Save

    private func loadExistingCustomTypes() {
        guard accountType == .other else { existingCustomTypes = []; return }
        let all = (try? appContainer.accountService.fetchAccounts(for: ledger, includeArchived: true, context: modelContext)) ?? []
        let names = all.compactMap { $0.customTypeName }.filter { !$0.isEmpty }
        if let editing, let current = editing.customTypeName, !current.isEmpty {
            existingCustomTypes = [current] + Array(Set(names)).filter { $0 != current }.sorted()
        } else {
            existingCustomTypes = Array(Set(names)).sorted()
        }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "请输入账户名称"; showErrorAlert = true; return
        }
        do {
            if let account = editing {
                account.name = name
                account.typeRaw = accountType.rawValue
                account.currencyCode = currencyCode
                account.initialBalance = initialBalance
                account.creditLimit = hasCreditLimit ? creditLimit : nil
                account.billingDay = Int64(billingDay)
                account.dueDay = Int64(dueDay)
                account.colorHex = colorHex
                account.iconName = iconName
                account.isArchived = isArchived
                account.customTypeName = accountType == .other ? (customTypeName.isEmpty ? nil : customTypeName) : nil
                try appContainer.accountService.updateAccount(account, context: modelContext)
            } else {
                let account = Account(name: name, currencyCode: currencyCode,
                    type: accountType, iconName: iconName, colorHex: colorHex,
                    initialBalance: initialBalance,
                    creditLimit: hasCreditLimit ? creditLimit : nil,
                    billingDay: billingDay, dueDay: dueDay,
                    context: modelContext)
                if accountType == .other, !customTypeName.isEmpty { account.customTypeName = customTypeName }
                try appContainer.accountService.createAccount(account, ledger: ledger, context: modelContext)
            }
            NotificationCenter.default.post(name: .transactionDidChange, object: nil)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription; showErrorAlert = true
        }
    }
}
