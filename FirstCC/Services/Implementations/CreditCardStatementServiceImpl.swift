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
        context.delete(statement)
        try context.save()
    }

    func calculateAppAmount(for account: Account, year: Int, month: Int, context: ModelContext) -> Decimal {
        let calendar = Calendar.current
        let billingDay = account.billingDay ?? 1

        // Period: (billingDay of previous month) ... (billingDay of current month)
        // e.g. billingDay=15, month=5: April 16 ... May 15
        var prevMonth = month - 1
        var prevYear = year
        if prevMonth < 1 {
            prevMonth = 12
            prevYear -= 1
        }

        var startComps = DateComponents(year: prevYear, month: prevMonth, day: billingDay)
        startComps.hour = 0
        startComps.minute = 0
        startComps.second = 0
        guard let startDate = calendar.date(from: startComps) else { return 0 }

        var endComps = DateComponents(year: year, month: month, day: billingDay)
        endComps.hour = 23
        endComps.minute = 59
        endComps.second = 59
        guard let endDate = calendar.date(from: endComps) else { return 0 }

        let accountID = account.id
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.account?.id == accountID && $0.isReconciled == false }
        )
        let allTransactions = (try? context.fetch(descriptor)) ?? []

        let periodTransactions = allTransactions.filter { t in
            t.date >= startDate && t.date <= endDate && t.type == .expense
        }

        return periodTransactions.reduce(Decimal.zero) { $0 + $1.amount }
    }
}
