import Foundation
import SwiftData

protocol LendingServiceProtocol {
    func createLending(_ lending: Lending, ledger: Ledger, user: User?, context: ModelContext) throws
    func addRepayment(lending: Lending, amount: Decimal, date: Date, note: String?, context: ModelContext) throws
    func fetchLendings(for ledger: Ledger, context: ModelContext) throws -> [Lending]
    func fetchActiveLendings(for ledger: Ledger, context: ModelContext) throws -> [Lending]
    func settleLending(_ lending: Lending, context: ModelContext) throws
    func deleteLending(_ lending: Lending, context: ModelContext) throws
}
