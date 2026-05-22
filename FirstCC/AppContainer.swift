import SwiftUI
import SwiftData
import CloudKit

@MainActor
final class AppContainer: ObservableObject {
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
            syncService = SyncServiceImpl(container: ckContainer)
        }
    }

    func handleShareURL(_ url: URL) async {
        // CKShare metadata extraction (Phase 3)
        Logger.info("Received share URL: \(url)")
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
