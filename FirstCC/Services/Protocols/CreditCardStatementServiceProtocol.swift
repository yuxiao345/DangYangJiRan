import Foundation
@preconcurrency import CoreData

protocol CreditCardStatementServiceProtocol {
    func createStatement(_ statement: CreditCardStatement, ledger: Ledger, context: NSManagedObjectContext) throws
    func fetchStatements(for account: Account, context: NSManagedObjectContext) throws -> [CreditCardStatement]
    func updateStatement(_ statement: CreditCardStatement, context: NSManagedObjectContext) throws
    func deleteStatement(_ statement: CreditCardStatement, context: NSManagedObjectContext) throws
    func calculateAppAmount(for account: Account, year: Int, month: Int, context: NSManagedObjectContext) -> Decimal
}
