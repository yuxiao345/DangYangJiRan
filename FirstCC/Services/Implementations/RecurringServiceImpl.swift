import Foundation
import SwiftData

struct RecurringServiceImpl: RecurringServiceProtocol {
    func setRecurring(
        template: TransactionTemplate,
        frequency: RecurringFrequency,
        interval: Int,
        startDate: Date,
        endDate: Date?,
        context: ModelContext
    ) throws -> RecurringRule {
        let rule: RecurringRule
        if let existing = template.recurringRule {
            existing.frequency = frequency
            existing.interval = interval
            existing.startDate = startDate
            existing.endDate = endDate
            existing.isActive = true
            existing.nextGenerateDate = RecurringRule.calculateNextDate(
                from: startDate, frequency: frequency, interval: interval
            )
            existing.lastGeneratedDate = nil
            rule = existing
        } else {
            rule = RecurringRule(
                frequency: frequency,
                interval: interval,
                startDate: startDate,
                endDate: endDate
            )
            rule.template = template
            template.recurringRule = rule
            template.isRecurring = true
        }
        try context.save()
        return rule
    }

    func disableRecurring(template: TransactionTemplate, context: ModelContext) throws {
        if let rule = template.recurringRule {
            rule.template = nil
            template.recurringRule = nil
            context.delete(rule)
        }
        template.isRecurring = false
        try context.save()
    }

    func processDueRecurring(context: ModelContext) throws {
        let now = Date()
        let descriptor = FetchDescriptor<RecurringRule>(
            predicate: #Predicate { $0.isActive == true }
        )
        let rules = try context.fetch(descriptor)

        for rule in rules {
            guard let template = rule.template else { continue }
            guard var nextDate = rule.nextGenerateDate else { continue }

            // Fast-forward: skip missed periods, only generate the current one
            while nextDate <= now {
                let following = RecurringRule.calculateNextDate(
                    from: nextDate,
                    frequency: rule.frequency,
                    interval: rule.interval
                )
                if following > now {
                    // This is the current period — generate the transaction
                    let transaction = Transaction(
                        type: template.type,
                        amount: template.amount,
                        currencyCode: template.currencyCode,
                        note: template.note,
                        date: nextDate,
                        tags: template.tags,
                        account: template.account,
                        toAccount: template.toAccount,
                        category: template.category
                    )
                    transaction.ledger = template.ledger
                    transaction.template = template
                    context.insert(transaction)

                    rule.lastGeneratedDate = nextDate
                    rule.nextGenerateDate = following
                    break
                }
                // Skip this missed period, advance to next
                if let endDate = rule.endDate, nextDate > endDate {
                    rule.isActive = false
                    break
                }
                nextDate = following
            }
        }

        try context.save()
    }

    func nextGenerateDate(for rule: RecurringRule) -> Date? {
        rule.nextGenerateDate
    }
}
