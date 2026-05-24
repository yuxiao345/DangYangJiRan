import Foundation
@preconcurrency import CoreData

@MainActor
final class AccountListViewModel: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var totalBalance: Decimal = 0
    @Published var selectedType: AccountType?

    private let service: AccountServiceProtocol
    private let ledger: Ledger

    init(ledger: Ledger, service: AccountServiceProtocol) {
        self.ledger = ledger
        self.service = service
    }

    func load(context: NSManagedObjectContext) {
        let allAccounts = (try? service.fetchAccounts(for: ledger, context: context)) ?? []
        accounts = allAccounts.filter { !$0.isArchived }
        totalBalance = accounts.reduce(0) { $0 + service.calculateBalance(for: $1, context: context) }
    }

    func accountsForType(_ type: AccountType) -> [Account] {
        accounts.filter { $0.type == type }
    }

    func deleteAccount(_ account: Account, context: NSManagedObjectContext) {
        try? service.archiveAccount(account, context: context)
    }
}
