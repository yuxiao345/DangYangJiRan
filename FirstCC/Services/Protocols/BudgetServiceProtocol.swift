import Foundation
import SwiftData

protocol BudgetServiceProtocol {
    // BudgetBook
    func createBook(_ book: BudgetBook, ledger: Ledger, context: ModelContext) throws
    func fetchBooks(for ledger: Ledger, context: ModelContext) throws -> [BudgetBook]
    func updateBook(_ book: BudgetBook, context: ModelContext) throws
    func deleteBook(_ book: BudgetBook, context: ModelContext) throws

    // BudgetItem
    func createItem(_ item: BudgetItem, book: BudgetBook, ledger: Ledger, context: ModelContext) throws
    func fetchItems(for book: BudgetBook, context: ModelContext) throws -> [BudgetItem]
    func updateItem(_ item: BudgetItem, context: ModelContext) throws
    func deleteItem(_ item: BudgetItem, context: ModelContext) throws

    // Calculations
    func currentPeriodSpending(for item: BudgetItem, context: ModelContext) -> Decimal
    func cumulativeSpending(for item: BudgetItem, context: ModelContext) -> Decimal
    func totalBudget(for book: BudgetBook) -> Decimal
    func totalCumulativeSpending(for book: BudgetBook, context: ModelContext) -> Decimal
    func totalCurrentPeriodSpending(for book: BudgetBook, context: ModelContext) -> Decimal
    func totalCurrentPeriodBudget(for book: BudgetBook) -> Decimal
}
