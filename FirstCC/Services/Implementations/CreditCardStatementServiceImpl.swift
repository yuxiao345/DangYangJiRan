import Foundation
@preconcurrency import CoreData

struct CreditCardStatementServiceImpl: CreditCardStatementServiceProtocol {
    func createStatement(_ statement: CreditCardStatement, ledger: Ledger, context: NSManagedObjectContext) throws {
        statement.ledger = ledger
        try context.save()
    }

    func fetchStatements(for account: Account, context: NSManagedObjectContext) throws -> [CreditCardStatement] {
        let accountID = account.id
        let request = NSFetchRequest<CreditCardStatement>(entityName: "CreditCardStatement")
        request.predicate = NSPredicate(format: "account.id == %@", accountID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "periodYear", ascending: false), NSSortDescriptor(key: "periodMonth", ascending: false)]
        return try context.fetch(request)
    }

    func updateStatement(_ statement: CreditCardStatement, context: NSManagedObjectContext) throws {
        try context.save()
    }

    func deleteStatement(_ statement: CreditCardStatement, context: NSManagedObjectContext) throws {
        if let account = statement.account,
           let period = CreditCardStatementPeriod(
                billingDay: account.billingDay == 0 ? 1 : Int(account.billingDay),
                year: Int(statement.periodYear),
                month: Int(statement.periodMonth)
           ) {
            let accountID = account.id
            let request = NSFetchRequest<Transaction>(entityName: "Transaction")
            request.predicate = NSPredicate(format: "account.id == %@ AND isReconciled == YES", accountID as CVarArg)
            let allReconciled = (try? context.fetch(request)) ?? []
            let reconciled = allReconciled.filter { period.contains($0.date) }
            for txn in reconciled {
                txn.isReconciled = false
            }
        }

        context.delete(statement)
        try context.save()
    }

    func calculateAppAmount(for account: Account, year: Int, month: Int, context: NSManagedObjectContext) -> Decimal {
        guard let period = CreditCardStatementPeriod(
            billingDay: account.billingDay == 0 ? 1 : Int(account.billingDay),
            year: year,
            month: month
        ) else {
            return 0
        }

        let accountID = account.id
        let request = NSFetchRequest<Transaction>(entityName: "Transaction")
        request.predicate = NSPredicate(format: "account.id == %@ AND isReconciled == NO AND parentTransaction == nil", accountID as CVarArg)
        let allTxns = (try? context.fetch(request)) ?? []

        return allTxns
            .filter { $0.type == .expense && period.contains($0.date) }
            .reduce(Decimal.zero) { $0 + $1.ledgerAmount }
    }
}
