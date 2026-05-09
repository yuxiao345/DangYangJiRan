import Foundation
import SwiftData

struct ReconciliationServiceImpl: ReconciliationServiceProtocol {

    func matchItems(_ bankItems: [BankTransactionItem], for account: Account, year: Int, month: Int, context: ModelContext) -> [ReconciliationMatch] {
        let calendar = Calendar.current
        let billingDay = account.billingDay ?? 1

        // Billing period boundaries ±3 day buffer
        var prevMonth = month - 1; var prevYear = year
        if prevMonth < 1 { prevMonth = 12; prevYear -= 1 }

        var startComps = DateComponents(year: prevYear, month: prevMonth, day: billingDay)
        startComps.hour = 0; startComps.minute = 0; startComps.second = 0
        guard let rawStart = calendar.date(from: startComps) else { return [] }
        let periodStart = calendar.date(byAdding: .day, value: -3, to: rawStart) ?? rawStart

        var endComps = DateComponents(year: year, month: month, day: billingDay)
        endComps.hour = 23; endComps.minute = 59; endComps.second = 59
        guard let rawEnd = calendar.date(from: endComps) else { return [] }
        let periodEnd = calendar.date(byAdding: .day, value: 3, to: rawEnd) ?? rawEnd

        // Fetch unreconciled expense transactions within period bounds
        let accountID = account.id
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.account?.id == accountID && $0.isReconciled == false }
        )
        let allTransactions = (try? context.fetch(descriptor)) ?? []
        let candidates = allTransactions.filter { t in
            t.date >= periodStart && t.date <= periodEnd && t.type == .expense
        }

        return bankItems.map { bankItem in
            let matches = findMatches(for: bankItem, candidates: candidates, calendar: calendar)

            let status: BankMatchStatus
            if matches.isEmpty {
                status = .unmatched
            } else if matches.count == 1 {
                status = .matched
            } else {
                status = .conflicted
            }

            return ReconciliationMatch(
                bankItem: bankItem,
                candidates: matches,
                status: status
            )
        }
    }

    // MARK: - Matching

    private struct ScoredMatch {
        let transaction: Transaction
        let score: Int
    }

    private func findMatches(for bankItem: BankTransactionItem, candidates: [Transaction], calendar: Calendar) -> [Transaction] {
        guard let bankDate = bankItem.transDate, let bankAmount = bankItem.amount else {
            return []
        }

        let scored = candidates.compactMap { t -> ScoredMatch? in
            guard let score = matchScore(bankDate: bankDate, bankAmount: bankAmount, transaction: t, calendar: calendar) else {
                return nil
            }
            return ScoredMatch(transaction: t, score: score)
        }
        .sorted { $0.score > $1.score }

        guard let bestScore = scored.first?.score, bestScore >= 2 else {
            return []
        }

        let bestMatches = scored.filter { $0.score == bestScore }

        // Tiebreaker: prefer match with description overlap
        if bestMatches.count > 1, let bankDesc = bankItem.desc {
            let keywords = bankDesc.components(separatedBy: CharacterSet(charactersIn: " ，（）()、。 "))
                .filter { $0.count >= 2 }
            if !keywords.isEmpty {
                let tiebroken = bestMatches.map { m -> (transaction: Transaction, tie: Int) in
                    let note = m.transaction.note ?? ""
                    let overlap = keywords.filter { note.contains($0) }.count
                    return (m.transaction, overlap)
                }
                .sorted { $0.tie > $1.tie }
                if let bestTie = tiebroken.first?.tie, bestTie > 0,
                   tiebroken.filter({ $0.tie == bestTie }).count == 1 {
                    return [tiebroken.first!.transaction]
                }
            }
        }

        return bestMatches.map { $0.transaction }
    }

    /// Returns a match score or nil (below threshold). Higher = better.
    private func matchScore(bankDate: Date, bankAmount: Decimal, transaction: Transaction, calendar: Calendar) -> Int? {
        // Compare by calendar day, not elapsed hours
        let bankDay = calendar.startOfDay(for: bankDate)
        let txnDay = calendar.startOfDay(for: transaction.date)
        let dayDiff = abs(calendar.dateComponents([.day], from: bankDay, to: txnDay).day ?? 99)
        guard dayDiff <= 2 else { return nil }

        // Amount match: exact=2, ±0.01=1
        let amountDiff = abs(bankAmount - transaction.amount)
        guard amountDiff <= 0.02 else { return nil }

        var score = 0
        if dayDiff == 0 { score += 2 }
        else if dayDiff == 1 { score += 1 }
        // dayDiff == 2 → +0

        if amountDiff == 0 { score += 2 }
        else if amountDiff <= 0.01 { score += 1 }
        // amountDiff > 0.01 → +0

        return score
    }

    // MARK: - Confirm

    func confirmReconciliation(
        matches: [ReconciliationMatch],
        account: Account,
        year: Int,
        month: Int,
        bankAmount: Decimal,
        ledger: Ledger,
        context: ModelContext
    ) throws -> CreditCardStatement {
        // Mark confirmed transactions as reconciled
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

        // Compute app amount from confirmed + newly created transactions
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

        // Upsert statement
        let accountID = account.id
        let stmtDescriptor = FetchDescriptor<CreditCardStatement>(
            predicate: #Predicate { $0.account?.id == accountID && $0.periodYear == year && $0.periodMonth == month }
        )
        let existing = try? context.fetch(stmtDescriptor)

        let stmt: CreditCardStatement
        if let existingStmt = existing?.first {
            existingStmt.statementAmount = bankAmount
            existingStmt.reconciledAppAmount = appTotal
            existingStmt.isReconciled = true
            existingStmt.reconciledAt = Date()
            stmt = existingStmt
        } else {
            stmt = CreditCardStatement(
                account: account,
                periodYear: year,
                periodMonth: month,
                statementAmount: bankAmount,
                reconciledAppAmount: appTotal
            )
            stmt.isReconciled = true
            stmt.reconciledAt = Date()
            stmt.ledger = ledger
            context.insert(stmt)
        }

        try context.save()
        return stmt
    }
}

