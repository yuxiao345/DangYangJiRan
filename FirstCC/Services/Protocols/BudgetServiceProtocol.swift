import Foundation
@preconcurrency import CoreData

protocol BudgetServiceProtocol {
    // BudgetBook
    func createBook(_ book: BudgetBook, ledger: Ledger, context: NSManagedObjectContext) throws
    func fetchBooks(for ledger: Ledger, context: NSManagedObjectContext) throws -> [BudgetBook]
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
    func totalBudget(for book: BudgetBook) -> Decimal
    func totalCumulativeSpending(for book: BudgetBook, context: NSManagedObjectContext) -> Decimal
    func totalCurrentPeriodSpending(for book: BudgetBook, context: NSManagedObjectContext) -> Decimal
    func totalCurrentPeriodBudget(for book: BudgetBook) -> Decimal
}
