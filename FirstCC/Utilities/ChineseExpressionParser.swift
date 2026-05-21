import Foundation
import NaturalLanguage

struct ParsedSearchQuery {
    var dateRange: Range<Date>?
    var amountRange: ClosedRange<Decimal>?
    var transactionType: TransactionType?
    var keyword: String?
    var dateKeyword: String?
    var amountKeyword: String?
    var typeKeyword: String?
}

enum ChineseExpressionParser {

    // MARK: - Main

    static func parse(_ input: String) -> ParsedSearchQuery {
        var query = ParsedSearchQuery()
        var remaining = input

        let dateResult = extractDate(from: remaining)
        query.dateRange = dateResult.range
        query.dateKeyword = dateResult.matched
        remaining = dateResult.remaining

        let amountResult = extractAmount(from: remaining)
        query.amountRange = amountResult.range
        query.amountKeyword = amountResult.matched
        remaining = amountResult.remaining

        let typeResult = extractType(from: remaining)
        query.transactionType = typeResult.type
        query.typeKeyword = typeResult.matched
        remaining = typeResult.remaining

        let trimmed = stripNoise(remaining)
        query.keyword = trimmed.isEmpty ? nil : tokenizeAndJoin(trimmed)

        return query
    }

    // MARK: - Date Extraction

    private struct DateMatch {
        let range: Range<Date>?
        let matched: String?
        let remaining: String
    }

    private static func extractDate(from input: String) -> DateMatch {
        let cal = Calendar.current
        let today = Date()
        let startOfToday = today.startOfDay
        let tomorrowStart = offset(.day, 1, from: startOfToday)

        func offset(_ comp: Calendar.Component, _ val: Int, from date: Date) -> Date {
            cal.date(byAdding: comp, value: val, to: date) ?? date
        }

        // Ordered by specificity (longer/more specific patterns first)
        let patterns: [(String, (NSTextCheckingResult, String) -> DateMatch?)] = [
            // "2025年3月" — specific month
            ("(\\d{4})年(\\d{1,2})月", { match, str in
                guard let y = Int((str as NSString).substring(with: match.range(at: 1))),
                      let m = Int((str as NSString).substring(with: match.range(at: 2))),
                      (1...12).contains(m),
                      let start = cal.date(from: DateComponents(year: y, month: m, day: 1)),
                      let end = cal.date(byAdding: .month, value: 1, to: start) else { return nil }
                return DateMatch(range: start..<end, matched: match.fullString(in: str), remaining: remove(match, from: str))
            }),
            // "2025年" — specific year
            ("(\\d{4})年", { match, str in
                guard let y = Int((str as NSString).substring(with: match.range(at: 1))),
                      let start = cal.date(from: DateComponents(year: y, month: 1, day: 1)),
                      let end = cal.date(byAdding: .year, value: 1, to: start) else { return nil }
                return DateMatch(range: start..<end, matched: match.fullString(in: str), remaining: remove(match, from: str))
            }),
            // "最近X天" / "过去X天"
            ("(最近|过去)(\\d+)天", { match, str in
                guard let n = Int((str as NSString).substring(with: match.range(at: 2))) else { return nil }
                let start = offset(.day, -n, from: startOfToday)
                return DateMatch(range: start..<tomorrowStart, matched: match.fullString(in: str), remaining: remove(match, from: str))
            }),
            // "最近X周/星期/礼拜"
            ("(最近|过去)(\\d+)个?(?:周|星期|礼拜)", { match, str in
                guard let n = Int((str as NSString).substring(with: match.range(at: 2))) else { return nil }
                let start = offset(.day, -(n * 7), from: startOfToday)
                return DateMatch(range: start..<tomorrowStart, matched: match.fullString(in: str), remaining: remove(match, from: str))
            }),
            // "最近X个月" / "最近X月"
            ("(最近|过去)(\\d+)个?月", { match, str in
                guard let n = Int((str as NSString).substring(with: match.range(at: 2))),
                      let start = cal.date(byAdding: .month, value: -n, to: startOfToday)?.startOfMonth else { return nil }
                return DateMatch(range: start..<tomorrowStart, matched: match.fullString(in: str), remaining: remove(match, from: str))
            }),
            // "最近X年"
            ("(最近|过去)(\\d+)年", { match, str in
                guard let n = Int((str as NSString).substring(with: match.range(at: 2))),
                      let start = cal.date(byAdding: .year, value: -n, to: startOfToday)?.startOfYear else { return nil }
                return DateMatch(range: start..<tomorrowStart, matched: match.fullString(in: str), remaining: remove(match, from: str))
            }),
        ]

        // Try regex patterns first
        for (pattern, handler) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
                  let result = handler(match, input) else { continue }
            return result
        }

