import Foundation
@preconcurrency import CoreData

struct TransactionServiceImpl: TransactionServiceProtocol {
    func createTransaction(_ transaction: Transaction, ledger: Ledger, context: NSManagedObjectContext) throws {
        transaction.ledger = ledger
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
        context: NSManagedObjectContext
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
            toAccount: destAccount,
            context: context
        )
        outflow.ledger = ledger

        let inflow = Transaction(
            type: .transfer,
            amount: absAmount,
            note: note,
            date: date,
            transferGroupId: groupID,
            account: destAccount,
            toAccount: sourceAccount,
            context: context
        )
        inflow.ledger = ledger

        try context.save()
        NotificationCenter.default.post(name: .transactionDidChange, object: nil)
        return (outflow, inflow)
    }

    func createRefund(
        for original: Transaction,
        amount: Decimal,
        context: NSManagedObjectContext
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
            category: original.category,
            context: context
        )
        refund.ledger = original.ledger
        try context.save()
        NotificationCenter.default.post(name: .transactionDidChange, object: nil)
        return refund
    }

    func fetchTransactions(
        for ledger: Ledger,
        context: NSManagedObjectContext,
        filters: TransactionFilters? = nil
    ) throws -> [Transaction] {
        let ledgerID = ledger.id
        let request = NSFetchRequest<Transaction>(entityName: "Transaction")

        // 将日期/类型过滤推到 SQLite 层，减少内存加载
        var preds: [NSPredicate] = [
            NSPredicate(format: "ledger.id == %@ AND parentTransaction == nil", ledgerID as CVarArg)
        ]
        if let range = filters?.dateRange {
            preds.append(NSPredicate(format: "date >= %@ AND date < %@", range.lowerBound as NSDate, range.upperBound as NSDate))
        }
        if let type = filters?.type {
            preds.append(NSPredicate(format: "typeRaw == %@", type.rawValue))
        }
        if let ids = filters?.categoryIDs, !ids.isEmpty {
            preds.append(NSPredicate(format: "category.id IN %@", Array(ids) as NSArray))
        }
        if let ids = filters?.memberIDs, !ids.isEmpty {
            preds.append(NSPredicate(format: "member.id IN %@", Array(ids) as NSArray))
        }
        if let ids = filters?.projectIDs, !ids.isEmpty {
            preds.append(NSPredicate(format: "project.id IN %@", Array(ids) as NSArray))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: preds)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        let results = try context.fetch(request)

        guard let filters = filters else { return results }

        // 金额范围 + 关键字过滤仍在内存中进行（多字段 OR 查询在 CoreData 层效率不高）
        return results.filter { t in
            if let amountRange = filters.amountRange {
                guard amountRange.contains(abs(t.amount)) else { return false }
            }
            if let keyword = filters.keyword, !keyword.isEmpty {
                let tokens = keyword.lowercased().split(separator: " ").map(String.init)
                guard !tokens.isEmpty else { return true }
                let lcNote = t.note?.lowercased()
                let lcTags = t.tags.map { $0.lowercased() }
                guard tokens.allSatisfy({ token in
                    if lcNote?.contains(token) == true { return true }
                    if lcTags.contains(where: { $0.contains(token) }) { return true }
                    if let name = t.merchant?.name, name.lowercased().contains(token) { return true }
                    if let name = t.category?.name, name.lowercased().contains(token) { return true }
                    if let name = t.account?.name, name.lowercased().contains(token) { return true }
                    if let name = t.toAccount?.name, name.lowercased().contains(token) { return true }
                    if let name = t.member?.name, name.lowercased().contains(token) { return true }
                    if let name = t.project?.name, name.lowercased().contains(token) { return true }
                    // Amount: match formatted absolute value (e.g. "6199" in "￥6,199.00")
                    if String(format: "%.0f", Double(truncating: abs(t.amount) as NSNumber)).contains(token) { return true }
                    if String(format: "%.2f", Double(truncating: abs(t.amount) as NSNumber)).contains(token) { return true }
                    // Split entries: member name
                    if let entries = t.splitGroup?.entries {
                        for entry in entries {
                            if let mn = entry.member?.name, mn.lowercased().contains(token) { return true }
                        }
                    }
                    // Split children: their own notes/categories/members/projects/accounts
                    if let children = t.splitChildren {
                        for child in children {
                            if let cn = child.note, cn.lowercased().contains(token) { return true }
                            if let ccat = child.category?.name, ccat.lowercased().contains(token) { return true }
                            if let cmem = child.member?.name, cmem.lowercased().contains(token) { return true }
                            if let cproj = child.project?.name, cproj.lowercased().contains(token) { return true }
                            if let cacc = child.account?.name, cacc.lowercased().contains(token) { return true }
                        }
                    }
                    return false
                }) else { return false }
            }
            return true
        }
    }

    func updateTransaction(_ transaction: Transaction, context: NSManagedObjectContext) throws {
        transaction.modifiedAt = Date()
        try context.save()
        NotificationCenter.default.post(name: .transactionDidChange, object: nil)
    }

    func deleteTransaction(_ transaction: Transaction, context: NSManagedObjectContext) throws {
        // For transfers, delete the paired record (same transferGroupId) so no orphan remains
        if transaction.type == .transfer, let gid = transaction.transferGroupId {
            let req = NSFetchRequest<Transaction>(entityName: "Transaction")
            req.predicate = NSPredicate(format: "transferGroupId == %@ AND id != %@", gid as CVarArg, transaction.id as CVarArg)
            if let counterpart = (try? context.fetch(req))?.first {
                context.delete(counterpart)
            }
        }

        // 借贷关联清理
        if transaction.type == .lending {
            if transaction.lendingDirection == .collect || transaction.lendingDirection == .repay {
                // 删除收款/还款时，重置被结算的原始借贷为待结算
                let req = NSFetchRequest<Transaction>(entityName: "Transaction")
                req.predicate = NSPredicate(format: "settledByLendingTransactionId == %@", transaction.id as CVarArg)
                if let settled = try? context.fetch(req) {
                    for item in settled {
                        item.settledByLendingTransactionId = nil
                        item.settledAmount = nil
                        item.lendingStatus = .pending
                    }
                }
            }
            // 删除借出/借入时，settledByLendingTransactionId 指向的收款交易不受影响
            // （收款交易没有反向引用，直接删除即可）
        }

        context.delete(transaction)
        try context.save()
        NotificationCenter.default.post(name: .transactionDidChange, object: nil)
    }
}
