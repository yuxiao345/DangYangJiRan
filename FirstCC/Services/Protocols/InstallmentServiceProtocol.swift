import Foundation
import SwiftData

protocol InstallmentServiceProtocol {
    func createPlan(_ plan: InstallmentPlan, ledger: Ledger, context: ModelContext) throws
    func generateNextInstallment(plan: InstallmentPlan, context: ModelContext) throws -> Transaction
    func fetchPlans(for ledger: Ledger, context: ModelContext) throws -> [InstallmentPlan]
    func deletePlan(_ plan: InstallmentPlan, context: ModelContext) throws
}
