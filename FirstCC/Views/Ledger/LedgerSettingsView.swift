import SwiftUI
import SwiftData
import CloudKit

struct LedgerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer

    let ledger: Ledger
    @State private var name: String = ""
    @State private var type: LedgerType = .personal
    @State private var currencyCode: String = "CNY"
    @State private var showDeleteAlert = false
    @State private var showCloudShare = false
    @State private var cloudShare: CKShare?
    @State private var isCreatingShare = false
    @State private var shareError: String?

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

            Section {
                    NavigationLink {
                        UserListView(ledger: ledger)
                    } label: {
                        Label("共享成员", systemImage: "person.2.fill")
                    }

                    if ledger.isShared {
                        Button {
                            openExistingShare()
                        } label: {
                            Label("管理共享", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            createShareAndShow()
                        } label: {
                            HStack {
                                Label("启用共享", systemImage: "person.2.badge.plus")
                                if isCreatingShare {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isCreatingShare)
                    }
                } header: {
                    Text("共享管理")
                } footer: {
                    if ledger.isShared {
                        Text("此账本已开启共享，其他用户可加入协作记账")
                    } else {
                        Text("开启后可邀请其他 iCloud 用户共同记账")
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
                NavigationLink("周期账管理") {
                    RecurringListView(ledger: ledger)
                }
                NavigationLink("待报销") {
                    PendingReimbursementView(ledger: ledger)
                }
                NavigationLink("数据导出") {
                    ExportView()
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
        .sheet(isPresented: $showCloudShare) {
            if let container = appContainer.cloudKitContainer, let share = cloudShare {
                CloudSharingView(share: share, container: container, ledger: ledger, isPresenting: true, syncService: appContainer.syncService as? SyncServiceImpl, modelContainer: appContainer.modelContainer)
            } else {
                ContentUnavailableView("共享未就绪", systemImage: "icloud.slash", description: Text("暂时无法读取共享信息，请稍后重试。"))
            }
        }
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { confirmDelete() }
        } message: {
            Text("删除账本会同时删除该账本下的所有数据，此操作不可撤销。")
        }
        .alert("共享失败", isPresented: .init(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
            Button("确定", role: .cancel) { shareError = nil }
        } message: {
            Text(shareError ?? "未知错误")
        }
        }
    }

    private func createShareAndShow() {
        isCreatingShare = true
        Task {
            do {
                guard let syncService = appContainer.syncService as? SyncServiceImpl else {
                    throw SyncError.invalidShareTarget
                }
                let share = try await syncService.createShare(for: ledger)
                await MainActor.run {
                    ledger.isShared = true
                    try? modelContext.save()
                    cloudShare = share
                    isCreatingShare = false
                    showCloudShare = true
                }
            } catch {
                await MainActor.run {
                    isCreatingShare = false
                    shareError = error.localizedDescription
                }
            }
        }
    }

    private func openExistingShare() {
        guard cloudShare != nil else {
            shareError = "共享状态已标记，但当前设备还没有可用的共享对象。请重新发起共享或稍后重试。"
            return
        }
        showCloudShare = true
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
