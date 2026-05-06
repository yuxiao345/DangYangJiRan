import Foundation
import SwiftData

@Model
final class RecurringRule {
    var id: UUID
    var frequencyRaw: String
    var interval: Int
    var startDate: Date
    var endDate: Date?
    var lastGeneratedDate: Date?
    var nextGenerateDate: Date?
    var isActive: Bool

    var template: TransactionTemplate?

    var frequency: RecurringFrequency {
        get { RecurringFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        frequency: RecurringFrequency = .monthly,
        interval: Int = 1,
        startDate: Date = Date(),
        endDate: Date? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.frequencyRaw = frequency.rawValue
        self.interval = interval
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = isActive
        // First generation happens on startDate (if it's today or past)
        self.nextGenerateDate = startDate
    }

    static func calculateNextDate(
        from date: Date,
        frequency: RecurringFrequency,
        interval: Int
    ) -> Date {
        let calendar = Calendar.current
        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: interval, to: date) ?? date
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: interval, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: interval, to: date) ?? date
        case .yearly:
            return calendar.date(byAdding: .year, value: interval, to: date) ?? date
        }
    }
}
