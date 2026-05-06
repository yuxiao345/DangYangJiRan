import Foundation
import SwiftData

struct AccountServiceImpl: AccountServiceProtocol {
    func createAccount(_ account: Account, ledger: Ledger, context: ModelContext) throws {
        account.ledger = ledger
        context.insert(account)
        try context.save()
    }

    func fetchAccounts(for ledger: Ledger, context: ModelContext) throws -> [Account] {
        let ledgerID = ledger.id
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.ledger?.id == ledgerID },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor)
    }

    func updateAccount(_ account: Account, context: ModelContext) throws {
        try context.save()
    }

    func deleteAccount(_ account: Account, context: ModelContext) throws {
        context.delete(account)
        try context.save()
    }

    func calculateBalance(for account: Account, context: ModelContext) -> Decimal {
        let accountID = account.id
        var balance = account.initialBalance

        let incomeDescriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate {
                ($0.account?.id == accountID || $0.toAccount?.id == accountID) &&
                $0.isReconciled == false
            }
        )
        let transactions = (try? context.fetch(incomeDescriptor)) ?? []

        for t in transactions {
            if t.type == .income {
                balance += t.amount
            } else if t.type == .expense {
                balance += t.amount
            } else if t.type == .transfer {
                if t.account?.id == accountID {
                    balance -= abs(t.amount)
                } else if t.toAccount?.id == accountID {
                    balance += abs(t.amount)
                }
            } else if t.type == .adjustment || t.type == .lending {
                balance += t.amount
            }
        }

        return balance
    }

    func archiveAccount(_ account: Account, context: ModelContext) throws {
        account.isArchived = true
        try context.save()
    }
}
