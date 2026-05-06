import Foundation
import SwiftData

protocol BudgetServiceProtocol {
    func createBudget(_ budget: Budget, ledger: Ledger, context: ModelContext) throws
    func fetchBudgets(for ledger: Ledger, context: ModelContext) throws -> [Budget]
    func updateBudget(_ budget: Budget, context: ModelContext) throws
    func deleteBudget(_ budget: Budget, context: ModelContext) throws
    func currentSpending(for budget: Budget, context: ModelContext) -> Decimal
    func checkOverspend(budget: Budget, context: ModelContext) -> Bool
}
