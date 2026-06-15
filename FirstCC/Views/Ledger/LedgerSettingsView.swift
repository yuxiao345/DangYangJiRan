import SwiftUI
@preconcurrency import CoreData
import CloudKit

struct LedgerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer

    let ledger: Ledger
    @State private var name: String = ""
    @State private var type: LedgerType = .personal
    @State private var currencyCode: String = "CNY"
    @State private var showDeleteAlert = false
    @State private var showCloseShareAlert = false
    @State private var showExitShareAlert = false
    @State private var showCloudShare = false
    @State private var cloudShare: CKShare?
    @State private var isExiting = false
    @State private var clonedLedgerID: UUID?
    @State private var isCreatingShare = false
    @State private var shareError: String?
    @State private var shareDetected: Bool? = nil  // nil=检测中, true=共享存在, false=无共享
    @State private var shareZoneIDForPurge: CKRecordZone.ID?

    private var isOwner: Bool {
        // 优先用 CKShare.currentUserParticipant 判断（基于当前 iCloud 账户，最可靠）
        if let share = cloudShare, share.currentUserParticipant?.role == .owner { return true }
        // 回退到比较 recordID
        return appContainer.isOwner(of: ledger)
    }
    private var isShared: Bool { shareDetected == true }

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
                    if shareDetected == nil {
                        HStack { ProgressView(); Text("正在检测共享状态...").font(.designBodySmall).foregroundStyle(.secondary) }
                    } else if isShared {
                        NavigationLink {
                            UserListView(ledger: ledger)
                        } label: {
                            Label("共享成员", systemImage: "person.2.fill")
                        }
                        if isOwner {
                            Button {
                                openExistingShare()
                            } label: {
                                Label("管理共享", systemImage: "square.and.arrow.up")
                            }
                            Button(role: .destructive) {
                                showCloseShareAlert = true
                            } label: {
                                HStack {
                                    Label("关闭共享", systemImage: "person.2.slash")
                                    if isExiting { Spacer(); ProgressView() }
                                }
                            }
                            .disabled(isExiting)
                        } else {
                            Button(role: .destructive) {
                                showExitShareAlert = true
                            } label: {
                                HStack {
                                    Label("退出共享", systemImage: "rectangle.portrait.and.arrow.right")
                                    if isExiting { Spacer(); ProgressView() }
                                }
                            }
                            .disabled(isExiting)
                        }
                    } else {
                        Button {
                            createShareAndShow()
                        } label: {
                            HStack {
                                Label("启用共享", systemImage: "person.2.badge.plus")
                                if isCreatingShare { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(isCreatingShare)
                    }
                } header: {
                    Text("共享管理")
                } footer: {
                    if shareDetected == nil {
                        Text("正在检查 iCloud 共享状态...")
                    } else if isShared {
#if DEBUG
                        let diag = "currentUser: \(appContainer.currentUserRecordID ?? "nil")\nownerRID: \(ledger.ownerUserRecordID ?? "nil")"
                        Text((isOwner ? "此账本已开启共享，其他用户可加入协作记账" : "你正在参与此共享账本，仅拥有者可管理成员") + "\n\n[诊断] \(diag)")
#else
                        Text(isOwner ? "此账本已开启共享，其他用户可加入协作记账" : "你正在参与此共享账本，仅拥有者可管理成员")
#endif
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
                NavigationLink("数据导出") {
                    ExportView()
                }
            }

            if !isShared || isOwner {
                Section {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("删除账本", systemImage: "trash")
                    }
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
        .task { await detectShare() }
        .sheet(isPresented: $showCloudShare) {
            if let container = appContainer.cloudKitContainer, let share = cloudShare {
                CloudSharingView(
                    share: share, container: container, ledger: ledger,
                    syncService: appContainer.syncService as? SyncServiceImpl,
                    onStopSharing: {
                        Task { await handleStopSharing() }
                    }
                )
            } else {
                ContentUnavailableView("共享未就绪", systemImage: "icloud.slash", description: Text("暂时无法读取共享信息，请稍后重试。"))
            }
        }
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { confirmDelete() }
        } message: {
            if isShared && isOwner {
                Text("这是共享账本。删除后其他成员将无法访问，数据将保留在你的本地。")
            } else {
                Text("删除账本会同时删除该账本下的所有数据，此操作不可撤销。")
            }
        }
        .alert("关闭共享", isPresented: $showCloseShareAlert) {
            Button("取消", role: .cancel) {}
            Button("关闭共享", role: .destructive) { closeShare() }
        } message: {
            Text("关闭共享后，其他成员将无法访问此账本。你的数据将保留为本地账本。")
        }
        .alert("退出共享", isPresented: $showExitShareAlert) {
            Button("取消", role: .cancel) {}
            Button("退出共享", role: .destructive) { exitShare() }
        } message: {
            Text("退出后你将无法访问此共享账本。数据将保留一份本地副本。")
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
                    ledger.shareRecordName = share.recordID.recordName
                    do {
                        try modelContext.save()
                    } catch {
                        DiagnosticLog.log("LedgerSettings: save after share failed: \(error.localizedDescription)")
                    }
                    cloudShare = share
                    isCreatingShare = false
                    showCloudShare = true
                }
                do {
                    try await syncService.syncParticipants(share: share, for: ledger)
                } catch {
                    DiagnosticLog.log("LedgerSettings: syncParticipants failed: \(error.localizedDescription)")
                }
            } catch {
                await MainActor.run {
                    isCreatingShare = false
                    shareError = error.localizedDescription
                }
            }
        }
    }

    private func detectShare() async {
        // 方式1：通过 shareRecordName
        if let recordName = ledger.shareRecordName {
            let recordID = CKRecord.ID(recordName: recordName)
            do {
                let records = try await CKContainer.default().sharedCloudDatabase.records(for: [recordID])
                if let share = records[recordID] as? CKShare {
                    repairLedgerFromShare(share)
                    cloudShare = share
                    shareDetected = true
                    return
                }
            } catch {
                // recordName 方式失败，继续 fallback
            }
        }

        // 方式2：通过 Core Data fetchShares
        do {
            let shares = try appContainer.coreDataStack.container.fetchShares(matching: [ledger.objectID])
            if let share = shares[ledger.objectID] {
                repairLedgerFromShare(share)
                cloudShare = share
                shareDetected = true
                return
            }
        } catch {}

        // 方式3：直接查询 shared database 中的 CKShare 记录
        do {
            let results = try await CKContainer.default().sharedCloudDatabase.records(
                matching: CKQuery(recordType: "cloudkit.share", predicate: NSPredicate(value: true))
            )
            for (_, result) in results.matchResults {
                if let share = try? result.get() as? CKShare {
                    // 保存 shareRecordName 以便后续使用
                    ledger.shareRecordName = share.recordID.recordName
                    repairLedgerFromShare(share)
                    cloudShare = share
                    shareDetected = true
                    return
                }
            }
        } catch {}

        shareDetected = false
    }

    private func repairLedgerFromShare(_ share: CKShare) {
        var changed = false
        if !ledger.isShared {
            ledger.isShared = true
            changed = true
        }
        if ledger.shareRecordName == nil {
            ledger.shareRecordName = share.recordID.recordName
            changed = true
        }
        // currentUserParticipant 基于当前 iCloud 登录状态，是判断 owner 的最可靠方式
        // 只有 owner 设备才写入自己的 recordID，participant 不碰（等 CloudKit 同步）
        if share.currentUserParticipant?.role == .owner {
            let myID = appContainer.currentUserRecordID
            if ledger.ownerUserRecordID != myID {
                ledger.ownerUserRecordID = myID
                changed = true
            }
        }
        if changed {
            try? modelContext.save()
        }
    }

    private func openExistingShare() {
        // Always re-detect to get the latest CKShare state
        Task {
            await detectShare()
            await MainActor.run {
                if cloudShare != nil {
                    showCloudShare = true
                } else {
                    shareError = "无法读取共享信息，请稍后重试"
                }
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
        do {
            try appContainer.ledgerService.deleteLedger(ledger, context: modelContext)
            DiagnosticLog.log("LedgerSettingsView: deleted \(ledger.name) OK")
        } catch {
            DiagnosticLog.log("LedgerSettingsView: delete FAILED \(error.localizedDescription)")
        }
        if ledger.id == appContainer.currentLedger?.id {
            if let next = (try? appContainer.ledgerService.fetchLedgers(context: modelContext))?.first {
                appContainer.currentLedger = next
                UserDefaults.standard.set(next.id.uuidString, forKey: "currentLedgerID")
            }
        }
        dismiss()
    }

    // MARK: - Exit & Close Share

    private func exitShare() {
        isExiting = true
        Task {
            do {
                let clone = try LedgerDeepCopyService.deepCopy(ledger, into: modelContext)
                // Re-detect to get latest CKShare state before showing system UI
                await detectShare()
                await MainActor.run {
                    clonedLedgerID = clone.id
                    shareZoneIDForPurge = cloudShare?.recordID.zoneID
                    isExiting = false
                    showCloudShare = true
                }
            } catch {
                await MainActor.run {
                    isExiting = false
                    shareError = "数据复制失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func closeShare() {
        isExiting = true
        Task {
            await MainActor.run {
                isExiting = false
                showCloudShare = true
            }
        }
    }

    @MainActor
    private func handleStopSharing() async {
        if isOwner {
            ledger.isShared = false
            try? modelContext.save()
            appContainer.syncStatus = .synced
            dismiss()
        } else if let cloneID = clonedLedgerID {
            // Record the original shared ledger as exited so it won't appear in the list
            appContainer.exitedSharedLedgerIDs.insert(ledger.id)
            let fetch = NSFetchRequest<Ledger>(entityName: "Ledger")
            fetch.predicate = NSPredicate(format: "id == %@", cloneID as CVarArg)
            fetch.fetchLimit = 1
            if let clone = try? modelContext.fetch(fetch).first {
                appContainer.currentLedger = clone
                UserDefaults.standard.set(clone.id.uuidString, forKey: "currentLedgerID")
                dismiss()
                // Purge the shared zone now that participant removal is complete.
                // This is Apple's recommended approach — safe because CloudKit has
                // already processed the participant removal server-side.
                if let zoneID = shareZoneIDForPurge {
                    appContainer.coreDataStack.purgeSharedZone(zoneID: zoneID)
                }
                appContainer.syncStatus = .synced
            }
        } else {
            dismiss()
        }
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
