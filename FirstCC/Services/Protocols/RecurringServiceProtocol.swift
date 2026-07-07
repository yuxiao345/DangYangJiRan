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
    func deduplicateRecurringTransactions(context: NSManagedObjectContext) throws
    /// 生成到期周期交易并清理跨设备重复。调用方应使用此方法
    /// 而非分别调用 processDueRecurring + deduplicateRecurringTransactions。
    func processAndDeduplicate(context: NSManagedObjectContext) throws
    func nextGenerateDate(for rule: RecurringRule) -> Date?
    func fetchRules(for ledger: Ledger, context: NSManagedObjectContext) throws -> [RecurringRule]
    func fetchActiveRules(for ledger: Ledger, context: NSManagedObjectContext) throws -> [RecurringRule]
}
