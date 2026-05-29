import Foundation
@preconcurrency import CoreData
import CloudKit

final class SyncServiceImpl: SyncServiceProtocol {
    private let ckContainer: CKContainer
    private let coreDataStack: CoreDataStack
    private let database: CKDatabase
    private var eventObserver: NSObjectProtocol?

    var status: SyncStatus = .synced

    init(container: CKContainer, coreDataStack: CoreDataStack) {
        self.ckContainer = container
        self.coreDataStack = coreDataStack
        self.database = container.privateCloudDatabase
        observeEvents()
    }

    deinit {
        if let observer = eventObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func startSync() async throws {
        status = .syncing
        do {
            _ = try await ckContainer.accountStatus()
            status = .synced
            Logger.info("CloudKit sync started successfully")
        } catch let error as CKError {
            switch error.code {
            case .networkUnavailable, .networkFailure: status = .offline
            default: status = .error(error.localizedDescription)
            }
            Logger.error("CloudKit sync start failed: \(error)")
            throw error
        }
    }

    func syncNow() async throws {
        status = .syncing
        do {
            let accountStatus = try await ckContainer.accountStatus()
            guard accountStatus == .available else { status = .offline; return }
            _ = try await database.records(matching: CKQuery(recordType: "Ledger", predicate: NSPredicate(value: true)))
            status = .synced
        } catch let error as CKError {
            switch error.code {
            case .networkUnavailable, .networkFailure: status = .offline
            default: status = .error(error.localizedDescription)
            }
            throw error
        }
    }

    @MainActor
    func createShare(for ledger: Ledger) async throws -> CKShare {
        DiagnosticLog.log("SyncService.createShare: using CloudKitShareCoordinator")
        // 必须在 share() 之前设置 ownerUserRecordID，这样共享数据库才有正确值
        if ledger.ownerUserRecordID == nil || ledger.ownerUserRecordID?.isEmpty == true {
            ledger.ownerUserRecordID = try? await ckContainer.userRecordID().recordName
            try? coreDataStack.viewContext.save()
        }
        let share = try await CloudKitShareCoordinator.shared.createShare(
            ledgerID: ledger.id,
            name: ledger.name
        )
        ledger.shareRecordName = share.recordID.recordName
        return share
    }

    @MainActor
    func acceptShare(metadata: CKShare.Metadata) async throws {
        DiagnosticLog.log("SyncService.acceptShare: delegating to CloudKitShareCoordinator")
        try await CloudKitShareCoordinator.shared.accept(metadata)
        NotificationCenter.default.post(name: .shareAccepted, object: nil)
    }

    @MainActor
    func importSharedData(into stack: CoreDataStack) async throws -> [Ledger] {
        DiagnosticLog.log("SyncService.importSharedData: polling for shared data...")

        let coordinator = CloudKitShareCoordinator.shared

        for attempt in 1...30 {
            let count = (try? await coordinator.pollForLedgersOnlyCount()) ?? -1
            let hasData = count > 0
            DiagnosticLog.log("importSharedData poll [\(attempt)]: count=\(count) hasData=\(hasData)")

            if hasData {
                DiagnosticLog.log("importSharedData: data found on attempt \(attempt), waiting for import to settle...")
                await stack.waitForImportSettled()
                DiagnosticLog.log("importSharedData: import settled, importing...")
                let container = try await coordinator.containerForImport()
                let sharedStore = try await coordinator.sharedStoreForImport()
                let imported = try await SharedLedgerImportService.shared.importSharedLedgers(
                    from: container,
                    sharedStore: sharedStore,
                    into: stack.viewContext
                )
                DiagnosticLog.log("importSharedData: imported \(imported.count) ledger(s)")
                return imported
            }

            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }

        DiagnosticLog.log("importSharedData: TIMEOUT after 60s (30 attempts)")
        throw SyncError.shareContainerNotReady
    }

    func fetchParticipants(for ledger: Ledger) async throws -> [CKShare.Participant] {
        let shares = try await ckContainer.sharedCloudDatabase.records(
            matching: CKQuery(recordType: "cloudkit.share", predicate: NSPredicate(value: true))
        )
        var participants: [CKShare.Participant] = []
        for result in shares.matchResults {
            if let record = try? result.1.get() as? CKShare {
                participants.append(contentsOf: record.participants)
            }
        }
        return participants
    }

    @MainActor
    func syncParticipants(metadata: CKShare.Metadata, for ledger: Ledger) async throws {
        DiagnosticLog.log("SyncService.syncParticipants(metadata): begin share=\(metadata.share.recordID)")
        try await syncParticipantsFromShare(metadata.share, ledger: ledger)
    }

    @MainActor
    func syncParticipants(share: CKShare, for ledger: Ledger) async throws {
        DiagnosticLog.log("SyncService.syncParticipants(share): begin share=\(share.recordID)")
        try await syncParticipantsFromShare(share, ledger: ledger)
    }

    @MainActor
    private func syncParticipantsFromShare(_ share: CKShare, ledger: Ledger) async throws {
        let context = coreDataStack.viewContext
        let participants = share.participants.filter { $0.acceptanceStatus == .accepted }

        DiagnosticLog.log("syncParticipantsFromShare: total participants in CKShare = \(share.participants.count), accepted = \(participants.count)")
        for (i, p) in participants.enumerated() {
            let lookupInfo = p.userIdentity.lookupInfo
            DiagnosticLog.log("syncParticipantsFromShare: participant[\(i)] role=\(p.role.rawValue) acceptance=\(p.acceptanceStatus.rawValue) recordID=\(lookupInfo?.userRecordID?.recordName ?? "nil") email=\(lookupInfo?.emailAddress ?? "nil") phone=\(lookupInfo?.phoneNumber ?? "nil")")
        }

        // 清空该账本所有现有 User，从 CKShare 参与者重新创建，避免重复
        let fetch = NSFetchRequest<User>(entityName: "User")
        let allUsers = try context.fetch(fetch)
        for user in allUsers where user.ledger?.id == ledger.id {
            context.delete(user)
        }
        var existingByRecordID: [String: User] = [:]

        let myRecordID = try? await ckContainer.userRecordID().recordName

        for participant in participants {
            let lookupInfo = participant.userIdentity.lookupInfo
            // Prefer userRecordID; fall back to email or phone for pending participants
            var recordID = lookupInfo?.userRecordID?.recordName ?? ""
            if recordID.isEmpty {
                recordID = lookupInfo?.emailAddress ?? lookupInfo?.phoneNumber ?? ""
            }
            // Owner with no identity info — try multiple sources for a meaningful recordID
            if recordID.isEmpty && participant.role == .owner {
                recordID = ledger.ownerUserRecordID
                    ?? share.creatorUserRecordID?.recordName
                    ?? "owner-\(ledger.id.uuidString.prefix(8))"
            }
            if recordID.isEmpty { continue }

            var name = participant.userIdentity.nameComponents?.formatted(.name(style: .medium))
                ?? lookupInfo?.emailAddress
                ?? lookupInfo?.phoneNumber
                ?? ""

            // Owner with no resolved name — try CloudKit identity lookup
            if name.isEmpty && participant.role == .owner && !recordID.hasPrefix("owner-") {
                do {
                    // 先请求 userDiscoverability 权限（Apple 文档要求）
                    let permissionStatus = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CKContainer.ApplicationPermissionStatus, Error>) in
                        ckContainer.status(forApplicationPermission: .userDiscoverability) { status, error in
                            if let error { cont.resume(throwing: error) }
                            else { cont.resume(returning: status) }
                        }
                    }
                    if permissionStatus != .granted {
                        let granted = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Bool, Error>) in
                            ckContainer.requestApplicationPermission(.userDiscoverability) { status, error in
                                if let error { cont.resume(throwing: error) }
                                else { cont.resume(returning: status == .granted) }
                            }
                        }
                        if !granted {
                            DiagnosticLog.log("SyncService: userDiscoverability permission denied")
                            throw CKError(.permissionFailure)
                        }
                    }
                    // 使用与 recordID 同一个 container 进行查找
                    let identity = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKUserIdentity, Error>) in
                        ckContainer.discoverUserIdentity(withUserRecordID: CKRecord.ID(recordName: recordID)) { identity, error in
                            if let identity {
                                continuation.resume(returning: identity)
                            } else {
                                continuation.resume(throwing: error ?? CKError(.internalError))
                            }
                        }
                    }
                    name = identity.lookupInfo?.emailAddress
                        ?? {
                            if let nc = identity.nameComponents {
                                return PersonNameComponentsFormatter().string(from: nc)
                            }
                            return nil
                        }()
                        ?? ""
                } catch let error as CKError {
                    DiagnosticLog.log("SyncService: discoverUserIdentity CKError code=\(error.code.rawValue)")
                } catch {
                    DiagnosticLog.log("SyncService: discoverUserIdentity error \(error.localizedDescription)")
                }
            }

            // 当前用户在自己设备上看到自己时，显示「我」
            let currentEmail = share.currentUserParticipant?.userIdentity.lookupInfo?.emailAddress
            let isMe = participant === share.currentUserParticipant
                || recordID == myRecordID
                || (lookupInfo?.emailAddress != nil && lookupInfo?.emailAddress == currentEmail)
                || (participant.role == .owner && share.currentUserParticipant?.role == .owner)

            if name.isEmpty {
                if isMe {
                    name = "我"
                } else if participant.role == .owner {
                    name = "创建者"
                } else {
                    name = "共享成员"
                }
            } else if isMe {
                name = "我"
            }

            let role: LedgerRole = participant.role == .owner ? .owner : .member
            DiagnosticLog.log("SyncService.syncParticipants: participant recordID=\(recordID) name=\(name) role=\(role.rawValue) acceptance=\(participant.acceptanceStatus.rawValue)")

            if let existing = existingByRecordID[recordID] {
                existing.displayName = name
                existing.role = role
                DiagnosticLog.log("SyncService.syncParticipants: updated existing user \(name)")
            } else {
                let user = User(displayName: name, cloudKitUserRecordID: recordID, role: role, context: context)
                user.ledger = ledger
                existingByRecordID[recordID] = user
                DiagnosticLog.log("SyncService.syncParticipants: created user \(name)")
            }
        }

        if context.hasChanges {
            try context.save()
            DiagnosticLog.log("SyncService.syncParticipants: saved users")
        }
    }

    func discoverShare(for ledger: Ledger) async throws -> CKShare? {
        // 方式1：通过 shareRecordName
        if let recordName = ledger.shareRecordName {
            let recordID = CKRecord.ID(recordName: recordName)
            do {
                let records = try await ckContainer.sharedCloudDatabase.records(for: [recordID])
                if let share = records[recordID] as? CKShare { return share }
            } catch {}
        }

        // 方式2：通过 Core Data fetchShares
        do {
            let shares = try coreDataStack.container.fetchShares(matching: [ledger.objectID])
            if let share = shares[ledger.objectID] { return share }
        } catch {}

        // 方式3：直接查询 shared database 中的 CKShare 记录
        do {
            let results = try await ckContainer.sharedCloudDatabase.records(
                matching: CKQuery(recordType: "cloudkit.share", predicate: NSPredicate(value: true))
            )
            for (_, result) in results.matchResults {
                if let share = try? result.get() as? CKShare { return share }
            }
        } catch {}

        return nil
    }

    func validateShare(for ledger: Ledger) async throws -> Bool {
        guard ledger.isShared, let recordName = ledger.shareRecordName else {
            return true // 非共享账本，不需要校验
        }
        DiagnosticLog.log("SyncService.validateShare: checking recordName=\(recordName)")
        let recordID = CKRecord.ID(recordName: recordName)
        do {
            let records = try await ckContainer.sharedCloudDatabase.records(for: [recordID])
            guard let share = records[recordID] as? CKShare else {
                DiagnosticLog.log("SyncService.validateShare: share not found, may be deleted")
                return false
            }
            // 检查当前用户是否仍在参与者中
            let currentUserID = try await ckContainer.userRecordID().recordName
            let isParticipant = share.participants.contains { p in
                p.userIdentity.lookupInfo?.userRecordID?.recordName == currentUserID
                && p.acceptanceStatus == .accepted
            }
            DiagnosticLog.log("SyncService.validateShare: valid=\(isParticipant)")
            return isParticipant
        } catch let error as CKError where error.code == .unknownItem {
            DiagnosticLog.log("SyncService.validateShare: CKShare deleted (unknownItem)")
            return false
        } catch {
            // 网络错误等不确定因素，保守返回 true 避免误伤
            DiagnosticLog.log("SyncService.validateShare: network/error, assuming valid: \(error)")
            return true
        }
    }

    func removeParticipant(_ participant: CKShare.Participant, from ledger: Ledger) async throws {
        Logger.info("Removing participant from share")
    }

    private func observeEvents() {
        eventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }

            guard let event = notification.userInfo?["event"] as? NSPersistentCloudKitContainer.Event else {
                return
            }

            if event.succeeded {
                self.status = .synced
            } else if let error = event.error {
                let ckError = error as? CKError
                if ckError?.code == .networkUnavailable || ckError?.code == .networkFailure {
                    self.status = .offline
                } else {
                    self.status = .error(error.localizedDescription)
                }
            }
        }
    }
}

extension Notification.Name {
    static let shareAccepted = Notification.Name("shareAccepted")
}

enum SyncError: LocalizedError {
    case invalidShareTarget
    case invalidShareURL
    case shareContainerNotReady

    var errorDescription: String? {
        switch self {
        case .invalidShareTarget: return "无效的分享目标"
        case .invalidShareURL: return "无效的分享链接"
        case .shareContainerNotReady: return "同步未就绪，请确认 iCloud 已登录且网络正常"
        }
    }
}
