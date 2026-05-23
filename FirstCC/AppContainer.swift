import SwiftUI
import SwiftData
import CloudKit
import CoreData

@MainActor
final class AppContainer: ObservableObject {
    // Static ref so SceneDelegate can access without view hierarchy dependency
    static weak var shared: AppContainer?

    let modelContainer: ModelContainer

    // Service instances
    let ledgerService: LedgerServiceProtocol
    let accountService: AccountServiceProtocol
    let transactionService: TransactionServiceProtocol
    let categoryService: CategoryServiceProtocol
    let templateService: TemplateServiceProtocol
    let recurringService: RecurringServiceProtocol
    let creditCardStatementService: CreditCardStatementServiceProtocol
    let reconciliationService: ReconciliationServiceProtocol
    let bankOCRService: BankOCRServiceProtocol
    let memberService: MemberServiceProtocol
    let merchantService: MerchantServiceProtocol
    let projectService: ProjectServiceProtocol
    private(set) var splitService: SplitServiceProtocol?
    private(set) var budgetService: BudgetServiceProtocol
    private(set) var currencyService: CurrencyServiceProtocol?
    private(set) var exchangeRateService: ExchangeRateServiceProtocol?
    private(set) var syncService: SyncServiceProtocol?
    private(set) var exportService: ExportServiceProtocol?

    // CloudKit (Phase 3: configure with entitlements)
    var cloudKitContainer: CKContainer?

    // App state
    @Published var currentLedger: Ledger?
    @Published var syncStatus: SyncStatus = .synced
    @Published var isAuthenticated: Bool = false

    init() {
        let schema = Schema(versionedSchema: FirstCCSchemaV4.self)

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .automatic
        )

