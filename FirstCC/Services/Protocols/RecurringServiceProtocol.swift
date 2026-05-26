import Foundation
@preconcurrency import CoreData

protocol RecurringServiceProtocol {
    func setRecurring(
        template: TransactionTemplate,
        frequency: RecurringFrequency,
        interval: Int,
        startDate: Date,
        endDate: Date?,
        context: NSManagedObjectContext
    ) throws -> RecurringRule
    func disableRecurring(template: TransactionTemplate, context: NSManagedObjectContext) throws
    func toggleActive(for rule: RecurringRule, context: NSManagedObjectContext) throws
    func processDueRecurring(context: NSManagedObjectContext) throws
    func nextGenerateDate(for rule: RecurringRule) -> Date?
    func fetchRules(for ledger: Ledger, context: NSManagedObjectContext) throws -> [RecurringRule]
    func fetchActiveRules(for ledger: Ledger, context: NSManagedObjectContext) throws -> [RecurringRule]
}
