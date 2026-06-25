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
        let range = currentPeriodRange(for: item, now: now)
        return spending(in: range, category: item.category, book: book, context: context)
    }

    func cumulativeSpending(for item: BudgetItem, context: NSManagedObjectContext) -> Decimal {
        guard let book = item.book else { return 0 }
        let end = max(book.startDate, Date())
        return spending(in: book.startDate...end, category: item.category, book: book, context: context)
    }

    func totalBudget(for book: BudgetBook) -> Decimal {
        return book.items?.reduce(into: Decimal(0)) { $0 += $1.totalBudget } ?? 0
    }

    func totalCumulativeSpending(for book: BudgetBook, context: NSManagedObjectContext) -> Decimal {
        let end = max(book.startDate, Date())
        return spending(in: book.startDate...end, category: nil, book: book, context: context)
    }

    func totalCurrentPeriodSpending(for book: BudgetBook, context: NSManagedObjectContext) -> Decimal {
        return spending(in: currentMonthRange(), category: nil, book: book, context: context)
    }

    func totalCurrentPeriodBudget(for book: BudgetBook) -> Decimal {
        guard let items = book.items else { return 0 }
        return items.reduce(into: Decimal(0)) { total, item in
            total += item.amount.normalizedToMonthly(period: item.period)
        }
    }

    func unbudgetedCategorySpending(for book: BudgetBook, context: NSManagedObjectContext) -> [(Category, Decimal)] {
        guard let ledger = book.ledger else { return [] }

        let budgetedIDs = Set((book.items as? Set<BudgetItem> ?? [])
            .compactMap { $0.category?.id })
        let catRequest = NSFetchRequest<Category>(entityName: "Category")
        catRequest.predicate = NSPredicate(format: "ledger.id == %@ AND typeRaw == %@",
            ledger.id as CVarArg, TransactionType.expense.rawValue)
        let allExpenseCategories = (try? context.fetch(catRequest)) ?? []
        let unbudgeted = allExpenseCategories.filter { !budgetedIDs.contains($0.id) }

        // Single fetch — partition by category in memory
        let spendingByCategory = categorySpending(in: currentMonthRange(), for: book, context: context)

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

    func categorySpending(in range: ClosedRange<Date>, for book: BudgetBook, context: NSManagedObjectContext) -> [UUID: Decimal] {
        guard let ledgerID = book.ledger?.id else { return [:] }
        let lower = range.lowerBound
        let upper = range.upperBound
        let request = NSFetchRequest<Transaction>(entityName: "Transaction")
        request.predicate = NSPredicate(format: "date >= %@ AND date <= %@ AND parentTransaction == nil AND ledger.id == %@ AND typeRaw == %@",
            lower as CVarArg, upper as CVarArg, ledgerID as CVarArg, TransactionType.expense.rawValue)
        let transactions = (try? context.fetch(request)) ?? []
        return transactions.reduce(into: [:]) { dict, t in
            guard t.refundGroupId == nil,
                  !t.isReimbursable,
                  let catID = t.category?.id else { return }
            dict[catID, default: 0] += abs(t.amount)
        }
    }

    private func spending(in range: ClosedRange<Date>, category: Category?, book: BudgetBook, context: NSManagedObjectContext) -> Decimal {
        guard let ledgerID = book.ledger?.id else { return 0 }

        let lower = range.lowerBound
        let upper = range.upperBound
        var fmt = "date >= %@ AND date <= %@ AND parentTransaction == nil AND ledger.id == %@ AND typeRaw == %@"
        var args: [CVarArg] = [lower as CVarArg, upper as CVarArg, ledgerID as CVarArg, TransactionType.expense.rawValue]
        if let cat = category {
            fmt += " AND category.id == %@"
            args.append(cat.id as CVarArg)
        }
        let request = NSFetchRequest<Transaction>(entityName: "Transaction")
        request.predicate = NSPredicate(format: fmt, argumentArray: args)
        let transactions = (try? context.fetch(request)) ?? []
        return transactions
            .filter { t in
                guard t.refundGroupId == nil else { return false }
                guard !t.isReimbursable else { return false }
                return true
            }
            .reduce(into: Decimal(0)) { $0 += abs($1.amount) }
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
