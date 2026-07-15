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
        return rootBudgetItems(for: book).reduce(into: Decimal(0)) { $0 += $1.totalBudget }
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
        // 只汇总顶层预算项（无预算祖先的），子预算是子限额而非独立封套
        return rootBudgetItems(for: book).reduce(into: Decimal(0)) { total, item in
            total += item.periodBudget.normalizedToMonthly(period: item.period)
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

        // 排除自身或任意祖先有预算的分类（父预算覆盖所有子分类）
        let unbudgeted = allExpenseCategories.filter { cat in
            if budgetedIDs.contains(cat.id) { return false }
            return !cat.allAncestorIDs.contains(where: { budgetedIDs.contains($0) })
        }

        // 用原始（非展开）按分类支出，避免子分类交易被重复计入未预算的父分类
        let range = clippedRange(currentMonthRange(), to: book)
        let txs = fetchExpenseTransactions(in: range, ledgerID: ledger.id, context: context)
        var rawByCat: [UUID: Decimal] = [:]
        for t in txs {
            guard let catID = t.category?.id else { continue }
            rawByCat[catID, default: 0] += t.netExpenseAmount
        }
        let spendingByCategory = rawByCat.mapValues { max(0, $0) }

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
        let net = txs.reduce(Decimal(0)) { $0 + $1.netExpenseAmount }
        return max(0, net)
    }

    func categorySpending(in range: ClosedRange<Date>, for book: BudgetBook, context: NSManagedObjectContext) -> [UUID: Decimal] {
        guard let ledgerID = book.ledger?.id else { return [:] }
        let txs = fetchExpenseTransactions(in: range, ledgerID: ledgerID, context: context)
        // 先按 Category 对象预分组——transaction 已通过 relationship 持有 Category，无需额外 fetch
        var byCategory: [Category: Decimal] = [:]
        for t in txs {
            guard let cat = t.category else { continue }
            byCategory[cat, default: 0] += t.netExpenseAmount
        }
        // 再展开祖先：每个唯一分类只计算一次 allAncestorIDs，而非每笔交易都重复计算
        var result: [UUID: Decimal] = [:]
        for (cat, sum) in byCategory {
            var ancestorIDs = cat.allAncestorIDs
            ancestorIDs.insert(cat.id)
            for id in ancestorIDs {
                result[id, default: 0] += sum
            }
        }
        return result.mapValues { max(0, $0) }
    }

    private func spending(in range: ClosedRange<Date>, category: Category?, book: BudgetBook, context: NSManagedObjectContext) -> Decimal {
        guard let ledgerID = book.ledger?.id else { return 0 }
        var txs = fetchExpenseTransactions(in: range, ledgerID: ledgerID, context: context)
        if let cat = category {
            let matchIDs = cat.allDescendantIDs.union([cat.id])
            txs = txs.filter { t in
                guard let cid = t.category?.id else { return false }
                return matchIDs.contains(cid)
            }
        } else if book.matchBudgetItems {
            let ids = budgetedCategoryIDs(for: book)
            guard !ids.isEmpty else { return 0 }
            txs = txs.filter { t in
                guard let cid = t.category?.id else { return false }
                return ids.contains(cid)
            }
        }
        let net = txs.reduce(Decimal(0)) { $0 + $1.netExpenseAmount }
        return max(0, net)
    }

    /// 顶层预算项：category 没有预算祖先的项。子预算是子限额，不应与父预算累加。
    private func rootBudgetItems(for book: BudgetBook) -> [BudgetItem] {
        let items = (book.items as? Set<BudgetItem> ?? []).filter { $0.isActive }
        let budgetedCatIDs = Set(items.compactMap { $0.category?.id })
        return items.filter { item in
            guard let cat = item.category else { return true }
            // 如果该分类的任何祖先也有预算，则本项是子限额，不计入汇总
            return !cat.allAncestorIDs.contains(where: { budgetedCatIDs.contains($0) })
        }
    }

    private func budgetedCategoryIDs(for book: BudgetBook) -> Set<UUID> {
        let items = (book.items as? Set<BudgetItem> ?? []).filter { $0.isActive }
        var ids = Set<UUID>()
        for item in items {
            guard let cat = item.category else { continue }
            ids.insert(cat.id)
            // 展开后代：如果预算设在父分类，所有子分类交易也应被计入
            ids.formUnion(cat.allDescendantIDs)
        }
        return ids
    }

    /// 将日期范围裁剪到预算书起始日（按自然日），保护后续计算不出界
    private func clippedRange(_ range: ClosedRange<Date>, to book: BudgetBook) -> ClosedRange<Date> {
        let cal = Calendar.current
        let start = max(range.lowerBound, cal.startOfDay(for: book.startDate))
        let end = max(start, range.upperBound)
        return start...end
    }

    // MARK: - Daily Trend

    func dailySpending(in range: ClosedRange<Date>, categoryID: UUID?, excludeCategoryIDs: Set<UUID> = [], ledgerID: UUID, context: NSManagedObjectContext) -> [DailySpendingPoint] {
        let cal = Calendar.current
        let txs = fetchExpenseTransactions(in: range, ledgerID: ledgerID, context: context)
        let filtered: [Transaction]
        if let cid = categoryID {
            // 批量查询所有需要的 Category（主分类 + 排除分类），一次 fetch 替代 N 次
            var allCatIDs = Set([cid])
            allCatIDs.formUnion(excludeCategoryIDs)
            let catRequest = NSFetchRequest<Category>(entityName: "Category")
            catRequest.predicate = NSPredicate(format: "id in %@", Array(allCatIDs) as CVarArg)
            let fetchedCats = (try? context.fetch(catRequest)) ?? []
            let catByID = Dictionary(uniqueKeysWithValues: fetchedCats.map { ($0.id, $0) })

            if let cat = catByID[cid] {
                var matchIDs = cat.allDescendantIDs.union([cat.id])
                // 排除指定子分类及其后代，让父分类只统计其独占的交易
                for eid in excludeCategoryIDs {
                    if let exCat = catByID[eid] {
                        matchIDs.subtract(exCat.allDescendantIDs.union([exCat.id]))
                    }
                }
                filtered = txs.filter { t in
                    guard let tcID = t.category?.id else { return false }
                    return matchIDs.contains(tcID)
                }
            } else {
                filtered = txs.filter { $0.category?.id == cid }
            }
        } else {
            filtered = txs
        }
        var byDay: [Date: Decimal] = [:]
        for t in filtered {
            let day = cal.startOfDay(for: t.date)
            byDay[day, default: 0] += t.netExpenseAmount
        }
        var current = cal.startOfDay(for: range.lowerBound)
        let end = min(cal.startOfDay(for: range.upperBound), cal.startOfDay(for: Date()))
        var points: [DailySpendingPoint] = []
        while current <= end {
            points.append(DailySpendingPoint(date: current, amount: byDay[current] ?? 0))
            current = cal.date(byAdding: .day, value: 1, to: current) ?? current.addingTimeInterval(86400)
        }
        return points
    }
}

extension Calendar {
    func endOfDay(for date: Date) -> Date {
        self.date(bySettingHour: 23, minute: 59, second: 59, of: date) ?? date
    }
}