        do {
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        } catch {
            // If schema changed, fallback: delete incompatible store and recreate
            Logger.error("ModelContainer failed, recreating: \(error)")
            let fileManager = FileManager.default
            if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let storeURL = appSupport.appendingPathComponent("default.store")
                try? fileManager.removeItem(at: storeURL)
                try? fileManager.removeItem(atPath: storeURL.path + "-wal")
                try? fileManager.removeItem(atPath: storeURL.path + "-shm")
            }
            modelContainer = try! ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        }

        // CloudKit container — sync engine for multi-device & sharing
        cloudKitContainer = CKContainer(identifier: CloudKitConfig.containerIdentifier)

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
        bankOCRService = BankOCRServiceImpl()
        splitService = SplitServiceImpl()
        exportService = ExportServiceImpl()
        currencyService = CurrencyServiceImpl()
        exchangeRateService = ExchangeRateServiceImpl()
        if let ckContainer = cloudKitContainer {
            syncService = SyncServiceImpl(container: ckContainer, modelContainer: modelContainer)
        }

        Self.shared = self

        // Listen for deferred share acceptance (when persistentContainer becomes available)
        NotificationCenter.default.addObserver(
            forName: .shareAccepted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self?.refreshAndSwitchToSharedLedger()
            }
        }
    }

    func handleShareURL(_ url: URL) async {
        let count = UserDefaults.standard.integer(forKey: "diag_onOpenURLFired") + 1
        UserDefaults.standard.set(count, forKey: "diag_onOpenURLFired")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "diag_onOpenURLLastTime")

        DiagnosticLog.log("handleShareURL #\(count): \(url)")
        Logger.info("handleShareURL #\(count): \(url)")

        // Try CKFetchShareMetadataOperation to resolve share URL → metadata
        guard let container = cloudKitContainer else { return }
        do {
            let metadata = try await resolveShareMetadata(from: url, container: container)
            DiagnosticLog.log("handleShareURL: resolved metadata OK")
            UserDefaults.standard.set(true, forKey: "diag_onOpenURLResolved")
            await handleAcceptedShareMetadata(metadata)
        } catch {
            DiagnosticLog.log("handleShareURL: resolve failed \(error.localizedDescription)")
            UserDefaults.standard.set(error.localizedDescription, forKey: "diag_onOpenURLError")
        }
    }

    private func resolveShareMetadata(from url: URL, container: CKContainer) async throws -> CKShare.Metadata {
        try await withCheckedThrowingContinuation { continuation in
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

    func handleAcceptedShareMetadata(_ metadata: CKShare.Metadata) async {
        DiagnosticLog.startSession("share accept \(Date())")
        DiagnosticLog.log("handleAcceptedShareMetadata: called")
        Logger.info("=== SHARE ACCEPT: handleAcceptedShareMetadata called ===")
        syncStatus = .error("接收开始")

        do {
            syncStatus = .error("正在接受共享邀请")
            try await syncService?.acceptShare(metadata: metadata)
            DiagnosticLog.log("handleAcceptedShareMetadata: accept OK, importing...")
            Logger.info("=== SHARE ACCEPT: accept succeeded, importing shared data ===")

            syncStatus = .error("共享邀请已接受，正在导入账本")
            let imported = try await syncService?.importSharedData(into: modelContainer) ?? []
            syncStatus = .error("导入结果：\(imported.count) 个账本")

            if let first = imported.first {
                DiagnosticLog.log("import: switched to \(first.name)")
                currentLedger = first
                UserDefaults.standard.set(first.id.uuidString, forKey: "currentLedgerID")
                Logger.info("=== IMPORT: switched to \(first.name) ===")
                syncStatus = .error("已切换到共享账本：\(first.name)")
                return
            }

            DiagnosticLog.log("import: 0 ledgers returned, falling back")
            Logger.info("=== IMPORT: 0 ledgers returned, refreshing ===")
            syncStatus = .error("导入 0 个账本，正在刷新本地账本列表")
            await refreshAndSwitchToSharedLedger()
        } catch {
            DiagnosticLog.log("handleAcceptedShareMetadata: FAILED \(error.localizedDescription)")
            Logger.error("=== SHARE ACCEPT FAILED: \(error) ===")
            syncStatus = .error("共享失败：\(error.localizedDescription)")
        }
    }

    @MainActor
    private func refreshAndSwitchToSharedLedger() {
        let context = modelContainer.mainContext
        guard let ledgers = try? context.fetch(FetchDescriptor<Ledger>()) else {
            Logger.error("=== REFRESH: fetch ledgers failed ===")
            syncStatus = .error("刷新失败：无法读取本地账本")
            return
        }

        Logger.info("=== REFRESH: found \(ledgers.count) ledger(s) total ===")
        for l in ledgers {
            Logger.info("  Ledger: id=\(l.id.uuidString.prefix(8)), name=\(l.name), isShared=\(l.isShared)")
        }

        // Try finding shared ledger first
        let newSharedLedger = ledgers.first { ledger in
            ledger.id != currentLedger?.id && ledger.isShared
        }
        if let shared = newSharedLedger {
            currentLedger = shared
            UserDefaults.standard.set(shared.id.uuidString, forKey: "currentLedgerID")
            Logger.info("=== REFRESH: switched to shared ledger \(shared.name) ===")
            syncStatus = .error("刷新后切换到共享账本：\(shared.name)")
            return
        }

        // Fallback: any new ledger (shared flag might not have synced yet)
        if let anyNew = ledgers.first(where: { $0.id != currentLedger?.id }) {
            Logger.info("=== REFRESH: found new ledger (isShared=\(anyNew.isShared)): \(anyNew.name) ===")
            currentLedger = anyNew
            UserDefaults.standard.set(anyNew.id.uuidString, forKey: "currentLedgerID")
            syncStatus = .error("刷新后切换到新账本：\(anyNew.name)")
        } else {
            Logger.info("=== REFRESH: no new ledger found ===")
            syncStatus = .error("刷新完成：未发现新的共享账本")
        }
    }

    func configureDefaultLedger(modelContext: ModelContext) {
        // Restore last used ledger from UserDefaults
        if let idString = UserDefaults.standard.string(forKey: "currentLedgerID"),
           let uuid = UUID(uuidString: idString),
           let restored = try? modelContext.fetch(FetchDescriptor<Ledger>()).first(where: { $0.id == uuid }) {
            currentLedger = restored
            return
        }

        // If a ledger already exists, just load it
        if let existingLedger = try? modelContext.fetch(FetchDescriptor<Ledger>()).first {
            currentLedger = existingLedger
            return
        }

        // First launch — create default ledger and seed data
        let ledger = Ledger(name: "我的账本", type: .personal)
        modelContext.insert(ledger)

        CategorySeeder.seed(modelContext: modelContext, ledger: ledger)

        // Seed default accounts
        let cash = Account(name: "现金", currencyCode: "CNY", type: .cash, iconName: "banknote", colorHex: "#4CAF50", sortOrder: 0)
        let debitCard = Account(name: "工资卡", currencyCode: "CNY", type: .debitCard, iconName: "creditcard.and.123", colorHex: "#2196F3", sortOrder: 1)
        let creditCard = Account(name: "信用卡", currencyCode: "CNY", type: .creditCard, iconName: "creditcard", colorHex: "#FF9800", creditLimit: 50000, sortOrder: 2)
        let eWallet = Account(name: "微信支付", currencyCode: "CNY", type: .eWallet, iconName: "wallet.pass", colorHex: "#4CAF50", sortOrder: 3)
        for a in [cash, debitCard, creditCard, eWallet] {
            a.ledger = ledger
            modelContext.insert(a)
        }

        // Seed default members
        let memberNames = ["自己", "配偶", "孩子"]
        for (i, name) in memberNames.enumerated() {
            let m = Member(name: name, avatar: ["person.circle", "heart.circle", "figure.child.circle"][i], sortOrder: i)
            m.ledger = ledger
            modelContext.insert(m)
        }

        // Seed default merchants
        let merchantNames = ["美团", "淘宝", "京东", "滴滴", "星巴克"]
        for (i, name) in merchantNames.enumerated() {
            let m = Merchant(name: name, sortOrder: i)
            m.ledger = ledger
            modelContext.insert(m)
        }

        // Seed default project
        let project = Project(name: "日常", desc: "日常收支", isActive: true, sortOrder: 0)
        project.ledger = ledger
        modelContext.insert(project)

        try? modelContext.save()
        currentLedger = ledger
    }
}

enum SyncStatus {
    case synced
    case syncing
    case offline
    case error(String)

    var displayName: String {
        switch self {
        case .synced: return NSLocalizedString("已同步", comment: "")
        case .syncing: return NSLocalizedString("同步中...", comment: "")
        case .offline: return NSLocalizedString("离线", comment: "")
        case .error(let msg): return msg
        }
    }
}
