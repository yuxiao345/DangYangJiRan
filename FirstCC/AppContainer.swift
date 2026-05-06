import SwiftUI
import SwiftData
import CloudKit

@MainActor
final class AppContainer: ObservableObject {
    let modelContainer: ModelContainer

    // Service instances (Phase 0: placeholders, Phase 1+: real implementations)
    private(set) var ledgerService: LedgerServiceProtocol?
    private(set) var accountService: AccountServiceProtocol?
    private(set) var transactionService: TransactionServiceProtocol?
    private(set) var categoryService: CategoryServiceProtocol?
    private(set) var templateService: TemplateServiceProtocol?
    private(set) var recurringService: RecurringServiceProtocol?
    private(set) var splitService: SplitServiceProtocol?
    private(set) var budgetService: BudgetServiceProtocol?
    private(set) var lendingService: LendingServiceProtocol?
    private(set) var installmentService: InstallmentServiceProtocol?
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
        let schema = Schema([
            Ledger.self, User.self, Account.self, Category.self,
            Transaction.self, TransactionTemplate.self, RecurringRule.self,
            SplitGroup.self, SplitEntry.self, Budget.self,
            Lending.self, LendingRepayment.self, InstallmentPlan.self,
            ExchangeRate.self
        ])

        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        do {
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        // Phase 3: cloudKitContainer = CKContainer(identifier: CloudKitConfig.containerIdentifier)
        cloudKitContainer = nil
    }

    func handleShareURL(_ url: URL) async {
        // CKShare metadata extraction (Phase 3)
        Logger.info("Received share URL: \(url)")
    }

    func configureDefaultLedger(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Ledger>()
        guard (try? modelContext.fetch(descriptor))?.isEmpty ?? true else { return }

        let ledger = Ledger(name: "我的账本", type: .personal)
        modelContext.insert(ledger)

        CategorySeeder.seed(modelContext: modelContext, ledger: ledger)

        try? modelContext.save()
        currentLedger = ledger
    }
}

enum SyncStatus {
    case synced
    case syncing
    case offline
    case error(String)
}
