import SwiftUI
@preconcurrency import CoreData
import CloudKit

@MainActor
final class AppContainer: ObservableObject {
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

    var cloudKitContainer: CKContainer?

    // App state
    @Published var currentLedger: Ledger?
    @Published var syncStatus: SyncStatus = .synced
    @Published var isAuthenticated: Bool = false

    init() {
        // CoreDataStack
        let stack = CoreDataStack()
        self.coreDataStack = stack
        CoreDataStack.shared = stack

        cloudKitContainer = CKContainer(identifier: CloudKitConfig.containerIdentifier)

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
        bankOCRService = BankOCRServiceImpl()
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
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self?.refreshAndSwitchToSharedLedger()
            }
        }

        // Deduplicate ledgers after CloudKit import
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.deduplicateLedgers()
            }
        }
    }

    func loadStores() async throws {
        try await coreDataStack.loadStores()

        // Wait for CloudKit to import existing data before deciding
        // whether to create a default ledger. Without this, every
        // reinstall creates a duplicate "我的账本" because CloudKit
        // hasn't pulled the old one back yet.
        let context = viewContext
        let fetch = NSFetchRequest<Ledger>(entityName: "Ledger")
        for waitSec in [1, 2, 4] {
            if (try? context.count(for: fetch)) ?? 0 > 0 { break }
            try? await Task.sleep(nanoseconds: UInt64(waitSec) * 1_000_000_000)
        }

        configureDefaultLedger()
    }

    // MARK: - Share URL Handling

    func handleShareURL(_ url: URL) async {
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
        syncStatus = .error("接收开始")

        do {
            syncStatus = .error("正在接受共享邀请")
            try await syncService?.acceptShare(metadata: metadata)
            DiagnosticLog.log("handleAcceptedShareMetadata: accept OK, importing...")

            syncStatus = .error("共享邀请已接受，正在导入账本")
            let imported = try await syncService?.importSharedData(into: coreDataStack) ?? []
            syncStatus = .error("导入结果：\(imported.count) 个账本")

            if let first = imported.first {
                DiagnosticLog.log("import: switched to \(first.name)")
                currentLedger = first
                UserDefaults.standard.set(first.id.uuidString, forKey: "currentLedgerID")
                syncStatus = .error("已切换到共享账本：\(first.name)")

                try? await syncService?.syncParticipants(metadata: metadata, for: first)
                DiagnosticLog.log("import: participants synced")
                return
            }

            DiagnosticLog.log("import: 0 ledgers returned, falling back")
            syncStatus = .error("导入 0 个账本，正在刷新本地账本列表")
            await refreshAndSwitchToSharedLedger()
        } catch {
            DiagnosticLog.log("handleAcceptedShareMetadata: FAILED \(error.localizedDescription)")
            syncStatus = .error("共享失败：\(error.localizedDescription)")
        }
    }

    // MARK: - Ledger Management

    @MainActor
    private func refreshAndSwitchToSharedLedger() {
        let context = viewContext
        let fetch = NSFetchRequest<Ledger>(entityName: "Ledger")
        guard let ledgers = try? context.fetch(fetch) else {
            syncStatus = .error("刷新失败：无法读取本地账本")
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
            syncStatus = .error("刷新后切换到共享账本：\(shared.name)")
            return
        }

        if let anyNew = ledgers.first(where: { $0.id != currentLedger?.id }) {
            currentLedger = anyNew
            UserDefaults.standard.set(anyNew.id.uuidString, forKey: "currentLedgerID")
            syncStatus = .error("刷新后切换到新账本：\(anyNew.name)")
        } else {
            syncStatus = .error("刷新完成：未发现新的共享账本")
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

        // Seed default merchants
        let merchantNames = ["美团", "淘宝", "京东", "滴滴", "星巴克"]
        for (i, name) in merchantNames.enumerated() {
            let m = Merchant(name: name, sortOrder: i, context: context)
            m.ledger = ledger
        }

        // Seed default project
        let project = Project(name: "日常", desc: "日常收支", isActive: true, sortOrder: 0, context: context)
        project.ledger = ledger

        try? context.save()
        currentLedger = ledger
    }

    // MARK: - Deduplication

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
