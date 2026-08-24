import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum NLQueryParser {

    private static let systemPrompt = """
    You are a financial search query parser. Extract search parameters from Chinese natural language and return ONLY a JSON object. No explanation.

    Current date: \(Date.now.formatted(date: .complete, time: .omitted)), day of week: \(Calendar.current.component(.weekday, from: .now)-1) (1=Monday)

    Return format:
    {"date":"YYYY-MM-DD to YYYY-MM-DD or relative keyword","keyword":"search term","type":"income/expense/transfer/lending or null","amount":"min-max or exact number or null"}

    Rules:
    - "花了/用了/花销/开支/花费/付了/买了/消费" → type:"expense"
    - "赚了/收入/入账/进账/收了/挣了" → type:"income"
    - "转出/转入/转账/转给" → type:"transfer"
    - "借出/借入/借钱/还钱" → type:"lending"
    - "去年" → "2025". "今年" → "2026". "前年" → "2024". "上个月/上月" → last calendar month. "这个月/本月" → current month. "最近N天/周/月/年" → relative range.
    - "在X上/关于X/X方面/X上面" → keyword:X
    - If user asks generally without specific keyword, set keyword:null
    - If no type specified, type:null
    - "多少/多少钱/一共/总共" → just signal aggregate query, no specific amount filter (set amount:null)

    Query:
    """

    // MARK: - Public

    @available(iOS 27.0, *)
    static func parse(_ input: String) async -> ParsedSearchQuery? {
        let model = SystemLanguageModel()
        guard model.isAvailable else { return nil }

        let session = LanguageModelSession(model: model)
        let prompt = systemPrompt + input

        guard let response = try? await session.respond(to: prompt),
              let json = extractJSON(from: response.content) else {
            return nil
        }

        return buildQuery(from: json)
    }

    // MARK: - JSON Extraction

    private static func extractJSON(from text: String) -> [String: String]? {
        // Try to find JSON between { }
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end else { return nil }

        let jsonStr = String(text[start...end])
        guard let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return nil
        }
        return obj
    }

    // MARK: - Build Query

    private static func buildQuery(from json: [String: String]) -> ParsedSearchQuery {
        var query = ParsedSearchQuery()

        // Date
        if let dateStr = json["date"]?.trimmingCharacters(in: .whitespaces),
           !dateStr.isEmpty {
            query.dateRange = parseDateExpression(dateStr)
            query.dateKeyword = dateStr
        }

        // Keyword
        if let kw = json["keyword"]?.trimmingCharacters(in: .whitespaces),
           !kw.isEmpty {
            query.keyword = kw
        }

        // Type
        if let typeStr = json["type"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            switch typeStr {
            case "expense", "支出": query.transactionType = .expense
            case "income", "收入": query.transactionType = .income
            case "transfer", "转账": query.transactionType = .transfer
            case "lending", "借贷": query.transactionType = .lending
            default: break
            }
            query.typeKeyword = json["type"]
        }

        // Amount — only apply if model returned a meaningful number
        if let amountStr = json["amount"]?.trimmingCharacters(in: .whitespaces),
           !amountStr.isEmpty, amountStr != "null" {
            if let range = parseAmountExpression(amountStr),
               // Ignore degenerate ranges (model sometimes returns "0" for "多少钱")
               !(range.lowerBound == 0 && range.upperBound == 0),
               !(range.lowerBound == 0 && range.upperBound == .greatestFiniteMagnitude) {
                query.amountRange = range
                query.amountKeyword = amountStr
            }
        }

        return query
    }

    // MARK: - Date Parsing

    private static func parseDateExpression(_ expr: String) -> Range<Date>? {
        let cal = Calendar.current
        let today = Date.now.startOfDay
        let lower = expr.lowercased()

        // "2025" → whole year
        if let year = Int(expr), (2000...2100).contains(year) {
            guard let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)),
                  let end = cal.date(byAdding: .year, value: 1, to: start) else { return nil }
            return start..<end
        }

        // "2025-01 to 2025-12" or "2025-01-01 to 2025-12-31"
        let datePattern = #/(\d{4})(?:-(\d{1,2}))?(?:-(\d{1,2}))?\s*(?:to|~|到|至)\s*(\d{4})(?:-(\d{1,2}))?(?:-(\d{1,2}))?/#
        if let match = try? datePattern.wholeMatch(in: expr) {
            let y1 = Int(match.1)!, m1 = Int(match.2 ?? "1")!, d1 = Int(match.3 ?? "1")!
            let y2 = Int(match.4)!, m2 = Int(match.5 ?? "12")!, d2 = Int(match.6 ?? "1")!
            var startComp = DateComponents(year: y1, month: m1, day: d1)
            var endComp = DateComponents(year: y2, month: m2, day: d2)
            if match.6 == nil {
                endComp = DateComponents(year: y2, month: m2 + 1, day: 1)
            }
            guard let start = cal.date(from: startComp),
                  let end = cal.date(from: endComp) else { return nil }
            return start..<end
        }

        // "last month", "previous month", "上个月"
        if lower.contains("last month") || lower.contains("previous month") {
            let thisMonth = today.startOfMonth
            let prevMonth = thisMonth.adding(.month, value: -1)
            return prevMonth..<thisMonth
        }

        // "this month", "current month"
        if lower.contains("this month") || lower.contains("current month") {
            let start = today.startOfMonth
            let end = start.adding(.month, value: 1)
            return start..<end
        }

        // "last N days/weeks/months/years"
        if let match = try? /last\s+(\d+)\s+(day|week|month|year)s?/.wholeMatch(in: lower) {
            let n = Int(match.1) ?? 1
            let unit: Calendar.Component = match.2 == "day" ? .day : match.2 == "week" ? .day : .month
            let multiplier: Int = match.2 == "week" ? 7 : 1
            guard let start = cal.date(byAdding: unit, value: -(n * multiplier), to: today) else { return nil }
            return start..<Date().startOfDay.adding(.day, value: 1)
        }

        return nil
    }

    // MARK: - Amount Parsing

    private static func parseAmountExpression(_ expr: String) -> ClosedRange<Decimal>? {
        let lower = expr.lowercased().trimmingCharacters(in: .whitespaces)

        // "100-500" / "100到500" / "100~500"
        if let match = try? /(\d+(?:\.\d+)?)\s*(?:-|到|至|~)\s*(\d+(?:\.\d+)?)/.wholeMatch(in: lower) {
            guard let v1 = Decimal(string: String(match.1)),
                  let v2 = Decimal(string: String(match.2)) else { return nil }
            return min(v1, v2)...max(v1, v2)
        }

        // ">100" / ">=100" / ">100元"
        if let match = try? />=? *(\d+(?:\.\d+)?)/.wholeMatch(in: lower) {
            guard let v = Decimal(string: String(match.1)) else { return nil }
            return v...Decimal.greatestFiniteMagnitude
        }

        // "<100" / "<=100"
        if let match = try? /<=? *(\d+(?:\.\d+)?)/.wholeMatch(in: lower) {
            guard let v = Decimal(string: String(match.1)) else { return nil }
            return 0...v
        }

        // "100万" / "1.5万"
        if let match = try? /(\d+(?:\.\d+)?)\s*万/.wholeMatch(in: lower) {
            guard let v = Decimal(string: String(match.1)) else { return nil }
            let wan = v * 10000
            return wan...wan
        }

        // Exact number "500" / "500元"
        if let match = try? /^(\d+(?:\.\d+)?)/.wholeMatch(in: lower) {
            guard let v = Decimal(string: String(match.1)) else { return nil }
            return v...v
        }

        return nil
    }
}
