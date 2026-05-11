import Foundation
import SwiftData

final class BudgetServiceImpl: BudgetServiceProtocol {

    // MARK: - BudgetBook

    func createBook(_ book: BudgetBook, ledger: Ledger, context: ModelContext) throws {
        book.ledger = ledger
        context.insert(book)
        try context.save()
    }

    func fetchBooks(for ledger: Ledger, context: ModelContext) throws -> [BudgetBook] {
        let lid = ledger.id
        let predicate = #Predicate<BudgetBook> { book in
            book.ledger?.id == lid
        }
        return try context.fetch(FetchDescriptor<BudgetBook>(predicate: predicate))
    }

    func updateBook(_ book: BudgetBook, context: ModelContext) throws {
        try context.save()
    }

    func deleteBook(_ book: BudgetBook, context: ModelContext) throws {
        context.delete(book)
        try context.save()
    }

    // MARK: - BudgetItem

    func createItem(_ item: BudgetItem, book: BudgetBook, ledger: Ledger, context: ModelContext) throws {
        NSLog("[BudgetSvc] createItem: setting book")
        item.book = book
        NSLog("[BudgetSvc] createItem: inserting into context")
        context.insert(item)
        NSLog("[BudgetSvc] createItem: saving context")
        try context.save()
        NSLog("[BudgetSvc] createItem: done")
    }

    func fetchItems(for book: BudgetBook, context: ModelContext) throws -> [BudgetItem] {
        let bid = book.id
        let predicate = #Predicate<BudgetItem> { item in
            item.book?.id == bid
        }
        return try context.fetch(FetchDescriptor<BudgetItem>(predicate: predicate))
    }

    func updateItem(_ item: BudgetItem, context: ModelContext) throws {
        try context.save()
    }

    func deleteItem(_ item: BudgetItem, context: ModelContext) throws {
        context.delete(item)
        try context.save()
    }

    // MARK: - Calculations

    func currentPeriodSpending(for item: BudgetItem, context: ModelContext) -> Decimal {
        guard let book = item.book else { return 0 }
        let now = Date()
        let range = currentPeriodRange(for: item, now: now)
        return spending(in: range, category: item.category, book: book, context: context)
    }

    func cumulativeSpending(for item: BudgetItem, context: ModelContext) -> Decimal {
        guard let book = item.book else { return 0 }
        return spending(in: book.startDate...Date(), category: item.category, book: book, context: context)
    }

    func totalBudget(for book: BudgetBook) -> Decimal {
        return book.items?.reduce(into: Decimal(0)) { $0 += $1.totalBudget } ?? 0
    }

    func totalCumulativeSpending(for book: BudgetBook, context: ModelContext) -> Decimal {
        return spending(in: book.startDate...Date(), category: nil, book: book, context: context)
    }

    func totalCurrentPeriodSpending(for book: BudgetBook, context: ModelContext) -> Decimal {
        let now = Date()
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? now
        return spending(in: cal.startOfDay(for: start)...cal.endOfDay(for: end), category: nil, book: book, context: context)
    }

    func totalCurrentPeriodBudget(for book: BudgetBook) -> Decimal {
        guard let items = book.items else { return 0 }
        return items.reduce(into: Decimal(0)) { $0 += $1.amount }
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
            let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? now
            return cal.startOfDay(for: start)...cal.endOfDay(for: end)
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

    private func spending(in range: ClosedRange<Date>, category: Category?, book: BudgetBook, context: ModelContext) -> Decimal {
        guard let ledgerID = book.ledger?.id else { return 0 }

        let lower = range.lowerBound
        let upper = range.upperBound
        let predicate = #Predicate<Transaction> { t in
            t.date >= lower && t.date <= upper && t.parentTransaction == nil
        }
        var descriptor = FetchDescriptor<Transaction>(predicate: predicate)
        descriptor.fetchLimit = 10000
        let transactions = (try? context.fetch(descriptor)) ?? []
        return transactions
            .filter { t in
                t.ledger?.id == ledgerID
                    && t.typeRaw == TransactionType.expense.rawValue
                    && (category == nil || t.category?.id == category!.id)
            }
            .reduce(into: Decimal(0)) { $0 += abs($1.amount) }
    }
}

private extension Calendar {
    func endOfDay(for date: Date) -> Date {
        self.date(bySettingHour: 23, minute: 59, second: 59, of: date) ?? date
    }
}
