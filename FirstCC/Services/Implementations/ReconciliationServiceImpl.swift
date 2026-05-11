import Foundation
import SwiftData

struct ReconciliationServiceImpl: ReconciliationServiceProtocol {

    func matchItems(_ bankItems: [BankTransactionItem], for account: Account, year: Int, month: Int, context: ModelContext) -> [ReconciliationMatch] {
        let calendar = Calendar.current
        guard let period = CreditCardStatementPeriod(
            billingDay: account.billingDay ?? 1,
            year: year,
            month: month
        ) else {
            return []
        }

        let accountID = account.id
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate {
                $0.account?.id == accountID &&
                $0.isReconciled == false
            }
        )
        let allTxns = (try? context.fetch(descriptor)) ?? []
        let candidates = allTxns.filter { $0.type == .expense && period.contains($0.date) }

        var usedIDs = Set<UUID>()
        var results: [ReconciliationMatch] = []

        // Sort bank items by date so earlier items get first pick
        var remaining = bankItems.sorted { ($0.transDate ?? .distantPast) < ($1.transDate ?? .distantPast) }

        // Pass 1: exact date + exact amount (diff ≤ 0.01)
        var passResults: [ReconciliationMatch] = []
        (remaining, passResults) = greedyPass(items: remaining, candidates: candidates, usedIDs: &usedIDs, calendar: calendar, status: .matched) { bankDate, bankAmount, txn, cal in
            guard cal.isDate(bankDate, inSameDayAs: txn.date) else { return false }
            return abs(bankAmount - txn.amount) <= 0.01
        }
        results.append(contentsOf: passResults)

        // Pass 2: date ±1-2 days + exact amount → suspected date mismatch
        (remaining, passResults) = greedyPass(items: remaining, candidates: candidates, usedIDs: &usedIDs, calendar: calendar, status: .suspectedDateMismatch) { bankDate, bankAmount, txn, cal in
            let dayDiff = abs(cal.dateComponents([.day], from: cal.startOfDay(for: bankDate), to: cal.startOfDay(for: txn.date)).day ?? 99)
            guard (1...2).contains(dayDiff) else { return false }
            return abs(bankAmount - txn.amount) <= 0.01
        }
        results.append(contentsOf: passResults)

        // Pass 3: exact date + amount within 2% or ¥2 tolerance → suspected amount mismatch
        (remaining, passResults) = greedyPass(items: remaining, candidates: candidates, usedIDs: &usedIDs, calendar: calendar, status: .suspectedAmountMismatch) { bankDate, bankAmount, txn, cal in
            guard cal.isDate(bankDate, inSameDayAs: txn.date) else { return false }
            let tolerance = max(abs(bankAmount) * 0.02, Decimal(2))
            let diff = abs(bankAmount - txn.amount)
            return diff > 0.01 && diff <= tolerance
        }
        results.append(contentsOf: passResults)

        // Remaining bank items → unmatched
        for item in remaining {
            results.append(ReconciliationMatch(bankItem: item, candidates: [], status: .unmatched))
        }

        return results
    }

    // MARK: - Greedy one-to-one pass

    private func greedyPass(
        items: [BankTransactionItem],
        candidates: [Transaction],
        usedIDs: inout Set<UUID>,
        calendar: Calendar,
        status: BankMatchStatus,
        filter: (Date, Decimal, Transaction, Calendar) -> Bool
    ) -> (remaining: [BankTransactionItem], matches: [ReconciliationMatch]) {
        var remaining: [BankTransactionItem] = []
        var matches: [ReconciliationMatch] = []

        for item in items {
            guard let bankDate = item.transDate, let bankAmount = item.amount else {
                remaining.append(item)
                continue
            }

            let available = candidates.filter { !usedIDs.contains($0.id) }
            let matching = available.filter { filter(bankDate, bankAmount, $0, calendar) }

            if let best = matching.min(by: { abs(bankAmount - $0.amount) < abs(bankAmount - $1.amount) }) {
                usedIDs.insert(best.id)
                matches.append(ReconciliationMatch(bankItem: item, candidates: [best], status: status))
            } else {
                remaining.append(item)
            }
        }

        return (remaining, matches)
    }

    func confirmReconciliation(
        matches: [ReconciliationMatch],
        account: Account,
        year: Int,
        month: Int,
        bankAmount: Decimal,
        ledger: Ledger,
        context: ModelContext
    ) throws -> CreditCardStatement {
        for match in matches {
            switch match.userAction {
            case .confirmed(let txn):
                txn.isReconciled = true
            case .createNew:
                let item = match.bankItem
                if let date = item.transDate, let amount = item.amount {
                    let txn = Transaction(
                        type: .expense,
                        amount: amount,
                        currencyCode: account.currencyCode,
                        note: item.desc,
                        date: date,
                        isReconciled: true
                    )
                    txn.account = account
                    txn.ledger = ledger
                    context.insert(txn)
                }
            case .pending, .ignored:
                break
            }
        }

        var appTotal: Decimal = 0
        for match in matches {
            switch match.userAction {
            case .confirmed(let txn):
                appTotal += txn.amount
            case .createNew:
                if let amount = match.bankItem.amount {
                    appTotal += amount
                }
            case .pending, .ignored:
                break
            }
        }

        let accountID = account.id
        let stmtDescriptor = FetchDescriptor<CreditCardStatement>(
            predicate: #Predicate { $0.account?.id == accountID && $0.periodYear == year && $0.periodMonth == month }
        )
        let existing = try? context.fetch(stmtDescriptor)

        let statement: CreditCardStatement
        if let existingStmt = existing?.first {
            existingStmt.statementAmount = bankAmount
            existingStmt.reconciledAppAmount = appTotal
            existingStmt.isReconciled = true
            existingStmt.reconciledAt = Date()
            statement = existingStmt
        } else {
            statement = CreditCardStatement(
                account: account,
                periodYear: year,
                periodMonth: month,
                statementAmount: bankAmount,
                reconciledAppAmount: appTotal
            )
            statement.isReconciled = true
            statement.reconciledAt = Date()
            statement.ledger = ledger
            context.insert(statement)
        }

        try context.save()
        return statement
    }
}
