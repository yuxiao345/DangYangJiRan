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

        // 若账户币种与账本基准币种不一致，使用交易原始币种保持一致性
        let acctCurrency = account.effectiveCurrencyCode
        let ledgerCurrency = account.ledger?.defaultCurrencyCode ?? "CNY"
        let useLedgerAmount = acctCurrency == ledgerCurrency

        let request = NSFetchRequest<Transaction>(entityName: "Transaction")
        request.predicate = NSPredicate(format: "account.id == %@ AND isReconciled == NO AND parentTransaction == nil", accountID as CVarArg)
        let transactions = (try? context.fetch(request)) ?? []

        for t in transactions {
            let amt = useLedgerAmount ? t.ledgerAmount : t.amount
            // 借贷账户：借入待结算=应付（反转符号，扣除已还部分）；收款/还款已在第二轮跳过避免重复计算
            if account.type == .lending,
               let dir = t.lendingDirection {
                if dir == .borrowIn, t.lendingStatus == .pending {
                    let settledAmt = useLedgerAmount ? t.settledAmountInLedgerCurrency : (t.settledAmount ?? 0)
                    balance += -(amt - min(settledAmt, abs(amt)))
                }
                // collect/repay/lendOut: 第一轮跳过，由第二轮处理
            } else {
                balance += amt
            }
        }

        // 第二轮：toAccount = 本账户的借贷交易
        // - 借贷账户：借出待结算=应收（反转符号，扣除已结算部分）
        // - 非借贷账户：收款/借入=钱到账
        let toRequest = NSFetchRequest<Transaction>(entityName: "Transaction")
        toRequest.predicate = NSPredicate(format: "toAccount.id == %@ AND typeRaw == %@ AND isReconciled == NO AND parentTransaction == nil",
                                          accountID as CVarArg, TransactionType.lending.rawValue)
        let toTransactions = (try? context.fetch(toRequest)) ?? []
        for t in toTransactions {
            let amt = useLedgerAmount ? t.ledgerAmount : t.amount
            if let dir = t.lendingDirection {
                if account.type == .lending {
                    switch dir {
                    case .lendOut:
                        if t.lendingStatus == .pending {
                            let settledAmt = useLedgerAmount ? t.settledAmountInLedgerCurrency : (t.settledAmount ?? 0)
                            balance += -(amt + min(settledAmt, abs(amt)))
                        }
                    case .borrowIn, .collect, .repay:
                        break
                    }
                } else {
                    // 非借贷账户：collect/borrowIn = 钱从借贷账户转入本账户
                    if dir == .collect || dir == .borrowIn { balance += amt }
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
