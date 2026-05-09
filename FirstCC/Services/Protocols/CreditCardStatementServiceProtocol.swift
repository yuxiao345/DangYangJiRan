import Foundation
import SwiftData

protocol CreditCardStatementServiceProtocol {
    func createStatement(_ statement: CreditCardStatement, ledger: Ledger, context: ModelContext) throws
    func fetchStatements(for account: Account, context: ModelContext) throws -> [CreditCardStatement]
    func updateStatement(_ statement: CreditCardStatement, context: ModelContext) throws
    func deleteStatement(_ statement: CreditCardStatement, context: ModelContext) throws
    func calculateAppAmount(for account: Account, year: Int, month: Int, context: ModelContext) -> Decimal
}
