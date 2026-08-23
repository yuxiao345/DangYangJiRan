import SwiftUI
@preconcurrency import CoreData
import CloudKit

@Observable
@MainActor
final class AppContainer {
    static weak var shared: AppContainer?

    let coreDataStack: CoreDataStack
    var viewContext: NSManagedObjectContext { coreDataStack.viewContext }

    // Service instances
    let ledgerService: LedgerServiceProtocol
    let accountService: AccountServiceProtocol
    let transactionService: TransactionServiceProtocol
    let categoryService: CategoryServiceProtocol
    let templateService: TemplateServiceProtocol
    let recurringService: RecurringServiceProtocol
    let creditCardStatementService: CreditCardStatementServiceProtocol
    let reconciliationService: ReconciliationServiceProtocol
    #if os(iOS)
    let bankOCRService: BankOCRServiceProtocol
    #endif
    let memberService: MemberServiceProtocol
    let merchantService: MerchantServiceProtocol
    let projectService: ProjectServiceProtocol
    private(set) var splitService: SplitServiceProtocol?
    private(set) var budgetService: BudgetServiceProtocol
    private(set) var currencyService: CurrencyServiceProtocol?
    private(set) var exchangeRateService: ExchangeRateServiceProtocol?
    private(set) var syncService: SyncServiceProtocol?
    private(set) var exportService: ExportServiceProtocol?

    var cloudKitContainer: CKContainer?

    // App state
    var currentLedger: Ledger?
    /// Active ledger's currency code, falling back to CNY when no ledger is loaded.
    var currentCurrencyCode: String {
        currentLedger?.defaultCurrencyCode ?? "CNY"
    }
    var syncStatus: SyncStatus = .synced
    var isAuthenticated: Bool = false
    var currentUserRecordID: String?
    var shareErrorMessage: String?
    private var recentShareURLHashes: [String: Date] = [:]

    /// Whether the current user is the owner of the given ledger
    func isOwner(of ledger: Ledger) -> Bool {
        guard let rid = currentUserRecordID, let ownerRID = ledger.ownerUserRecordID else { return false }
        return rid == ownerRID
    }

    init() {
        // CoreDataStack
        let stack = CoreDataStack()
        self.coreDataStack = stack
        CoreDataStack.shared = stack

        // In UITEST_MODE, skip CloudKit container creation entirely so UI tests
        // don't touch iCloud account/network state. CoreDataStack itself also
        // switches to in-memory store when isUITestMode.
        if stack.isUITestMode {
            cloudKitContainer = nil
        } else {
            cloudKitContainer = CKContainer(identifier: CloudKitConfig.containerIdentifier)
        }

        // Services (protocols will be updated to take NSManagedObjectContext)
        ledgerService = LedgerServiceImpl()
        accountService = AccountServiceImpl()
        transactionService = TransactionServiceImpl()
        categoryService = CategoryServiceImpl()
        templateService = TemplateServiceImpl()
        recurringService = RecurringServiceImpl()
        memberService = MemberServiceImpl()
        merchantService = MerchantServiceImpl()
        projectService = ProjectServiceImpl()
        budgetService = BudgetServiceImpl()
        creditCardStatementService = CreditCardStatementServiceImpl()
        reconciliationService = ReconciliationServiceImpl()
        #if os(iOS)
        bankOCRService = BankOCRServiceImpl()
        #endif
        splitService = SplitServiceImpl()
        exportService = ExportServiceImpl()
        currencyService = CurrencyServiceImpl()
        exchangeRateService = ExchangeRateServiceImpl()
        if let ckContainer = cloudKitContainer {
            syncService = SyncServiceImpl(container: ckContainer, coreDataStack: stack)
        }

        Self.shared = self

        // Listen for deferred share acceptance
        NotificationCenter.default.addObserver(
            forName: .shareAccepted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.refreshAndSwitchToSharedLedger()
            }
        }