        // Fixed expressions — ordered by priority, first found in string wins
        let fixedExpressions: [(String, Range<Date>)] = [
            ("今天", startOfToday..<tomorrowStart),
            ("昨天", {
                let start = offset(.day, -1, from: startOfToday)
                return start..<startOfToday
            }()),
            ("明天", {
                let start = offset(.day, 1, from: startOfToday)
                let end = offset(.day, 1, from: start)
                return start..<end
            }()),
            ("本周", {
                let start = today.startOfWeek
                let end = offset(.day, 7, from: start)
                return start..<end
            }()),
            ("这周", {
                let start = today.startOfWeek
                let end = offset(.day, 7, from: start)
                return start..<end
            }()),
            ("这个星期", {
                let start = today.startOfWeek
                let end = offset(.day, 7, from: start)
                return start..<end
            }()),
            ("这个礼拜", {
                let start = today.startOfWeek
                let end = offset(.day, 7, from: start)
                return start..<end
            }()),
            ("上周", {
                let thisMonday = today.startOfWeek
                let prevMonday = offset(.day, -7, from: thisMonday)
                return prevMonday..<thisMonday
            }()),
            ("上个星期", {
                let thisMonday = today.startOfWeek
                let prevMonday = offset(.day, -7, from: thisMonday)
                return prevMonday..<thisMonday
            }()),
            ("上个礼拜", {
                let thisMonday = today.startOfWeek
                let prevMonday = offset(.day, -7, from: thisMonday)
                return prevMonday..<thisMonday
            }()),
            ("本月", {
                let start = today.startOfMonth
                let end = offset(.month, 1, from: start)
                return start..<end
            }()),
            ("这个月", {
                let start = today.startOfMonth
                let end = offset(.month, 1, from: start)
                return start..<end
            }()),
            ("上个月", {
                let thisMonth = today.startOfMonth
                let prevMonth = offset(.month, -1, from: thisMonth)
                return prevMonth..<thisMonth
            }()),
            ("上月", {
                let thisMonth = today.startOfMonth
                let prevMonth = offset(.month, -1, from: thisMonth)
                return prevMonth..<thisMonth
            }()),
            ("下个月", {
                let thisMonth = today.startOfMonth
                let nextMonth = offset(.month, 1, from: thisMonth)
                let end = offset(.month, 1, from: nextMonth)
                return nextMonth..<end
            }()),
            ("下月", {
                let thisMonth = today.startOfMonth
                let nextMonth = offset(.month, 1, from: thisMonth)
                let end = offset(.month, 1, from: nextMonth)
                return nextMonth..<end
            }()),
            ("今年", {
                let start = today.startOfYear
                let end = offset(.year, 1, from: start)
                return start..<end
            }()),
            ("去年", {
                let thisYear = today.startOfYear
                let prevYear = offset(.year, -1, from: thisYear)
                return prevYear..<thisYear
            }()),
            ("前年", {
                let thisYear = today.startOfYear
                let prevYear = offset(.year, -2, from: thisYear)
                let end = offset(.year, 1, from: prevYear)
                return prevYear..<end
            }()),
            ("明年", {
                let thisYear = today.startOfYear
                let nextYear = offset(.year, 1, from: thisYear)
                let end = offset(.year, 1, from: nextYear)
                return nextYear..<end
            }()),
            ("上半年", {
                let start = today.startOfYear
                let mid = offset(.month, 6, from: start)
                return start..<mid
            }()),
            ("下半年", {
                let start = today.startOfYear
                let mid = offset(.month, 6, from: start)
                let end = offset(.year, 1, from: start)
                return mid..<end
            }()),
            ("Q1", {
                let start = today.startOfYear
                let end = offset(.month, 3, from: start)
                return start..<end
            }()),
            ("Q2", {
                let start = offset(.month, 3, from: today.startOfYear)
                let end = offset(.month, 3, from: start)
                return start..<end
            }()),
            ("Q3", {
                let start = offset(.month, 6, from: today.startOfYear)
                let end = offset(.month, 3, from: start)
                return start..<end
            }()),
            ("Q4", {
                let start = offset(.month, 9, from: today.startOfYear)
                let end = offset(.year, 1, from: today.startOfYear)
                return start..<end
            }()),
            ("一季度", {
                let start = today.startOfYear
                let end = offset(.month, 3, from: start)
                return start..<end
            }()),
            ("二季度", {
                let start = offset(.month, 3, from: today.startOfYear)
                let end = offset(.month, 3, from: start)
                return start..<end
            }()),
            ("三季度", {
                let start = offset(.month, 6, from: today.startOfYear)
                let end = offset(.month, 3, from: start)
                return start..<end
            }()),
            ("四季度", {
                let start = offset(.month, 9, from: today.startOfYear)
                let end = offset(.year, 1, from: today.startOfYear)
                return start..<end
            }()),
            ("第一季度", {
                let start = today.startOfYear
                let end = offset(.month, 3, from: start)
                return start..<end
            }()),
            ("第二季度", {
                let start = offset(.month, 3, from: today.startOfYear)
                let end = offset(.month, 3, from: start)
                return start..<end
            }()),
            ("第三季度", {
                let start = offset(.month, 6, from: today.startOfYear)
                let end = offset(.month, 3, from: start)
                return start..<end
            }()),
            ("第四季度", {
                let start = offset(.month, 9, from: today.startOfYear)
                let end = offset(.year, 1, from: today.startOfYear)
                return start..<end
            }()),
        ]

