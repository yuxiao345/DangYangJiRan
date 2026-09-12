import Foundation
@preconcurrency import CoreData

protocol BudgetServiceProtocol {
    // BudgetBook
    func createBook(_ book: BudgetBook, ledger: Ledger, context: NSManagedObjectContext) throws
    func fetchBooks(for ledger: Ledger, context: NSManagedObjectContext) throws -> [BudgetBook]
    func findBookByName(_ name: String, ledger: Ledger, context: NSManagedObjectContext) throws -> BudgetBook?
    func updateBook(_ book: BudgetBook, context: NSManagedObjectContext) throws
    func deleteBook(_ book: BudgetBook, context: NSManagedObjectContext) throws
    func reorderBooks(_ books: [BudgetBook], context: NSManagedObjectContext) throws

    // BudgetItem
    func createItem(_ item: BudgetItem, book: BudgetBook, ledger: Ledger, context: NSManagedObjectContext) throws
    func fetchItems(for book: BudgetBook, context: NSManagedObjectContext) throws -> [BudgetItem]
    func updateItem(_ item: BudgetItem, context: NSManagedObjectContext) throws
    func deleteItem(_ item: BudgetItem, context: NSManagedObjectContext) throws

    // Calculations
    func currentPeriodSpending(for item: BudgetItem, context: NSManagedObjectContext) -> Decimal
    func cumulativeSpending(for item: BudgetItem, context: NSManagedObjectContext) -> Decimal

    /// 当前周期范围（按 item.period 算周/月/季/年的真实当期）。用于"本期明细"链接。
    func currentPeriodRange(for item: BudgetItem, now: Date, context: NSManagedObjectContext) -> ClosedRange<Date>

    /// 累计区间：账本起始日（自然日）→ 今天（endOfDay）。用于"累计明细"链接。
    func cumulativeRange(for item: BudgetItem, context: NSManagedObjectContext) -> ClosedRange<Date>
    func totalBudget(for book: BudgetBook) -> Decimal
    func totalCumulativeSpending(for book: BudgetBook, context: NSManagedObjectContext) -> Decimal
    func totalCumulativeSpending(in range: ClosedRange<Date>, for book: BudgetBook, context: NSManagedObjectContext) -> Decimal
    func totalCurrentPeriodSpending(for book: BudgetBook, context: NSManagedObjectContext) -> Decimal
    func totalCurrentPeriodSpending(in range: ClosedRange<Date>, for book: BudgetBook, context: NSManagedObjectContext) -> Decimal
    func totalCurrentPeriodBudget(for book: BudgetBook) -> Decimal
    func unbudgetedCategorySpending(for book: BudgetBook, context: NSManagedObjectContext) -> [(Category, Decimal)]
    func unbudgetedCategorySpending(in range: ClosedRange<Date>, for book: BudgetBook, context: NSManagedObjectContext) -> [(Category, Decimal)]
    func categorySpending(in range: ClosedRange<Date>, for book: BudgetBook, context: NSManagedObjectContext) -> [UUID: Decimal]

    /// 通用本月支出（不依赖预算书），和各项内部计算使用完全一致的筛选逻辑
    func totalExpense(in range: ClosedRange<Date>, ledger: Ledger, context: NSManagedObjectContext) -> Decimal

    /// 每日支出趋势（按分类可选，excludeCategoryIDs 用于排除特定子分类——其自身及后代均不参与聚合）
    func dailySpending(in range: ClosedRange<Date>, categoryID: UUID?, excludeCategoryIDs: Set<UUID>, ledgerID: UUID, context: NSManagedObjectContext) -> [DailySpendingPoint]
}

extension BudgetServiceProtocol {
    func dailySpending(in range: ClosedRange<Date>, categoryID: UUID?, ledgerID: UUID, context: NSManagedObjectContext) -> [DailySpendingPoint] {
        dailySpending(in: range, categoryID: categoryID, excludeCategoryIDs: [], ledgerID: ledgerID, context: context)
    }

    /// prod 便捷方法：默认使用当前时间作为 now
    func currentPeriodRange(for item: BudgetItem, context: NSManagedObjectContext) -> ClosedRange<Date> {
        currentPeriodRange(for: item, now: Date.now, context: context)
    }
}