        // Deduplicate after CloudKit import
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.deduplicateLedgers()
                self?.deduplicateRecurring()
            }
        }
    }

    func loadStores() async throws {
        try await coreDataStack.loadStores()
        // Baseline for detecting the first CloudKit import — captured right
        // after stores load so imports that finish during the identity fetch
        // below still count.
        let storesLoadedAt = Date()

        // One-time repair: backfill missing member/merchant/project on historical refunds.
        // Must run after stores are loaded so data is available.
        repairRefundMetadataIfNeeded()

        guard coreDataStack.cloudKitAvailable else {
            configureDefaultLedger()
            return
        }

        // Fetch current iCloud user identity for permission checks
        await fetchCurrentUserIdentity()

        // Wait for CloudKit to import existing data before deciding
        // whether to create a default ledger. Without this, every
        // fresh install creates a duplicate "我的账本" because CloudKit
        // hasn't pulled the old one back yet. Only waits when the local
        // store is empty, so normal launches are unaffected.
        let context = viewContext
        let fetch = NSFetchRequest<Ledger>(entityName: "Ledger")
        if ((try? context.count(for: fetch)) ?? 0) == 0 {
            syncStatus = .syncing
            await coreDataStack.waitForInitialImport(since: storesLoadedAt)
            syncStatus = .synced
        }

        // Recover share acceptance for devices that auto-discovered a shared
        // store via metadata sync but never formally accepted the CKShare.
        // Per Apple docs, each iCloud account only needs to accept once —
        // the shared store should auto-discover on sibling devices. In practice,
        // auto-discovery creates the store but data may not sync bidirectionally
        // without a formal acceptShareInvitations call.
        await recoverShareAcceptance()

        configureDefaultLedger()
        validateCurrentLedgerShare()
    }

    private func fetchCurrentUserIdentity() async {
        guard let container = cloudKitContainer else { return }
        do {
            let recordID = try await container.userRecordID()
            currentUserRecordID = recordID.recordName
            DiagnosticLog.log("AppContainer: currentUserRecordID=\(recordID.recordName.prefix(8))")
        } catch {
            DiagnosticLog.log("AppContainer: fetchUserRecordID failed \(error.localizedDescription)")
        }
    }

    // MARK: - Share URL Handling

    private func shouldProcessShareURL(_ url: URL) -> Bool {
        let key = url.absoluteString
        let now = Date()
        if let last = recentShareURLHashes[key], now.timeIntervalSince(last) < 5 {
            DiagnosticLog.log("handleShareURL: skip duplicate within 5s")
            return false
        }
        recentShareURLHashes[key] = now
        recentShareURLHashes = recentShareURLHashes.filter { now.timeIntervalSince($0.value) < 30 }
        return true
    }

    private func presentShareError(_ error: Error) {
        let message = (error as NSError).domain == CKError.errorDomain
            ? String(localized: "共享失败，请检查网络或确认共享邀请仍然有效后重试")
            : String(localized: "共享失败，请稍后重试")
        shareErrorMessage = message
    }

    func handleShareURL(_ url: URL) async {
        guard shouldProcessShareURL(url) else { return }
        let count = UserDefaults.standard.integer(forKey: "diag_onOpenURLFired") + 1
        UserDefaults.standard.set(count, forKey: "diag_onOpenURLFired")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "diag_onOpenURLLastTime")

        DiagnosticLog.log("handleShareURL #\(count): \(url)")

        guard let container = cloudKitContainer else { return }
        do {
            let metadata = try await resolveShareMetadata(from: url, container: container)
            DiagnosticLog.log("handleShareURL: resolved metadata OK")
            UserDefaults.standard.set(true, forKey: "diag_onOpenURLResolved")
            await handleAcceptedShareMetadata(metadata)
        } catch {
            DiagnosticLog.log("handleShareURL: resolve failed \(error.localizedDescription)")
            UserDefaults.standard.set(error.localizedDescription, forKey: "diag_onOpenURLError")
            presentShareError(error)
        }
    }

    private func resolveShareMetadata(from url: URL, container: CKContainer) async throws -> CKShare.Metadata {
        if #available(iOS 26.0, *) {
            // Modern path: request share access + fetch metadata
            try await container.requestShareAccess(for: [url])
            let results = try await container.shareMetadatas(for: [url])
            guard let metadata = try results[url]?.get() else {
                throw SyncError.invalidShareURL
            }
            DiagnosticLog.log("resolveShareMetadata: iOS 26 path OK")
            return metadata
        } else {
            // Legacy path for iOS 18–25
            return try await withCheckedThrowingContinuation { continuation in
                var resumed = false
                let op = CKFetchShareMetadataOperation(shareURLs: [url])
                op.perShareMetadataBlock = { _, metadata, error in
                    if !resumed {
                        if let metadata {
                            resumed = true
                            continuation.resume(returning: metadata)
                        } else if let error {
                            resumed = true
                            continuation.resume(throwing: error)
                        }
                    }
                }
                op.fetchShareMetadataCompletionBlock = { error in
                    if !resumed {
                        resumed = true
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(throwing: SyncError.shareContainerNotReady)
                        }
                    }
                }
                container.add(op)
            }
        }
    }

    func handleAcceptedShareMetadata(_ metadata: CKShare.Metadata) async {
        DiagnosticLog.startSession("share accept \(Date())")
        DiagnosticLog.log("handleAcceptedShareMetadata: called")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "diag_acceptFlowStartTime")
        syncStatus = .error(String(localized: "接收开始"))

        do {
            // New join — clear stale tracker from any previous exit
            exitedSharedLedgerIDs.removeAll()

            // Clean up clone ledgers from previous exit operations
            cleanupCloneLedgers()

            syncStatus = .error(String(localized: "正在接受共享邀请"))
            try await syncService?.acceptShare(metadata: metadata)
            DiagnosticLog.log("handleAcceptedShareMetadata: accept OK, importing...")
            UserDefaults.standard.set(true, forKey: "diag_acceptInvitationOK")

            syncStatus = .error(String(localized: "共享邀请已接受，正在导入账本"))
            let imported = try await syncService?.importSharedData(into: coreDataStack) ?? []
            syncStatus = .error(String(localized: "导入结果：\(imported.count) 个账本"))
            UserDefaults.standard.set(imported.count, forKey: "diag_importLedgerCount")

            if let first = imported.first {
                DiagnosticLog.log("import: switched to \(first.name)")
                currentLedger = first
                UserDefaults.standard.set(first.id.uuidString, forKey: "currentLedgerID")
                first.shareRecordName = metadata.share.recordID.recordName
                do { try viewContext.save() }
                catch { DiagnosticLog.log("import: save shareRecordName FAILED \(error.localizedDescription)") }
                // Mark as recovered so relaunch won't re-accept (which fails with "CREATE operation not permitted")
                UserDefaults.standard.set(true, forKey: shareRecoveryKey(for: metadata.share.recordID.recordName))
                syncStatus = .error(String(localized: "已切换到共享账本：\(first.name)"))

                do {
                    try await syncService?.syncParticipants(metadata: metadata, for: first)
                    DiagnosticLog.log("import: participants synced")
                } catch {
                    DiagnosticLog.log("import: syncParticipants FAILED \(error.localizedDescription)")
                    syncStatus = .error(String(localized: "成员同步失败：\(error.localizedDescription)"))
                }
                return
            }

            DiagnosticLog.log("import: 0 ledgers returned, falling back")
            syncStatus = .error(String(localized: "导入 0 个账本，正在刷新本地账本列表"))
            await refreshAndSwitchToSharedLedger()
            // Attempt participant sync on fallback path too
            if let ledger = currentLedger, ledger.isShared {
                ledger.shareRecordName = metadata.share.recordID.recordName
                do { try viewContext.save() }
                catch { DiagnosticLog.log("fallback: save shareRecordName FAILED \(error.localizedDescription)") }
                UserDefaults.standard.set(true, forKey: shareRecoveryKey(for: metadata.share.recordID.recordName))
                do {
                    try await syncService?.syncParticipants(metadata: metadata, for: ledger)
                } catch {
                    DiagnosticLog.log("fallback: syncParticipants FAILED \(error.localizedDescription)")
                }
            }
        } catch {
            DiagnosticLog.log("handleAcceptedShareMetadata: FAILED \(error.localizedDescription)")
            UserDefaults.standard.set(error.localizedDescription, forKey: "diag_shareAcceptError")
            syncStatus = .error(String(localized: "共享失败：\(error.localizedDescription)"))
            presentShareError(error)
        }
    }

    /// Ledger IDs from shared store that the user has exited.
    /// Persisted so stale shared ledgers stay hidden across app restarts.
    var exitedSharedLedgerIDs: Set<UUID> {
        get {
            guard let data = UserDefaults.standard.data(forKey: "exitedSharedLedgerIDs") else { return [] }
            let strings = (try? JSONDecoder().decode([String].self, from: data)) ?? []
            return Set(strings.compactMap(UUID.init))
        }
        set {
            let strings = newValue.map(\.uuidString)
            if let data = try? JSONEncoder().encode(strings) {
                UserDefaults.standard.set(data, forKey: "exitedSharedLedgerIDs")
            }
        }
    }

    /// Delete all clone ledgers (from previous exit operations) in private store.
    /// Clones have "(副本)" in their name and isShared == false.
    /// Also cleans up orphaned child objects that survived failed cascade deletes.
    private func cleanupCloneLedgers() {
        let fetch = NSFetchRequest<Ledger>(entityName: "Ledger")
        fetch.predicate = NSPredicate(format: "isShared == NO")
        guard let ledgers = try? viewContext.fetch(fetch) else { return }

        let clones = ledgers.filter { $0.name.contains("(副本)") }
        let orphanCount = cleanupOrphanedObjects()

        if !clones.isEmpty || orphanCount > 0 {
            DiagnosticLog.log("AppContainer: clones=\(clones.count) orphans=\(orphanCount)")
        }

        for clone in clones {
            do {
                try ledgerService.deleteLedger(clone, context: viewContext)
                DiagnosticLog.log("AppContainer: deleted clone \(clone.name)")
            } catch {
                DiagnosticLog.log("AppContainer: failed to delete clone \(clone.name): \(error.localizedDescription)")
            }
        }
    }

    /// Delete orphaned objects in private store that have no parent ledger.
    /// These are remnants of failed cascade deletes from previous exit operations.
    /// Returns total count of deleted objects.
    private func cleanupOrphanedObjects() -> Int {
        let entityNames = ["Account", "Category", "Transaction", "TransactionTemplate",
                           "BudgetBook", "CreditCardStatement", "Member", "Merchant",
                           "Project", "SplitGroup", "User"]
        var total = 0

        for name in entityNames {
            let fetch = NSFetchRequest<NSManagedObject>(entityName: name)
            fetch.predicate = NSPredicate(format: "ledger == nil")
            guard let orphans = try? viewContext.fetch(fetch), !orphans.isEmpty else { continue }

            DiagnosticLog.log("AppContainer: orphan cleanup \(name)=\(orphans.count)")
            for obj in orphans {
                // Manually delete children of orphans too
                if let splitGroup = obj as? SplitGroup {
                    if let entries = splitGroup.entries {
                        for e in entries { viewContext.delete(e) }
                    }
                } else if let budgetBook = obj as? BudgetBook {
                    if let items = budgetBook.items {
                        for i in items { viewContext.delete(i) }
                    }
                } else if let category = obj as? Category {
                    if let children = category.children {
                        for c in children { viewContext.delete(c) }
                    }
                } else if let transaction = obj as? Transaction {
                    if let children = transaction.splitChildren {
                        for c in children { viewContext.delete(c) }
                    }
                } else if let template = obj as? TransactionTemplate {
                    if let rule = template.recurringRule {
                        viewContext.delete(rule)
                    }
                } else if let account = obj as? Account {
                    if let statements = account.creditCardStatements {
                        for s in statements { viewContext.delete(s) }
                    }
                }
                viewContext.delete(obj)
                total += 1
            }
        }

        if total > 0 {
            do {
                try viewContext.save()
                DiagnosticLog.log("AppContainer: orphan cleanup saved \(total) objects")
            } catch {
                DiagnosticLog.log("AppContainer: orphan cleanup save FAILED \(error.localizedDescription)")
            }
        }
        return total
    }

    // MARK: - Ledger Management

    @MainActor
    private func refreshAndSwitchToSharedLedger() {
        let context = viewContext
        let fetch = NSFetchRequest<Ledger>(entityName: "Ledger")
        guard let ledgers = try? context.fetch(fetch) else {
            syncStatus = .error(String(localized: "刷新失败：无法读取本地账本"))
            return
        }

        for l in ledgers {
            DiagnosticLog.log("Ledger: id=\(l.id.uuidString.prefix(8)), name=\(l.name), isShared=\(l.isShared)")
        }

        let newSharedLedger = ledgers.first { ledger in
            ledger.id != currentLedger?.id && ledger.isShared
        }
        if let shared = newSharedLedger {
            currentLedger = shared
            UserDefaults.standard.set(shared.id.uuidString, forKey: "currentLedgerID")
            syncStatus = .error(String(localized: "刷新后切换到共享账本：\(shared.name)"))
            return
        }

        if let anyNew = ledgers.first(where: { $0.id != currentLedger?.id }) {
            currentLedger = anyNew
            UserDefaults.standard.set(anyNew.id.uuidString, forKey: "currentLedgerID")
            syncStatus = .error(String(localized: "刷新后切换到新账本：\(anyNew.name)"))
        } else {
            syncStatus = .error(String(localized: "刷新完成：未发现新的共享账本"))
        }
    }

    func configureDefaultLedger() {
        let context = viewContext

        // Restore last used ledger from UserDefaults
        if let idString = UserDefaults.standard.string(forKey: "currentLedgerID"),
           let uuid = UUID(uuidString: idString) {
            let fetch = NSFetchRequest<Ledger>(entityName: "Ledger")
            if let restored = try? context.fetch(fetch).first(where: { $0.id == uuid }) {
                currentLedger = restored
                return
            }
        }

        // If a ledger already exists, just load it
        let fetch = NSFetchRequest<Ledger>(entityName: "Ledger")
        if let existingLedger = try? context.fetch(fetch).first {
            currentLedger = existingLedger
            return
        }

        // First launch — create default ledger and seed data
        let ledger = Ledger(name: "我的账本", type: .personal, context: context)

        CategorySeeder.seed(modelContext: context, ledger: ledger)
        MerchantSeeder.seed(modelContext: context, ledger: ledger)

        // Seed default accounts
        let cash = Account(name: "现金", currencyCode: "CNY", type: .cash, iconName: "banknote", colorHex: "#4CAF50", sortOrder: 0, context: context)
        let debitCard = Account(name: "工资卡", currencyCode: "CNY", type: .debitCard, iconName: "creditcard.and.123", colorHex: "#2196F3", sortOrder: 1, context: context)
        let creditCard = Account(name: "信用卡", currencyCode: "CNY", type: .creditCard, iconName: "creditcard", colorHex: "#FF9800", creditLimit: 50000, sortOrder: 2, context: context)
        let eWallet = Account(name: "微信支付", currencyCode: "CNY", type: .eWallet, iconName: "wallet.pass", colorHex: "#4CAF50", sortOrder: 3, context: context)
        for a in [cash, debitCard, creditCard, eWallet] {
            a.ledger = ledger
        }

        // Seed default members
        let memberNames = ["自己", "配偶", "孩子"]
        for (i, name) in memberNames.enumerated() {
            let m = Member(name: name, avatar: ["person.circle", "heart.circle", "figure.child.circle"][i], sortOrder: i, context: context)
            m.ledger = ledger
        }

        // Seed default project
        let project = Project(name: "日常", desc: "日常收支", isActive: true, sortOrder: 0, context: context)
        project.ledger = ledger

        try? context.save()
        currentLedger = ledger
    }

    // MARK: - Deduplication

    /// One-time repair: backfill member/merchant/project on historical refund transactions.
    /// Runs once per app version, safe to call repeatedly (predicate skips already-repaired records).
    private func repairRefundMetadataIfNeeded() {
        let key = "refundMetadataRepaired_v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        do {
            try transactionService.repairRefundMetadata(context: viewContext)
            UserDefaults.standard.set(true, forKey: key)
            DiagnosticLog.log("AppContainer: refund metadata repair completed")
        } catch {
            DiagnosticLog.log("AppContainer: refund metadata repair FAILED: \(error.localizedDescription)")
        }
    }

    /// Remove duplicate ledgers (same name) that can appear after uninstall/reinstall
    /// when CloudKit syncs back old data alongside newly-created defaults.
    func deduplicateLedgers() {
        let context = viewContext
        let fetch = NSFetchRequest<Ledger>(entityName: "Ledger")
        guard let allLedgers = try? context.fetch(fetch) else { return }

        let grouped = Dictionary(grouping: allLedgers, by: { $0.name })
        for (name, ledgers) in grouped where ledgers.count > 1 {
            DiagnosticLog.log("AppContainer: dedup found \(ledgers.count) ledgers named '\(name)'")
            // Keep the ledger with the most transactions; delete the rest
            let sorted = ledgers.sorted { ($0.transactions?.count ?? 0) > ($1.transactions?.count ?? 0) }
            let keep = sorted.first!
            for dup in sorted.dropFirst() {
                DiagnosticLog.log("AppContainer: dedup deleting duplicate ledger id=\(dup.id.uuidString.prefix(8))")
                context.delete(dup)
            }
            // If currentLedger was one of the deleted ones, switch to the kept one
            if currentLedger.map({ $0 != keep }) ?? true {
                currentLedger = keep
                UserDefaults.standard.set(keep.id.uuidString, forKey: "currentLedgerID")
            }
            try? context.save()
        }
    }

    /// Remove duplicate recurring transactions (same template + same day) that can appear
    /// when multiple devices trigger processDueRecurring before iCloud sync propagates.
    func deduplicateRecurring() {
        do {
            try recurringService.deduplicateRecurringTransactions(context: viewContext)
        } catch {
            DiagnosticLog.log("AppContainer: deduplicateRecurring FAILED: \(error.localizedDescription)")
        }
    }

    // MARK: - Share Validation

    func validateCurrentLedgerShare() {
        guard let ledger = currentLedger, let svc = syncService else { return }

        Task {
            do {
                // 主动发现 CKShare，不依赖 isShared 当前值
                if let share = try await svc.discoverShare(for: ledger) {
                    await MainActor.run {
                        var changed = false
                        if !ledger.isShared { ledger.isShared = true; changed = true }
                        if ledger.shareRecordName == nil { ledger.shareRecordName = share.recordID.recordName; changed = true }
                        if share.currentUserParticipant?.role == .owner,
                           ledger.ownerUserRecordID != currentUserRecordID {
                            ledger.ownerUserRecordID = currentUserRecordID
                            changed = true
                        }
                        if changed { try? viewContext.save() }
                    }
                } else if ledger.isShared {
                    // 之前标记为共享但 CKShare 不存在 → 已失效
                    await MainActor.run {
                        ledger.isShared = false
                        ledger.shareRecordName = nil
                        try? viewContext.save()
                        syncStatus = .shareInvalid
                    }
                }
            } catch {
                DiagnosticLog.log("AppContainer: share validation error: \(error)")
            }
        }
    }

    /// Accept CKShare on devices where the shared store was auto-discovered
    /// via metadata sync but `acceptShareInvitations` was never called.
    ///
    /// Apple's design (per "Accepting Share Invitations in a SwiftUI App"):
    /// once a share is accepted on one device, CKShare metadata syncs through
    /// the private database to all sibling devices with the same iCloud account.
    /// The container auto-creates the shared store, but without a formal
    /// `acceptShareInvitations` call, data may not sync bidirectionally.
    ///
    /// This method detects that state and completes the acceptance.
    private func shareRecoveryKey(for recordName: String) -> String { "shareRecovered_\(recordName)" }

    private func recoverShareAcceptance() async {
        let hasSharedStore = coreDataStack.sharedStore != nil
        DiagnosticLog.log("AppContainer: recoverShareAcceptance begin sharedStore=\(hasSharedStore)")
        guard hasSharedStore else { return }

        // Fetch ALL ledgers to diagnose what's in the stores
        let allFetch = NSFetchRequest<Ledger>(entityName: "Ledger")
        let allLedgers = (try? viewContext.fetch(allFetch)) ?? []
        DiagnosticLog.log("AppContainer: recovery — total ledgers=\(allLedgers.count)")
        for l in allLedgers {
            DiagnosticLog.log("AppContainer: recovery ledger name=\(l.name) isShared=\(l.isShared) shrRN=\(l.shareRecordName?.prefix(8) ?? "nil")")
        }

        // Also check shared store specifically
        if let sharedStore = coreDataStack.sharedStore {
            let sharedFetch = NSFetchRequest<Ledger>(entityName: "Ledger")
            sharedFetch.affectedStores = [sharedStore]
            let sharedCount = (try? viewContext.count(for: sharedFetch)) ?? -1
            DiagnosticLog.log("AppContainer: recovery — ledgers in shared store=\(sharedCount)")
        }

        // Find shared ledgers — isShared OR has shareRecordName
        // Skip ledgers owned by the current user: the creator doesn't need
        // to accept their own share; calling acceptShareInvitations for
        // a self-created share always fails.
        var candidates: [Ledger] = []
        for l in allLedgers {
            if (l.isShared || l.shareRecordName != nil) && !isOwner(of: l) {
                candidates.append(l)
            }
        }
        DiagnosticLog.log("AppContainer: recovery — candidates=\(candidates.count)")

        // Filter to ledgers not yet recovered (per-shareRecordName tracking)
        let pending = candidates.filter { ledger in
            !UserDefaults.standard.bool(forKey: shareRecoveryKey(for: ledger.shareRecordName ?? ledger.id.uuidString))
        }
        guard !pending.isEmpty else {
            DiagnosticLog.log("AppContainer: recovery — all candidates already recovered")
            return
        }

        DiagnosticLog.log("AppContainer: share recovery — \(pending.count)/\(candidates.count) pending")
        UserDefaults.standard.set(pending.count, forKey: "diag_recoveryLedgerCount")

        guard let svc = syncService, let container = cloudKitContainer else { return }

        for ledger in pending {
            let perLedgerKey = shareRecoveryKey(for: ledger.shareRecordName ?? ledger.id.uuidString)
            DiagnosticLog.log("AppContainer: recovering share for [\(ledger.name)] recordName=\(ledger.shareRecordName?.prefix(8) ?? "nil")…")

            do {
                // Try to get shareRecordName from the shared store if missing locally
                if ledger.shareRecordName == nil, let sharedStore = coreDataStack.sharedStore {
                    if let shares = try? coreDataStack.container.fetchShares(matching: [ledger.objectID]),
                       let (_, share) = shares.first {
                        ledger.shareRecordName = share.recordID.recordName
                        try? viewContext.save()
                        DiagnosticLog.log("AppContainer: recovery — set shareRecordName=\(share.recordID.recordName.prefix(8))")
                    }
                }

                guard let recordName = ledger.shareRecordName else {
                    DiagnosticLog.log("AppContainer: recovery — NO shareRecordName, cannot recover")
                    continue
                }
                guard let share = try await svc.discoverShare(for: ledger) else {
                    DiagnosticLog.log("AppContainer: recovery — CKShare not found, skipping")
                    continue
                }
                guard let shareURL = share.url else {
                    DiagnosticLog.log("AppContainer: recovery — CKShare has no URL, skipping")
                    continue
                }

                let metadata = try await resolveShareMetadata(from: shareURL, container: container)
                try await coreDataStack.acceptShareInvitations(from: metadata)
                DiagnosticLog.log("AppContainer: recovery — accepted, waiting for import…")

                await coreDataStack.waitForImportSettled()

                let imported = try await svc.importSharedData(into: coreDataStack)
                DiagnosticLog.log("AppContainer: recovery — imported \(imported.count) ledgers")

                for l in imported {
                    try? await svc.syncParticipants(metadata: metadata, for: l)
                }

                // Mark this specific share as recovered
                UserDefaults.standard.set(true, forKey: perLedgerKey)
                DiagnosticLog.log("AppContainer: share recovery OK for [\(ledger.name)]")

                // Switch to the first successfully recovered ledger if none is active
                if currentLedger == nil, let first = imported.first {
                    currentLedger = first
                    UserDefaults.standard.set(first.id.uuidString, forKey: "currentLedgerID")
                }
            } catch {
                DiagnosticLog.log("AppContainer: recovery FAIL for [\(ledger.name)]: \(error.localizedDescription)")
                UserDefaults.standard.set(error.localizedDescription, forKey: "diag_recoveryError")
            }
        }
    }
}

enum SyncStatus {
    case synced
    case syncing
    case offline
    case shareInvalid
    case error(String)

    var displayName: String {
        switch self {
        case .synced: return NSLocalizedString("已同步", comment: "")
        case .syncing: return NSLocalizedString("同步中...", comment: "")
        case .offline: return NSLocalizedString("离线", comment: "")
        case .shareInvalid: return NSLocalizedString("共享已失效", comment: "")
        case .error(let msg): return msg
        }
    }
}
