import Foundation
import SwiftData

struct TransactionServiceImpl: TransactionServiceProtocol {
    func createTransaction(_ transaction: Transaction, ledger: Ledger, context: ModelContext) throws {
        transaction.ledger = ledger
        context.insert(transaction)
        try context.save()
        NotificationCenter.default.post(name: .transactionDidChange, object: nil)
    }

    func createTransfer(
        from sourceAccount: Account,
        to destAccount: Account,
        amount: Decimal,
        date: Date,
        note: String?,
        ledger: Ledger,
        context: ModelContext
    ) throws -> (Transaction, Transaction) {
        let groupID = UUID()
        let absAmount = abs(amount)

        let outflow = Transaction(
            type: .transfer,
            amount: -absAmount,
            note: note,
            date: date,
            transferGroupId: groupID,
            account: sourceAccount,
            toAccount: destAccount
        )
        outflow.ledger = ledger
        context.insert(outflow)

        let inflow = Transaction(
            type: .transfer,
            amount: absAmount,
            note: note,
            date: date,
            transferGroupId: groupID,
            account: destAccount,
            toAccount: sourceAccount
        )
        inflow.ledger = ledger
        context.insert(inflow)

        try context.save()
        NotificationCenter.default.post(name: .transactionDidChange, object: nil)
        return (outflow, inflow)
    }

    func createRefund(
        for original: Transaction,
        amount: Decimal,
        context: ModelContext
    ) throws -> Transaction {
        let absAmount = abs(amount)
        let signedAmount: Decimal = original.type == .expense ? absAmount : -absAmount
        let refund = Transaction(
            type: original.type,
            amount: signedAmount,
            currencyCode: original.currencyCode,
            note: "退款: \(original.note ?? "")",
            date: Date(),
            refundGroupId: original.id,
            refundAmount: amount,
            account: original.account,
            category: original.category
        )
        refund.ledger = original.ledger
        context.insert(refund)
        try context.save()
        NotificationCenter.default.post(name: .transactionDidChange, object: nil)
        return refund
    }

    func fetchTransactions(
        for ledger: Ledger,
        context: ModelContext,
        filters: TransactionFilters? = nil
    ) throws -> [Transaction] {
        let ledgerID = ledger.id
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.ledger?.id == ledgerID && $0.parentTransaction == nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let all = try context.fetch(descriptor)

        guard let filters = filters else { return all }

        return all.filter { t in
            if let range = filters.dateRange {
                guard range.contains(t.date) else { return false }
            }
            if let type = filters.type, t.type != type {
                return false
            }
            if let amountRange = filters.amountRange {
                guard amountRange.contains(abs(t.amount)) else { return false }
            }
            if let keyword = filters.keyword, !keyword.isEmpty {
                let tokens = keyword.lowercased().split(separator: " ").map(String.init)
                guard !tokens.isEmpty else { return true }
                let lcNote = t.note?.lowercased()
                let lcTags = t.tags.map { $0.lowercased() }
                let match = tokens.allSatisfy { token in
                    if lcNote?.contains(token) == true { return true }
                    if lcTags.contains(where: { $0.contains(token) }) { return true }
                    if let name = t.merchant?.name, name.lowercased().contains(token) { return true }
                    if let name = t.category?.name, name.lowercased().contains(token) { return true }
                    if let name = t.account?.name, name.lowercased().contains(token) { return true }
                    if let name = t.member?.name, name.lowercased().contains(token) { return true }
                    if let name = t.project?.name, name.lowercased().contains(token) { return true }
                    return false
                }
                guard match else { return false }
            }
            return true
        }
    }

    func updateTransaction(_ transaction: Transaction, context: ModelContext) throws {
        transaction.modifiedAt = Date()
        try context.save()
        NotificationCenter.default.post(name: .transactionDidChange, object: nil)
    }

    func deleteTransaction(_ transaction: Transaction, context: ModelContext) throws {
        context.delete(transaction)
        try context.save()
        NotificationCenter.default.post(name: .transactionDidChange, object: nil)
    }
}
