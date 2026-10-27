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
        balance(for: account, before: .distantFuture, context: context)
    }

    /// 截至 `cutoff`（不含）的余额，只统计 `date < cutoff` 的交易，其余规则与当前余额完全一致。
    ///
    /// 总览用它反推月初净资产。**不要**改成「当前余额 − 当月交易金额之和」：借贷交易只有现金侧
    /// 一条 `amount`，另一侧应收/应付是在这里按 `toAccount` 补的，直接求和会把借出/借入误算成
    /// 净资产减少（2026-10 实测「较上月」把 +16,274 显示成 −13,970）。
    ///
    /// 已知边界：`lendingStatus` / `settledAmount` 是可变状态、没有历史日期，所以「本月刚结清
    /// 上月借出」时，上月那条应收在回溯视角里会凭空消失。这是既有口径，未在本次修复范围内。
    func calculateBalance(for account: Account, before cutoff: Date, context: NSManagedObjectContext) -> Decimal {
        balance(for: account, before: cutoff, context: context)
    }

    private func balance(for account: Account, before cutoff: Date, context: NSManagedObjectContext) -> Decimal {
        let accountID = account.id
        var balance = account.initialBalance

        // 若账户币种与账本基准币种不一致，使用交易原始币种保持一致性
        let acctCurrency = account.effectiveCurrencyCode
        let ledgerCurrency = account.ledger?.defaultCurrencyCode ?? "CNY"
        let useLedgerAmount = acctCurrency == ledgerCurrency

        // 当前余额即「截止到无限远」，两轮查询共用同一条日期上界。
        // `date == nil` 必须显式放行：模型里 date 是 optional，`NULL < X` 恒为假，
        // 只写字面比较会让无日期记录从所有账户余额里静默消失（旧实现无日期条件）。
        // 这类记录在「当前」和「月初」两侧都会被计入，做差时自然抵消。
        let cutoffPredicate = NSPredicate(format: "date == nil OR date < %@", cutoff as NSDate)

        let request = NSFetchRequest<Transaction>(entityName: "Transaction")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "account.id == %@ AND isReconciled == NO AND parentTransaction == nil", accountID as CVarArg),
            cutoffPredicate,
        ])
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
        toRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "toAccount.id == %@ AND typeRaw == %@ AND isReconciled == NO AND parentTransaction == nil",
                        accountID as CVarArg, TransactionType.lending.rawValue),
            cutoffPredicate,
        ])
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
