import Foundation
@preconcurrency import CoreData

@objc(RecurringRule)
final class RecurringRule: NSManagedObject,  Sendable {
    @NSManaged var id: UUID
    @NSManaged var frequencyRaw: String
    @NSManaged var interval: Int64
    @NSManaged var startDate: Date
    @NSManaged var endDate: Date?
    @NSManaged var lastGeneratedDate: Date?
    @NSManaged var nextGenerateDate: Date?
    @NSManaged var isActive: Bool

    @NSManaged var template: TransactionTemplate?

    var frequency: RecurringFrequency {
        get { RecurringFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        startDate = Date()
    }

    convenience init(
        frequency: RecurringFrequency = .monthly,
        interval: Int = 1,
        startDate: Date = Date(),
        endDate: Date? = nil,
        isActive: Bool = true,
        context: NSManagedObjectContext
    ) {
        self.init(context: context)
        self.frequencyRaw = frequency.rawValue
        self.interval = Int64(interval)
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = isActive
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

extension RecurringRule: Identifiable {}
