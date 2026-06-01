import Foundation
@preconcurrency import CoreData

struct AccountServiceImpl: AccountServiceProtocol {
    func createAccount(_ account: Account, ledger: Ledger, context: NSManagedObjectContext) throws {
        account.ledger = ledger
        try context.save()
    }

    func fetchAccounts(for ledger: Ledger, context: NSManagedObjectContext) throws -> [Account] {
        let ledgerID = ledger.id
        let request = NSFetchRequest<Account>(entityName: "Account")
        request.predicate = NSPredicate(format: "ledger.id == %@", ledgerID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true), NSSortDescriptor(key: "createdAt", ascending: true)]
        return try context.fetch(request)
    }

    func updateAccount(_ account: Account, context: NSManagedObjectContext) throws {
        try context.save()
    }

    func deleteAccount(_ account: Account, context: NSManagedObjectContext) throws {
        context.delete(account)
        try context.save()
    }

    func calculateBalance(for account: Account, context: NSManagedObjectContext) -> Decimal {
        let accountID = account.id
        var balance = account.initialBalance

        let request = NSFetchRequest<Transaction>(entityName: "Transaction")
        request.predicate = NSPredicate(format: "account.id == %@ AND isReconciled == NO AND parentTransaction == nil", accountID as CVarArg)
        let transactions = (try? context.fetch(request)) ?? []

        for t in transactions {
            balance += t.amount
        }

        return balance
    }

    func archiveAccount(_ account: Account, context: NSManagedObjectContext) throws {
        account.isArchived = true
        try context.save()
    }
}
