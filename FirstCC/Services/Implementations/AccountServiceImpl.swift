import Foundation
@preconcurrency import CoreData

struct AccountServiceImpl: AccountServiceProtocol {
    func createAccount(_ account: Account, ledger: Ledger, context: NSManagedObjectContext) throws {
        account.ledger = ledger
        try context.save()
    }

    func findByName(_ name: String, ledger: Ledger, context: NSManagedObjectContext) throws -> Account? {
        let request = NSFetchRequest<Account>(entityName: "Account")
        request.predicate = NSPredicate(format: "ledger.id == %@ AND name == %@", ledger.id as CVarArg, name)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    func fetchAccounts(for ledger: Ledger, includeArchived: Bool = false, context: NSManagedObjectContext) throws -> [Account] {
        let ledgerID = ledger.id
        let request = NSFetchRequest<Account>(entityName: "Account")
        var fmt = "ledger.id == %@"
        if !includeArchived { fmt += " AND isArchived == NO" }
        request.predicate = NSPredicate(format: fmt, ledgerID as CVarArg)
        return try context.fetch(request).sorted { a, b in
            if a.type.sortPriority != b.type.sortPriority { return a.type.sortPriority < b.type.sortPriority }
            if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
            return (a.createdAt ?? Date.distantPast) < (b.createdAt ?? Date.distantPast)
        }
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
            // 借贷账户上的待结算借入=债务，反转符号（借入+1000 → 余额-1000）
            if account.type == .lending,
               let dir = t.lendingDirection,
               dir == .borrowIn,
               t.lendingStatus == .pending {
                balance += -t.amount
            } else {
                balance += t.amount
            }
        }

        // 借贷账户：借出/还款时 account 是别的账户，toAccount 才是本账户。
        // 待结算的借出/借入=应收/应付（反转符号），还款=钱流出（不反转）。
        if account.type == .lending {
            let toRequest = NSFetchRequest<Transaction>(entityName: "Transaction")
            toRequest.predicate = NSPredicate(format: "toAccount.id == %@ AND typeRaw == %@ AND isReconciled == NO AND parentTransaction == nil",
                                              accountID as CVarArg, TransactionType.lending.rawValue)
            let toTransactions = (try? context.fetch(toRequest)) ?? []
            for t in toTransactions {
                if let dir = t.lendingDirection {
                    switch dir {
                    case .lendOut:
                        if t.lendingStatus == .pending { balance += -t.amount }
                    case .repay:
                        balance += t.amount
                    case .borrowIn, .collect:
                        break
                    }
                }
            }
        }

        return balance
    }

    func archiveAccount(_ account: Account, context: NSManagedObjectContext) throws {
        account.isArchived = true
        try context.save()
    }
}