        // Find the fixed expression that appears earliest in the input
        var best: (keyword: String, range: Range<Date>, position: Int)?
        for (keyword, dateRange) in fixedExpressions {
            if let r = input.range(of: keyword) {
                let pos = input.distance(from: input.startIndex, to: r.lowerBound)
                if let b = best {
                    if pos < b.position { best = (keyword, dateRange, pos) }
                } else {
                    best = (keyword, dateRange, pos)
                }
            }
        }

        if let b = best {
            let newRemaining = input.replacingOccurrences(of: b.keyword, with: "", options: [], range: nil)
            return DateMatch(range: b.range, matched: b.keyword, remaining: newRemaining)
        }

        return DateMatch(range: nil, matched: nil, remaining: input)
    }

    // MARK: - Amount Extraction

    private struct AmountMatch {
        let range: ClosedRange<Decimal>?
        let matched: String?
        let remaining: String
    }

    private static func extractAmount(from input: String) -> AmountMatch {
        // Combined pattern: "大于100" but also "小于50"
        // We handle > and < separately and combine if both present

        var remaining = input
        var lowerBound: Decimal?
        var upperBound: Decimal?
        var matchedParts: [String] = []

        // "大于X" / "超过X" / ">X" / "＞X"
        if let result = matchAmountPattern(in: remaining, prefixes: ["大于", "超过", "不低于", ">", "＞"]) {
            lowerBound = result.value
            matchedParts.append(result.matched)
            remaining = result.remaining
        }

        // "X以上"
        if lowerBound == nil, let result = matchAmountPatternSuffix(in: remaining, suffixes: ["以上", "及以上"]) {
            lowerBound = result.value
            matchedParts.append(result.matched)
            remaining = result.remaining
        }

        // "小于X" / "低于X" / "<X" / "＜X"
        if let result = matchAmountPattern(in: remaining, prefixes: ["小于", "低于", "不超过", "<", "＜"]) {
            upperBound = result.value
            matchedParts.append(result.matched)
            remaining = result.remaining
        }

        // "X以下"
        if upperBound == nil, let result = matchAmountPatternSuffix(in: remaining, suffixes: ["以下", "及以下"]) {
            upperBound = result.value
            matchedParts.append(result.matched)
            remaining = result.remaining
        }

        // "X到Y" / "X-Y" / "X至Y" / "X~Y"
        if lowerBound == nil && upperBound == nil, let result = matchRangePattern(in: remaining) {
            lowerBound = result.lower
            upperBound = result.upper
            matchedParts.append(result.matched)
            remaining = result.remaining
        }

        // "X元" / "X块" — exact amount
        if lowerBound == nil && upperBound == nil, let result = matchExactAmount(in: remaining) {
            lowerBound = result.value
            upperBound = result.value
            matchedParts.append(result.matched)
            remaining = result.remaining
        }

        // Build range
        let amountRange: ClosedRange<Decimal>?
        if let lo = lowerBound, let hi = upperBound {
            amountRange = min(lo, hi)...max(lo, hi)
        } else if let lo = lowerBound {
            amountRange = lo...Decimal.greatestFiniteMagnitude
        } else if let hi = upperBound {
            amountRange = 0...hi
        } else {
            amountRange = nil
        }

        let matched = matchedParts.isEmpty ? nil : matchedParts.joined()

        return AmountMatch(range: amountRange, matched: matched, remaining: remaining)
    }

    private struct AmountPatternResult {
        let value: Decimal
        let matched: String
        let remaining: String
    }

    private static func matchAmountPattern(in input: String, prefixes: [String]) -> AmountPatternResult? {
        for prefix in prefixes {
            let escaped = NSRegularExpression.escapedPattern(for: prefix)
            let pattern = "\(escaped)\\s*(\\d+(?:\\.?\\d*)?)\\s*(?:万|[元块]钱?)?"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) else { continue }
            let numStr = (input as NSString).substring(with: match.range(at: 1))
            guard var value = Decimal(string: numStr) else { continue }
            let fullMatch = match.fullString(in: input)
            // Check for 万 multiplier
            if fullMatch.contains("万") { value *= 10000 }
            let remaining = remove(match, from: input)
            return AmountPatternResult(value: value, matched: fullMatch, remaining: remaining)
        }
        return nil
    }

    private static func matchAmountPatternSuffix(in input: String, suffixes: [String]) -> AmountPatternResult? {
        for suffix in suffixes {
            let escaped = NSRegularExpression.escapedPattern(for: suffix)
            let pattern = "(\\d+(?:\\.?\\d*)?)\\s*(?:万)?\\s*\(escaped)"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) else { continue }
            let numStr = (input as NSString).substring(with: match.range(at: 1))
            guard var value = Decimal(string: numStr) else { continue }
            let fullMatch = match.fullString(in: input)
            if fullMatch.contains("万") { value *= 10000 }
            let remaining = remove(match, from: input)
            return AmountPatternResult(value: value, matched: fullMatch, remaining: remaining)
        }
        return nil
    }

    private static func matchRangePattern(in input: String) -> (lower: Decimal, upper: Decimal, matched: String, remaining: String)? {
        let pattern = "(\\d+(?:\\.?\\d*)?)\\s*(?:万)?\\s*[-到至~]\\s*(\\d+(?:\\.?\\d*)?)\\s*(?:万|[元块]钱?|之间)?"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) else { return nil }
        let num1Str = (input as NSString).substring(with: match.range(at: 1))
        let num2Str = (input as NSString).substring(with: match.range(at: 2))
        guard var v1 = Decimal(string: num1Str), var v2 = Decimal(string: num2Str) else { return nil }
        let fullMatch = match.fullString(in: input)
        // Check if 万 appears before the delimiter
        if let wanRange = input.range(of: "万"),
           let num2Range = Range(match.range(at: 2), in: input),
           wanRange.upperBound <= num2Range.lowerBound {
            // Only first number may have 万 — handled below
        }
        // Simpler: check if 万 is in the matched string
        if fullMatch.contains("万") {
            let beforeDelim = String(fullMatch.prefix { "-到至~".contains($0) == false })
            if beforeDelim.contains("万") { v1 *= 10000 }
            guard let delimIdx = fullMatch.firstIndex(where: { "-到至~".contains($0) }) else { return nil }
            let afterDelim = String(fullMatch.suffix(from: delimIdx))
            if afterDelim.contains("万") { v2 *= 10000 }
        }
        let remaining = remove(match, from: input)
        return (v1, v2, fullMatch, remaining)
    }

    private static func matchExactAmount(in input: String) -> AmountPatternResult? {
        let pattern = "(\\d+(?:\\.?\\d*)?)\\s*(?:万)?\\s*[元块]钱?"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) else { return nil }
        let numStr = (input as NSString).substring(with: match.range(at: 1))
        guard var value = Decimal(string: numStr) else { return nil }
        let fullMatch = match.fullString(in: input)
        if fullMatch.contains("万") { value *= 10000 }
        let remaining = remove(match, from: input)
        return AmountPatternResult(value: value, matched: fullMatch, remaining: remaining)
    }

    // MARK: - Type Extraction

    private struct TypeMatch {
        let type: TransactionType?
        let matched: String?
        let remaining: String
    }

    private static func extractType(from input: String) -> TypeMatch {
        let typeKeywords: [(String, TransactionType)] = [
            ("收入", .income),
            ("支出", .expense),
            ("转账", .transfer),
            ("借贷", .lending),
            ("调整", .adjustment),
        ]

        // Find the last-occurring type keyword
        var best: (keyword: String, type: TransactionType, position: Int)?
        for (keyword, type) in typeKeywords {
            if let r = input.range(of: keyword, options: .backwards) {
                let pos = input.distance(from: input.startIndex, to: r.lowerBound)
                if let b = best {
                    if pos > b.position { best = (keyword, type, pos) }
                } else {
                    best = (keyword, type, pos)
                }
            }
        }

        if let b = best {
            let remaining = input.replacingOccurrences(of: b.keyword, with: "", options: [], range: nil)
            return TypeMatch(type: b.type, matched: b.keyword, remaining: remaining)
        }

        return TypeMatch(type: nil, matched: nil, remaining: input)
    }

    // MARK: - Helpers

    private static let noiseCharacters: Set<Character> = ["的", "了", "吗", "呢", "吧", "啊", "呀", "哦", "嗯", "嘛", "呗", "啦", "在"]

    private static func tokenizeAndJoin(_ input: String) -> String {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = input
        let tokens = tokenizer.tokens(for: input.startIndex..<input.endIndex).map {
            String(input[$0])
        }
        return tokens.joined(separator: " ")
    }

    private static func stripNoise(_ input: String) -> String {
        let filtered = input.filter { !noiseCharacters.contains($0) }
        return filtered.trimmingCharacters(in: .whitespaces)
    }

    private static func remove(_ match: NSTextCheckingResult, from input: String) -> String {
        guard let range = Range(match.range, in: input) else { return input }
        var result = input
        result.removeSubrange(range)
        return result
    }
}

private extension NSTextCheckingResult {
    func fullString(in input: String) -> String {
        guard let range = Range(range, in: input) else { return "" }
        return String(input[range])
    }
}
