import Foundation
@preconcurrency import CoreData

@objc(ExchangeRate)
final class ExchangeRate: NSManagedObject,  Sendable {
    @NSManaged var id: UUID
    @NSManaged var fromCurrencyCode: String
    @NSManaged var toCurrencyCode: String
    @NSManaged var rate: Double
    @NSManaged var fetchedAt: Date

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        fetchedAt = Date()
    }

    convenience init(
        fromCurrencyCode: String,
        toCurrencyCode: String,
        rate: Double,
        fetchedAt: Date = Date(),
        context: NSManagedObjectContext
    ) {
        self.init(context: context)
        self.fromCurrencyCode = fromCurrencyCode
        self.toCurrencyCode = toCurrencyCode
        self.rate = rate
        self.fetchedAt = fetchedAt
    }
}

extension ExchangeRate: Identifiable {}
