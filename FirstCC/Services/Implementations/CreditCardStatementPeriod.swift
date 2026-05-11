import Foundation

struct CreditCardStatementPeriod {
    let startDate: Date
    let endDate: Date

    init?(billingDay: Int, year: Int, month: Int, calendar: Calendar = .current) {
        var prevMonth = month - 1
        var prevYear = year
        if prevMonth < 1 {
            prevMonth = 12
            prevYear -= 1
        }

        var startComponents = DateComponents(year: prevYear, month: prevMonth, day: billingDay)
        startComponents.hour = 0
        startComponents.minute = 0
        startComponents.second = 0

        var endComponents = DateComponents(year: year, month: month, day: billingDay)
        endComponents.hour = 23
        endComponents.minute = 59
        endComponents.second = 59

        guard let startDate = calendar.date(from: startComponents),
              let endDate = calendar.date(from: endComponents) else {
            return nil
        }

        self.startDate = startDate
        self.endDate = endDate
    }

    func contains(_ date: Date) -> Bool {
        date >= startDate && date <= endDate
    }
}
