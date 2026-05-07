import SwiftUI
import SwiftData

struct LedgerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer

    let ledger: Ledger
    @State private var name: String = ""
    @State private var type: LedgerType = .personal
    @State private var currencyCode: String = "CNY"
    @State private var showDeleteAlert = false

    private let currencies = ["CNY", "USD", "EUR", "JPY", "GBP", "HKD", "AUD", "CAD"]

    var body: some View {
        NavigationStack {
            Form {
            Section("基本信息") {
                TextField("账本名称", text: $name)
                Picker("类型", selection: $type) {
                    ForEach(LedgerType.allCases, id: \.self) { t in
                        Label(t.displayName, systemImage: t.systemIcon).tag(t)
                    }
                }
                Picker("默认货币", selection: $currencyCode) {
                    ForEach(currencies, id: \.self) { code in
                        Text("\(code) (\(currencyName(code)))").tag(code)
                    }
                }
            }

            Section("数据管理") {
                NavigationLink("账户管理") {
                    AccountsManagementView(ledger: ledger)
                }
                NavigationLink("分类管理") {
                    CategoryListView(ledger: ledger)
                }
                NavigationLink("联系人管理") {
                    MemberListView(ledger: ledger)
                }
                NavigationLink("商家管理") {
                    MerchantListView(ledger: ledger)
                }
                NavigationLink("项目管理") {
                    ProjectListView(ledger: ledger)
                }
                NavigationLink("预算管理") {
                    BudgetBookListView(ledger: ledger)
                }
                NavigationLink("模板管理") {
                    TemplateListView(ledger: ledger)
                }
                NavigationLink("待报销") {
                    PendingReimbursementView(ledger: ledger)
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Label("删除账本", systemImage: "trash")
                }
            }
        }
        .navigationTitle("账本设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(name.isEmpty)
            }
        }
        .onAppear {
            name = ledger.name
            type = ledger.type
            currencyCode = ledger.defaultCurrencyCode
        }
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { confirmDelete() }
        } message: {
            Text("删除账本会同时删除该账本下的所有数据，此操作不可撤销。")
        }
        }
    }

    private func save() {
        ledger.name = name
        ledger.type = type
        ledger.defaultCurrencyCode = currencyCode
        try? appContainer.ledgerService.updateLedger(ledger, context: modelContext)
        dismiss()
    }

    private func confirmDelete() {
        try? appContainer.ledgerService.deleteLedger(ledger, context: modelContext)
        if ledger.id == appContainer.currentLedger?.id {
            if let next = (try? appContainer.ledgerService.fetchLedgers(context: modelContext))?.first {
                appContainer.currentLedger = next
                UserDefaults.standard.set(next.id.uuidString, forKey: "currentLedgerID")
            }
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
        default: return code
        }
    }
}
