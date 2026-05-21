import Foundation

extension Array where Element == Transaction {
    func groupedByRelativeDate(locale: Locale? = nil) -> [(key: String, value: [Transaction])] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today) ?? today

        var todayTx: [Transaction] = []
        var yesterdayTx: [Transaction] = []
        var other: [String: [Transaction]] = [:]

        for t in self {
            let day = cal.startOfDay(for: t.date)
            if day == today {
                todayTx.append(t)
            } else if day == yesterday {
                yesterdayTx.append(t)
            } else {
                var fmt = t.date.formatted(.dateTime.month(.abbreviated).day(.defaultDigits))
                if let locale { fmt = t.date.formatted(.dateTime.month(.abbreviated).day(.defaultDigits).locale(locale)) }
                other[fmt, default: []].append(t)
            }
        }

        var result: [(String, [Transaction])] = []
        if !todayTx.isEmpty { result.append(("今天", todayTx)) }
        if !yesterdayTx.isEmpty { result.append(("昨天", yesterdayTx)) }
        for key in other.keys.sorted(by: >) {
            if let list = other[key] { result.append((key, list)) }
        }
        return result
    }
}
