import Foundation
@preconcurrency import CoreData

final class BudgetServiceImpl: BudgetServiceProtocol {

    // MARK: - BudgetBook

    func createBook(_ book: BudgetBook, ledger: Ledger, context: NSManagedObjectContext) throws {
        book.ledger = ledger
        try context.save()
    }

    func findBookByName(_ name: String, ledger: Ledger, context: NSManagedObjectContext) throws -> BudgetBook? {
        let request = NSFetchRequest<BudgetBook>(entityName: "BudgetBook")
        request.predicate = NSPredicate(format: "ledger.id == %@ AND name == %@", ledger.id as CVarArg, name)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    func fetchBooks(for ledger: Ledger, context: NSManagedObjectContext) throws -> [BudgetBook] {
        let lid = ledger.id
        let request = NSFetchRequest<BudgetBook>(entityName: "BudgetBook")
        request.predicate = NSPredicate(format: "ledger.id == %@", lid as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        return try context.fetch(request)
    }

    func updateBook(_ book: BudgetBook, context: NSManagedObjectContext) throws {
        try context.save()
    }

    func deleteBook(_ book: BudgetBook, context: NSManagedObjectContext) throws {
        context.delete(book)
        try context.save()
    }

    func reorderBooks(_ books: [BudgetBook], context: NSManagedObjectContext) throws {
        for (i, book) in books.enumerated() {
            book.sortOrder = Int64(i)
        }
        try context.save()
    }

    // MARK: - BudgetItem

    func createItem(_ item: BudgetItem, book: BudgetBook, ledger: Ledger, context: NSManagedObjectContext) throws {
        item.book = book
        try context.save()
    }

    func fetchItems(for book: BudgetBook, context: NSManagedObjectContext) throws -> [BudgetItem] {
        let bid = book.id
        let request = NSFetchRequest<BudgetItem>(entityName: "BudgetItem")
        request.predicate = NSPredicate(format: "book.id == %@", bid as CVarArg)
        return try context.fetch(request)
    }

    func updateItem(_ item: BudgetItem, context: NSManagedObjectContext) throws {
        try context.save()
    }

    func deleteItem(_ item: BudgetItem, context: NSManagedObjectContext) throws {
        context.delete(item)
        try context.save()
    }

    // MARK: - Calculations

    func currentPeriodSpending(for item: BudgetItem, context: NSManagedObjectContext) -> Decimal {
        guard let book = item.book else { return 0 }
        let now = Date()
        let range = clippedRange(currentPeriodRange(for: item, now: now), to: book)
        return spending(in: range, category: item.category, book: book, context: context)
    }

    func cumulativeSpending(for item: BudgetItem, context: NSManagedObjectContext) -> Decimal {
        guard let book = item.book else { return 0 }
        let cal = Calendar.current
        let start = cal.startOfDay(for: book.startDate)
        let end = max(start, Date())
        return spending(in: start...end, category: item.category, book: book, context: context)
    }

    func totalBudget(for book: BudgetBook) -> Decimal {
        return book.items?.reduce(into: Decimal(0)) { $0 += $1.totalBudget } ?? 0
    }

    func totalCumulativeSpending(for book: BudgetBook, context: NSManagedObjectContext) -> Decimal {
        let cal = Calendar.current
        let start = cal.startOfDay(for: book.startDate)
        let end = max(start, Date())
        return spending(in: start...end, category: nil, book: book, context: context)
    }

    func totalCurrentPeriodSpending(for book: BudgetBook, context: NSManagedObjectContext) -> Decimal {
        return spending(in: clippedRange(currentMonthRange(), to: book), category: nil, book: book, context: context)
    }

    func totalCurrentPeriodBudget(for book: BudgetBook) -> Decimal {
        guard let items = book.items else { return 0 }
        return items.reduce(into: Decimal(0)) { total, item in
            // 本期按真实周期，但如果书覆盖不全则钳到累计
            total += item.periodBudget
        }
    }

    func unbudgetedCategorySpending(for book: BudgetBook, context: NSManagedObjectContext) -> [(Category, Decimal)] {
        // 匹配模式下，没有"非预算项"的概念——所有未匹配分类的支出都不计入本预算
        guard !book.matchBudgetItems else { return [] }
        guard let ledger = book.ledger else { return [] }

        let budgetedIDs = budgetedCategoryIDs(for: book)
        let catRequest = NSFetchRequest<Category>(entityName: "Category")
        catRequest.predicate = NSPredicate(format: "ledger.id == %@ AND typeRaw == %@",
            ledger.id as CVarArg, TransactionType.expense.rawValue)
        let allExpenseCategories = (try? context.fetch(catRequest)) ?? []
        let unbudgeted = allExpenseCategories.filter { !budgetedIDs.contains($0.id) }

        let spendingByCategory = categorySpending(in: clippedRange(currentMonthRange(), to: book), for: book, context: context)

        return unbudgeted
            .compactMap { cat -> (Category, Decimal)? in
                let s = spendingByCategory[cat.id] ?? 0
                return s > 0 ? (cat, s) : nil
            }
            .sorted { $0.1 > $1.1 }
    }

    // MARK: - Private helpers

    private func currentPeriodRange(for item: BudgetItem, now: Date) -> ClosedRange<Date> {
        let cal = Calendar.current
        switch item.period {
        case .weekly:
            let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            let end = cal.date(byAdding: .day, value: 6, to: start) ?? now
            return cal.startOfDay(for: start)...cal.endOfDay(for: end)
        case .monthly:
            return currentMonthRange(now: now)
        case .quarterly:
            let month = cal.component(.month, from: now)
            let qStart = ((month - 1) / 3) * 3 + 1
            let start = cal.date(from: DateComponents(year: cal.component(.year, from: now), month: qStart, day: 1)) ?? now
            let end = cal.date(byAdding: DateComponents(month: 3, day: -1), to: start) ?? now
            return cal.startOfDay(for: start)...cal.endOfDay(for: end)
        case .yearly:
            let start = cal.date(from: cal.dateComponents([.year], from: now)) ?? now
            let end = cal.date(byAdding: DateComponents(year: 1, day: -1), to: start) ?? now
            return cal.startOfDay(for: start)...cal.endOfDay(for: end)
        }
    }

    private func currentMonthRange(now: Date = Date()) -> ClosedRange<Date> {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? now
        return cal.startOfDay(for: start)...cal.endOfDay(for: end)
    }

    // MARK: - 共用查询引擎（所有支出统计的单一入口）

    /// 按日期范围查询支出交易，统一筛选规则：排除拆分父交易、排除报销交易。
    /// 退款交易（type=expense, amount 为正）包含在结果中，调用方通过原始金额累加自动抵消。
    private func fetchExpenseTransactions(in range: ClosedRange<Date>, ledgerID: UUID, context: NSManagedObjectContext) -> [Transaction] {
        let request = NSFetchRequest<Transaction>(entityName: "Transaction")
        request.predicate = NSPredicate(format: "date >= %@ AND date <= %@ AND isSplitParent == false AND ledger.id == %@ AND typeRaw == %@",
            range.lowerBound as CVarArg, range.upperBound as CVarArg, ledgerID as CVarArg, TransactionType.expense.rawValue)
        let transactions = (try? context.fetch(request)) ?? []
        return transactions.filter { !$0.isReimbursable }
    }

    func totalExpense(in range: ClosedRange<Date>, ledger: Ledger, context: NSManagedObjectContext) -> Decimal {
        let txs = fetchExpenseTransactions(in: range, ledgerID: ledger.id, context: context)
        return abs(txs.reduce(Decimal(0)) { $0 + $1.amount })
    }

    func categorySpending(in range: ClosedRange<Date>, for book: BudgetBook, context: NSManagedObjectContext) -> [UUID: Decimal] {
        guard let ledgerID = book.ledger?.id else { return [:] }
        return fetchExpenseTransactions(in: range, ledgerID: ledgerID, context: context)
            .reduce(into: [:]) { dict, t in
                guard let catID = t.category?.id else { return }
                dict[catID, default: 0] += t.amount
            }
            .mapValues { abs($0) }
    }

    private func spending(in range: ClosedRange<Date>, category: Category?, book: BudgetBook, context: NSManagedObjectContext) -> Decimal {
        guard let ledgerID = book.ledger?.id else { return 0 }
        var txs = fetchExpenseTransactions(in: range, ledgerID: ledgerID, context: context)
        if let cat = category {
            txs = txs.filter { $0.category?.id == cat.id }
        } else if book.matchBudgetItems {
            let ids = budgetedCategoryIDs(for: book)
            guard !ids.isEmpty else { return 0 }
            txs = txs.filter { t in
                guard let cid = t.category?.id else { return false }
                return ids.contains(cid)
            }
        }
        return abs(txs.reduce(Decimal(0)) { $0 + $1.amount })
    }

    private func budgetedCategoryIDs(for book: BudgetBook) -> Set<UUID> {
        Set((book.items as? Set<BudgetItem> ?? []).compactMap { $0.category?.id })
    }

    /// 将日期范围裁剪到预算书起始日（按自然日），保护后续计算不出界
    private func clippedRange(_ range: ClosedRange<Date>, to book: BudgetBook) -> ClosedRange<Date> {
        let cal = Calendar.current
        let start = max(range.lowerBound, cal.startOfDay(for: book.startDate))
        let end = max(start, range.upperBound)
        return start...end
    }
}

private extension Decimal {
    func normalizedToMonthly(period: BudgetPeriod) -> Decimal {
        switch period {
        case .weekly:   return self * 52 / 12
        case .monthly:  return self
        case .quarterly: return self / 3
        case .yearly:   return self / 12
        }
    }
}

extension Calendar {
    func endOfDay(for date: Date) -> Date {
        self.date(bySettingHour: 23, minute: 59, second: 59, of: date) ?? date
    }
}
