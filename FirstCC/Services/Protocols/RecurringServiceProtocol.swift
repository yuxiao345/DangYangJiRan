import Foundation
import SwiftData

protocol RecurringServiceProtocol {
    func setRecurring(
        template: TransactionTemplate,
        frequency: RecurringFrequency,
        interval: Int,
        startDate: Date,
        endDate: Date?,
        context: ModelContext
    ) throws -> RecurringRule
    func disableRecurring(template: TransactionTemplate, context: ModelContext) throws
    func processDueRecurring(context: ModelContext) throws
    func nextGenerateDate(for rule: RecurringRule) -> Date?
}
