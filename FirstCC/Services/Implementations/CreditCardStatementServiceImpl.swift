import Foundation
import SwiftData

struct CreditCardStatementServiceImpl: CreditCardStatementServiceProtocol {
    func createStatement(_ statement: CreditCardStatement, ledger: Ledger, context: ModelContext) throws {
        statement.ledger = ledger
        context.insert(statement)
        try context.save()
    }

    func fetchStatements(for account: Account, context: ModelContext) throws -> [CreditCardStatement] {
        let accountID = account.id
        let descriptor = FetchDescriptor<CreditCardStatement>(
            predicate: #Predicate { $0.account?.id == accountID },
            sortBy: [SortDescriptor(\.periodYear, order: .reverse), SortDescriptor(\.periodMonth, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func updateStatement(_ statement: CreditCardStatement, context: ModelContext) throws {
        try context.save()
    }

    func deleteStatement(_ statement: CreditCardStatement, context: ModelContext) throws {
        if let account = statement.account,
           let period = CreditCardStatementPeriod(
                billingDay: account.billingDay ?? 1,
                year: statement.periodYear,
                month: statement.periodMonth
           ) {
            let accountID = account.id
            let descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate {
                    $0.account?.id == accountID &&
                    $0.isReconciled == true
                }
            )
            let allReconciled = (try? context.fetch(descriptor)) ?? []
            let reconciled = allReconciled.filter { period.contains($0.date) }
            for txn in reconciled {
                txn.isReconciled = false
            }
        }

        context.delete(statement)
        try context.save()
    }

    func calculateAppAmount(for account: Account, year: Int, month: Int, context: ModelContext) -> Decimal {
        guard let period = CreditCardStatementPeriod(
            billingDay: account.billingDay ?? 1,
            year: year,
            month: month
        ) else {
            return 0
        }

        let accountID = account.id
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate {
                $0.account?.id == accountID &&
                $0.isReconciled == false
            }
        )
        let allTxns = (try? context.fetch(descriptor)) ?? []

        return allTxns
            .filter { $0.type == .expense && period.contains($0.date) }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }
}
