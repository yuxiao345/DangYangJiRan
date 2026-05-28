import SwiftUI
@preconcurrency import CoreData
import CloudKit

struct UserListView: View {
    @Environment(\.managedObjectContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer

    let ledger: Ledger?
    @State private var users: [User] = []
    @State private var isSyncing = false
    @State private var diagMessage: String = ""

    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }

    var body: some View {
        List {
            Section {
                if users.isEmpty {
                    ContentUnavailableView(
                        "暂无共享成员",
                        systemImage: "person.2.slash",
                        description: Text("点击刷新按钮从 iCloud 同步成员列表")
                    )
                }
                ForEach(users) { user in
                HStack {
                    Image(systemName: user.role == .owner ? "crown.fill" : "person.fill")
                        .foregroundStyle(user.role == .owner ? .yellow : Color.designPrimaryContainer)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName)
                        Text(user.role.displayName)
                            .font(.designBodySmall)
                            .foregroundStyle(Color.designOnSurfaceVariant)
                    }
                    Spacer()
                }
            }
            }
            if !diagMessage.isEmpty {
                Section("诊断") {
                    Text(diagMessage)
                        .font(.designBodySmall)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("共享成员")
        .refreshable { await refreshMembers() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await refreshMembers() }
                } label: {
                    if isSyncing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isSyncing)
            }
        }
        .task { await refreshMembers() }
    }

    private func refreshMembers() async {
        guard let ledger = effectiveLedger else {
            loadUsers()
            diagMessage = "ledger=nil, currentLedger=\(appContainer.currentLedger?.name ?? "nil")"
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        var msgs: [String] = []
        msgs.append("账本: \(ledger.name)")
        msgs.append("isShared: \(ledger.isShared)")
        msgs.append("shareRecordName: \(ledger.shareRecordName ?? "nil")")

        if let share = try? await fetchShare(for: ledger) {
            // 如果 CKShare 存在但 isShared 是 false，修复它
            if !ledger.isShared {
                ledger.isShared = true
                try? appContainer.coreDataStack.viewContext.save()
                msgs.append("已修复: isShared → true")
            }
            msgs.append("CKShare: recordID=\(share.recordID.recordName)")
            msgs.append("participants: \(share.participants.count)")
            for p in share.participants {
                let id = p.userIdentity.lookupInfo?.userRecordID?.recordName
                    ?? p.userIdentity.lookupInfo?.emailAddress
                    ?? p.userIdentity.lookupInfo?.phoneNumber
                    ?? "nil"
                msgs.append("  - role=\(p.role.rawValue) id=\(id) status=\(p.acceptanceStatus.rawValue)")
            }
            try? await appContainer.syncService?.syncParticipants(share: share, for: ledger)
            msgs.append("syncParticipants 完成")
        } else {
            msgs.append("CKShare: 未找到 (三种方式均失败)")
        }

        loadUsers()
        msgs.append("本地 User 数: \(users.count)")
        diagMessage = msgs.joined(separator: "\n")
    }

    private func fetchShare(for ledger: Ledger) async throws -> CKShare? {
        // 方式1：通过 shareRecordName 直接查询
        if let recordName = ledger.shareRecordName {
            let recordID = CKRecord.ID(recordName: recordName)
            if let share = try? await fetchCKShare(recordID: recordID) {
                return share
            }
        }

        // 方式2：通过 Core Data fetchShares 发现 (fallback，兼容旧共享账本)
        do {
            let stack = appContainer.coreDataStack
            let shares = try stack.container.fetchShares(matching: [ledger.objectID])
            if let share = shares[ledger.objectID] {
                // 补上 shareRecordName
                ledger.shareRecordName = share.recordID.recordName
                try? stack.viewContext.save()
                return share
            }
        } catch {
            DiagnosticLog.log("UserListView: fetchShares failed: \(error)")
        }

        // 方式3：遍历 shared database 中的 CKShare 记录
        do {
            let results = try await CKContainer.default().sharedCloudDatabase.records(
                matching: CKQuery(recordType: "cloudkit.share", predicate: NSPredicate(value: true))
            )
            for (_, result) in results.matchResults {
                if let share = try? result.get() as? CKShare {
                    ledger.shareRecordName = share.recordID.recordName
                    try? appContainer.coreDataStack.viewContext.save()
                    return share
                }
            }
        } catch {
            DiagnosticLog.log("UserListView: query shared db failed: \(error)")
        }

        return nil
    }

    private func fetchCKShare(recordID: CKRecord.ID) async throws -> CKShare? {
        let db = CKContainer.default()
        let records: [CKRecord.ID: Result<CKRecord, any Error>]
        do {
            records = try await db.sharedCloudDatabase.records(for: [recordID])
        } catch {
            records = try await db.privateCloudDatabase.records(for: [recordID])
        }
        guard let result = records[recordID], case .success(let record) = result,
              let share = record as? CKShare else { return nil }
        return share
    }

    private func loadUsers() {
        guard let ledger = effectiveLedger else { return }
        let ledgerID = ledger.id as CVarArg
        let request = NSFetchRequest<User>(entityName: "User")
        request.predicate = NSPredicate(format: "ledger.id == %@", ledgerID)
        request.sortDescriptors = [NSSortDescriptor(key: "joinedAt", ascending: true)]
        users = (try? modelContext.fetch(request)) ?? []
    }
}
