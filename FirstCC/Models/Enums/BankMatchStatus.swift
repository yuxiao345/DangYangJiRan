import Foundation

enum BankMatchStatus: String, Codable, CaseIterable {
    case unmatched
    case matched
    case conflicted
    case ignored
    case suspectedDateMismatch   // exact amount, date off by 1-2 days
    case suspectedAmountMismatch // exact date, amount off by small margin
}
