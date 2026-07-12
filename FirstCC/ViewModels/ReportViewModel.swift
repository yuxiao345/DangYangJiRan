import Foundation
@preconcurrency import CoreData

enum ReportPeriod: Hashable {
    case thisMonth
    case last3Months
    case last6Months
    case last12Months
    case last18Months
    case lastYear
    case last2Years
    case last3Years
    case customRange(start: Date, end: Date)

    var label: String {
        switch self {
        case .thisMonth: String(localized: "本月")
        case .last3Months: String(localized: "近3月")
        case .last6Months: String(localized: "近6月")
        case .last12Months: String(localized: "近12月")
        case .last18Months: String(localized: "近18月")
        case .lastYear: String(localized: "近1年")
        case .last2Years: String(localized: "近2年")
        case .last3Years: String(localized: "近3年")
        case .customRange: String(localized: "自定义")
        }
    }

    var dateRange: Range<Date>? {
        let cal = Calendar.current
        let now = Date()
        let todayEnd = cal.date(byAdding: .day, value: 1, to: now) ?? now
        switch self {
        case .thisMonth:
            let endOfMonth = cal.date(byAdding: .month, value: 1, to: now.startOfMonth) ?? now
            return now.startOfMonth..<endOfMonth
        case .last3Months:
            guard let start = cal.date(byAdding: .month, value: -3, to: now)?.startOfMonth else { return nil }
            return start..<todayEnd
        case .last6Months:
            guard let start = cal.date(byAdding: .month, value: -6, to: now)?.startOfMonth else { return nil }
            return start..<todayEnd
        case .last12Months:
            guard let start = cal.date(byAdding: .month, value: -12, to: now)?.startOfMonth else { return nil }
            return start..<todayEnd
        case .last18Months:
            guard let start = cal.date(byAdding: .month, value: -18, to: now)?.startOfMonth else { return nil }
            return start..<todayEnd
        case .lastYear:
            guard let start = cal.date(byAdding: .year, value: -1, to: now)?.startOfMonth else { return nil }
            return start..<todayEnd
        case .last2Years:
            guard let start = cal.date(byAdding: .year, value: -2, to: now)?.startOfMonth else { return nil }
            return start..<todayEnd
        case .last3Years:
            guard let start = cal.date(byAdding: .year, value: -3, to: now)?.startOfYear else { return nil }
            return start..<todayEnd
        case .customRange(let start, let end):
            return start..<end
        }
    }
}

struct CategoryExpenseItem: Identifiable {
    let id: UUID
    let name: String
    let iconName: String
    let colorHex: String
    let amount: Decimal
    let percentage: Double
    let parentID: UUID?
    let children: [CategoryExpenseItem]
}

struct TrendDataPoint: Identifiable {
    let id = UUID()
    let label: String
    let monthLabel: String
    let year: Int?
    let income: Decimal
    let expense: Decimal
}

struct AssetDataPoint: Identifiable {
    let id = UUID()
    let label: String       // "25年6月"
    let yearMonth: String   // "2026-06"
    let totalAssets: Decimal
    let totalLiabilities: Decimal
    var netWorth: Decimal { totalAssets - totalLiabilities }
}

/// 每日支出趋势数据点
struct DailySpendingPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let amount: Decimal
}

// MARK: - Asset Allocation

enum AllocationFilter: String, CaseIterable {
    case all
    case assets
    case liabilities

    var label: String {
        switch self {
        case .all: String(localized: "全部")
        case .assets: String(localized: "资产")
        case .liabilities: String(localized: "负债")
        }
    }
}

struct AccountAllocationItem: Identifiable {
    let id: UUID
    let name: String
    let accountType: AccountType
    let iconName: String
    let balance: Decimal
    let percentage: Double
    let isLiability: Bool
}

/// 消耗速率分桶（固定12柱，粒度自适应）
struct BurnRateBucket: Identifiable {
    let id = UUID()
    let index: Int
    let startDate: Date
    let endDate: Date
    let amount: Decimal
    let maxAmount: Decimal
}

struct BudgetItemData: Identifiable {
    let id: UUID
    let name: String
    let colorHex: String
    let period: BudgetPeriod
    let budgetAmount: Decimal
    let spentAmount: Decimal
    /// 原始每期金额（用于展示参照）
    let periodAmount: Decimal
    /// 全周期数
    let periodCount: Double
    /// 是否为累计数据（非本维度原生周期项）
    let isCumulative: Bool
    /// 是否为子限额（其分类的祖先也有预算）
    let isSubLimit: Bool
    /// 本维度时间进度
    let timeProgress: Double
    let elapsedDays: Int
    let totalPeriodDays: Int

    var remaining: Decimal { budgetAmount - spentAmount }
    var percentage: Double {
        budgetAmount > 0 ? min(1.0, Double(truncating: (spentAmount / budgetAmount) as NSNumber)) : 0
    }
    var isOverBudget: Bool { spentAmount > budgetAmount }

    var remainingDays: Int { max(0, totalPeriodDays - elapsedDays) }
    var isOnTrack: Bool { percentage <= timeProgress }

    var dailyAvailable: Double {
        guard remainingDays > 0 else { return 0 }
        return Double(truncating: ((budgetAmount - spentAmount) / Decimal(remainingDays)) as NSNumber)
    }

    var paceLabel: String {
        if spentAmount == 0 { return String(localized: "尚未开始花费") }
        let diff = percentage - timeProgress
        if abs(diff) < 0.02 { return String(localized: "节奏持平") }
        return diff > 0 ? String(localized: "超前花费") : String(localized: "落后于时间")
    }

    var suggestionText: String {
        if remainingDays <= 0 { return String(localized: "预算周期已结束") }

        // 已超支：无论怎么控制都无法挽回
        if isOverBudget || dailyAvailable < 0 {
            return String(localized: "预算已超支，请调整预算")
        }

        // 超前花费：剩余日均预算低于原计划的 50%，大概率控制不住
        if !isOnTrack {
            let avgDailyBudget = totalPeriodDays > 0 ? budgetAmount / Decimal(totalPeriodDays) : 0
            let halfAvg = Double(truncating: (avgDailyBudget / 2) as NSNumber)
            if dailyAvailable < halfAvg {
                return String(localized: "预计会超支，请调整预算并严格控制支出")
            }
        }

        let n = Int(dailyAvailable)
        if n < 1 { return String(localized: "建议平均日花费控制在 ¥1 以内") }
        return String(localized: "建议平均日花费控制在 ¥\(n) 以内")
    }
}

/// 整体预算全景汇总（仅 .overall 维度使用）
struct BudgetOverviewSummary {
    let totalBudget: Decimal
    let totalSpent: Decimal
    let timeProgress: Double
    let budgetProgress: Double
    let dailyBudget: Decimal
    let dailyAvailable: Double
    let totalDays: Int
    let elapsedDays: Int
    let remainingDays: Int

    var remainingBudget: Decimal { totalBudget - totalSpent }
    var isOnTrack: Bool { budgetProgress <= timeProgress }

    var paceLabel: String {
        if totalSpent == 0 { return String(localized: "尚未开始花费") }
        let diff = budgetProgress - timeProgress
        if abs(diff) < 0.02 { return String(localized: "节奏持平") }
        return diff > 0 ? String(localized: "超前花费") : String(localized: "落后于时间")
    }

    var suggestionText: String {
        if remainingDays <= 0 { return String(localized: "预算周期已结束") }

        // 已超支
        if totalSpent > totalBudget || dailyAvailable < 0 {
            return String(localized: "预算已超支，请调整预算")
        }

        // 超前花费：剩余日均预算低于原计划 50%
        if !isOnTrack {
            let halfAvg = Double(truncating: (dailyBudget / 2) as NSNumber)
            if dailyAvailable < halfAvg {
                return String(localized: "预计会超支，请调整预算并严格控制支出")
            }
        }

        if dailyAvailable < 1 && dailyAvailable > 0 { return String(localized: "建议平均日花费控制在 ¥1 以内") }
        return String(localized: "建议平均日花费控制在 ¥\(Int(dailyAvailable)) 以内")
    }
}

enum BudgetViewDimension: CaseIterable {
    case overall
    case yearly
    case quarterly
    case monthly
    case weekly

    var label: String {
        switch self {
        case .overall:   String(localized: "整体预算")
        case .yearly:    String(localized: "年度")
        case .quarterly: String(localized: "季度")
        case .monthly:   String(localized: "月度")
        case .weekly:    String(localized: "每周")
        }
    }

    /// 本维度对应的「原生」周期
    var nativePeriod: BudgetPeriod? {
        switch self {
        case .overall:   nil
        case .yearly:    .yearly
        case .quarterly: .quarterly
        case .monthly:   .monthly
        case .weekly:    .weekly
        }
    }

    /// 当前维度的时间窗口（用于计算支出）
    func dateRange(bookStart: Date) -> ClosedRange<Date> {
        let cal = Calendar.current
        let today = Date()
        let start: Date
        switch self {
        case .overall:
            start = cal.startOfDay(for: bookStart)
        case .yearly:
            start = cal.date(from: cal.dateComponents([.year], from: today)) ?? today
        case .quarterly:
            let month = cal.component(.month, from: today)
            let qStart = ((month - 1) / 3) * 3 + 1
            start = cal.date(from: DateComponents(year: cal.component(.year, from: today), month: qStart, day: 1)) ?? today
        case .monthly:
            start = cal.date(from: cal.dateComponents([.year, .month], from: today)) ?? today
        case .weekly:
            start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today
        }
        return cal.startOfDay(for: start)...max(cal.startOfDay(for: start), today)
    }

    /// 计算本维度的时间进度（所有预算项共享）
    func timeProgress(bookStart: Date, bookEnd: Date) -> (progress: Double, elapsed: Int, total: Int) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start: Date
        let end: Date
        switch self {
        case .overall:
            start = cal.startOfDay(for: bookStart)
            end = max(cal.startOfDay(for: bookEnd), today)
        case .yearly:
            start = cal.date(from: cal.dateComponents([.year], from: today)) ?? today
            end = cal.date(byAdding: DateComponents(year: 1, day: -1), to: start) ?? today
        case .quarterly:
            let month = cal.component(.month, from: today)
            let qStart = ((month - 1) / 3) * 3 + 1
            start = cal.date(from: DateComponents(year: cal.component(.year, from: today), month: qStart, day: 1)) ?? today
            end = cal.date(byAdding: DateComponents(month: 3, day: -1), to: start) ?? today
        case .monthly:
            start = cal.date(from: cal.dateComponents([.year, .month], from: today)) ?? today
            end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? today
        case .weekly:
            start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today
            end = cal.date(byAdding: .day, value: 6, to: start) ?? today
        }
        let total = max(1, (cal.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
        let elapsed = min(max(0, cal.dateComponents([.day], from: start, to: today).day ?? 0), total)
        return (Double(elapsed) / Double(total), elapsed, total)
    }

    /// 是否需要按周期分组显示
    var groupByPeriod: Bool { self == .overall }

    /// 消耗速率图的时间轴起点：取预算开始日期与维度周期起点的较晚者
    func burnRateStart(bookStart: Date) -> Date {
        let cal = Calendar.current
        let today = Date()
        let dimStart: Date
        switch self {
        case .overall:
            dimStart = bookStart
        case .yearly:
            dimStart = cal.date(from: cal.dateComponents([.year], from: today)) ?? today
        case .quarterly:
            let month = cal.component(.month, from: today)
            let qStart = ((month - 1) / 3) * 3 + 1
            dimStart = cal.date(from: DateComponents(year: cal.component(.year, from: today), month: qStart, day: 1)) ?? today
        case .monthly:
            dimStart = cal.date(from: cal.dateComponents([.year, .month], from: today)) ?? today
        case .weekly:
            dimStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today
        }
        return max(cal.startOfDay(for: bookStart), cal.startOfDay(for: dimStart))
    }
}

@MainActor
@Observable
final class ReportViewModel {
    static let uncategorizedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    var selectedPeriod: ReportPeriod = .thisMonth
    var categoryExpenses: [CategoryExpenseItem] = []
    var totalExpense: Decimal = 0
    var categoryIncomes: [CategoryExpenseItem] = []
    var totalIncome: Decimal = 0
    var selectedCategoryID: UUID?
    var txByCategory: [UUID: [Transaction]] = [:]
    var txByIncomeCategory: [UUID: [Transaction]] = [:]
    var trendData: [TrendDataPoint] = []
    var assetData: [AssetDataPoint] = []
    var budgetItems: [BudgetItemData] = []
    var budgetBooks: [BudgetBook] = []
    var selectedBudgetBookID: UUID?
    var budgetViewDimension: BudgetViewDimension = .overall
    var budgetBookName: String { budgetBooks.first(where: { $0.id == selectedBudgetBookID })?.name ?? "" }
    var dailyTrendByCategory: [UUID: [DailySpendingPoint]] = [:]
    var burnRateData: [BurnRateBucket] = []
    var allocationData: [AccountAllocationItem] = []
    var totalAllocationNetWorth: Decimal = 0
    var allocationFilter: AllocationFilter = .all
    var categoryType: TransactionType = .expense

    private var currentCategories: [CategoryExpenseItem] {
        categoryType == .expense ? categoryExpenses : categoryIncomes
    }

    var displayCategories: [CategoryExpenseItem] {
        let source = currentCategories
        guard let id = selectedCategoryID else { return source }
        if let parent = source.first(where: { $0.id == id }), !parent.children.isEmpty {
            return parent.children
        }
        for top in source {
            if let child = top.children.first(where: { $0.id == id }), !child.children.isEmpty {
                return child.children
            }
        }
        return []
    }

    var isShowingTransactions: Bool {
        guard let id = selectedCategoryID else { return false }
        if id == Self.uncategorizedUUID { return true }
        for top in currentCategories {
            if top.id == id { return top.children.isEmpty }
            if let child = top.children.first(where: { $0.id == id }) {
                return child.children.isEmpty
            }
        }
        return true
    }

    var displayTitle: String {
        guard let id = selectedCategoryID else {
            return categoryType == .expense ? String(localized: "支出分类") : String(localized: "收入分类")
        }
        for top in currentCategories {
            if top.id == id { return top.name }
            if let child = top.children.first(where: { $0.id == id }) { return child.name }
        }
        if id == Self.uncategorizedUUID { return String(localized: "未分类") }
        return categoryType == .expense ? String(localized: "支出分类") : String(localized: "收入分类")
    }

    var displayTotal: Decimal {
        if isShowingTransactions {
            return displayTransactions.reduce(0) { $0 + (categoryType == .expense ? netAmount($1) : abs(ledgerAmount($1))) }
        }
        if selectedCategoryID != nil {
            return displayCategories.map(\.amount).reduce(0, +)
        }
        return categoryType == .expense ? totalExpense : totalIncome
    }

    var displayTransactions: [Transaction] {
        guard let id = selectedCategoryID else { return [] }
        let txMap = categoryType == .expense ? txByCategory : txByIncomeCategory
        return txMap[id] ?? []
    }

    func load(
        ledger: Ledger,
        transactionService: TransactionServiceProtocol,
        categoryService: CategoryServiceProtocol,
        context: NSManagedObjectContext
    ) {
        guard let range = selectedPeriod.dateRange else { return }

        let ledgerID = ledger.id
        let startDate = range.lowerBound
        let endDate = range.upperBound
        let fetch = NSFetchRequest<Transaction>(entityName: "Transaction")
        fetch.predicate = NSPredicate(format: "ledger.id == %@ AND date >= %@ AND date < %@", ledgerID as CVarArg, startDate as CVarArg, endDate as CVarArg)
        fetch.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        let all = (try? context.fetch(fetch)) ?? []

        // Load expense categories
        let expenseResult = buildCategoryItems(
            from: all,
            type: .expense,
            categoryService: categoryService,
            ledger: ledger,
            context: context
        )
        categoryExpenses = expenseResult.items
        totalExpense = expenseResult.total
        txByCategory = expenseResult.txMap

        // Load income categories
        let incomeResult = buildCategoryItems(
            from: all,
            type: .income,
            categoryService: categoryService,
            ledger: ledger,
            context: context
        )
        categoryIncomes = incomeResult.items
        totalIncome = incomeResult.total
        txByIncomeCategory = incomeResult.txMap

        // Validate selection
        let activeCategories = categoryType == .expense ? categoryExpenses : categoryIncomes
        if selectedCategoryID != nil, !activeCategories.contains(where: { $0.id == selectedCategoryID }) {
            selectedCategoryID = nil
        }
    }

    private typealias CategoryBuildResult = (items: [CategoryExpenseItem], total: Decimal, txMap: [UUID: [Transaction]])

    private func buildCategoryItems(
        from allTransactions: [Transaction],
        type: TransactionType,
        categoryService: CategoryServiceProtocol,
        ledger: Ledger,
        context: NSManagedObjectContext
    ) -> CategoryBuildResult {
        let transactions = allTransactions
            .excludingReimbursementTransactions()
            .filter { t in
                guard t.type == type else { return false }
                guard !t.isSplitParent else { return false }
                return true
            }

        let allCategories = (try? categoryService.fetchAllCategories(for: ledger, type: type, context: context)) ?? []
        let categoryLookup = Dictionary(uniqueKeysWithValues: allCategories.map { ($0.id, $0) })

        var txMap: [UUID: [Transaction]] = [:]
        var rootMap: [UUID: (cat: Category, total: Decimal, directAmount: Decimal, children: [UUID: Decimal])] = [:]
        var directTXByRoot: [UUID: [Transaction]] = [:]
        var uncategorizedTotal: Decimal = 0
        var uncategorizedTxs: [Transaction] = []

        for t in transactions {
            guard let cat = t.category else {
                uncategorizedTotal += type == .expense ? netAmount(t) : abs(ledgerAmount(t))
                uncategorizedTxs.append(t)
                continue
            }
            let rootCat = rootCategory(for: cat)
            let amt = type == .expense ? netAmount(t) : abs(ledgerAmount(t))

            var entry = rootMap[rootCat.id] ?? (rootCat, 0, 0, [:])
            entry.total += amt
            if cat.id == rootCat.id {
                entry.directAmount += amt
                directTXByRoot[rootCat.id, default: []].append(t)
            } else {
                entry.children[cat.id, default: 0] += amt
                txMap[cat.id, default: []].append(t)
            }
            rootMap[rootCat.id] = entry
        }

        let total = rootMap.values.map(\.total).reduce(0, +) + uncategorizedTotal

        var items = rootMap.map { id, entry in
            let parentTotal = entry.total
            var childItems: [CategoryExpenseItem] = []

            if entry.directAmount > 0 {
                let directID = UUID()
                txMap[directID] = directTXByRoot[id] ?? []
                childItems.append(CategoryExpenseItem(
                    id: directID,
                    name: String(localized: "本分类"),
                    iconName: entry.cat.iconName,
                    colorHex: entry.cat.colorHex,
                    amount: entry.directAmount,
                    percentage: parentTotal > 0 ? Double(truncating: (entry.directAmount / parentTotal) as NSNumber) : 0,
                    parentID: id,
                    children: []
                ))
            }

            let subItems = entry.children.map { childID, childAmount in
                let childCat = categoryLookup[childID]
                return CategoryExpenseItem(
                    id: childID,
                    name: childCat?.name ?? String(localized: "未知"),
                    iconName: childCat?.iconName ?? "questionmark",
                    colorHex: childCat?.colorHex ?? "#999999",
                    amount: childAmount,
                    percentage: parentTotal > 0 ? Double(truncating: (childAmount / parentTotal) as NSNumber) : 0,
                    parentID: id,
                    children: []
                )
            }.sorted { $0.amount > $1.amount }

            childItems.append(contentsOf: subItems)

            return CategoryExpenseItem(
                id: id,
                name: entry.cat.name,
                iconName: entry.cat.iconName,
                colorHex: entry.cat.colorHex,
                amount: entry.total,
                percentage: total > 0 ? Double(truncating: (entry.total / total) as NSNumber) : 0,
                parentID: nil,
                children: childItems
            )
        }.sorted { $0.amount > $1.amount }

        if uncategorizedTotal > 0 {
            txMap[Self.uncategorizedUUID] = uncategorizedTxs
            let uncategorizedItem = CategoryExpenseItem(
                id: Self.uncategorizedUUID,
                name: String(localized: "未分类"),
                iconName: "questionmark.circle",
                colorHex: "#AAAAAA",
                amount: uncategorizedTotal,
                percentage: total > 0 ? Double(truncating: (uncategorizedTotal / total) as NSNumber) : 0,
                parentID: nil,
                children: []
            )
            items.append(uncategorizedItem)
            items.sort { $0.amount > $1.amount }
        }

        return (items, total, txMap)
    }

    func loadTrendData(
        ledger: Ledger,
        transactionService: TransactionServiceProtocol,
        context: NSManagedObjectContext
    ) {
        guard let range = selectedPeriod.dateRange else { return }

        let ledgerID = ledger.id
        let startDate = range.lowerBound
        let endDate = range.upperBound
        let fetch = NSFetchRequest<Transaction>(entityName: "Transaction")
        fetch.predicate = NSPredicate(format: "ledger.id == %@ AND date >= %@ AND date < %@", ledgerID as CVarArg, startDate as CVarArg, endDate as CVarArg)
        let all = (try? context.fetch(fetch)) ?? []

        let filtered = all
            .excludingReimbursementTransactions()
            .filter { t in
                guard t.type == .expense || t.type == .income else { return false }
                guard !t.isSplitParent else { return false }
                return true
            }

        switch selectedPeriod {
        case .last3Years:
            let monthFmt = Date.FormatStyle.dateTime.month(.abbreviated)
            let yearFmt = Date.FormatStyle.dateTime.year(.twoDigits)

            var byYearMonth: [String: (monthLabel: String, income: Decimal, expense: Decimal)] = [:]
            var order: [String] = []

            for t in filtered {
                let yearKey = t.date.formatted(yearFmt)
                let monthKey = t.date.formatted(monthFmt)
                let compoundKey = "\(yearKey)\(monthKey)"

                if byYearMonth[compoundKey] == nil {
                    order.append(compoundKey)
                    byYearMonth[compoundKey] = (
                        monthLabel: monthKey,
                        income: 0,
                        expense: 0
                    )
                }
                guard var entry = byYearMonth[compoundKey] else { continue }
                if t.type == .income {
                    entry.income += ledgerAmount(t)
                } else {
                    entry.expense += netAmount(t)
                }
                byYearMonth[compoundKey] = entry
            }
            trendData = order.compactMap { key in
                byYearMonth[key].map { v in
                    let (year, _) = parseYearMonth(from: key)
                    return TrendDataPoint(
                        label: key,
                        monthLabel: v.monthLabel,
                        year: year,
                        income: v.income,
                        expense: v.expense
                    )
                }
            }

        default:
            // Use year-qualified keys when the period spans multiple years to avoid merging
            // e.g. May 2025 and May 2026 must be separate bars
            let cal = Calendar.current
            let startYear = cal.component(.year, from: range.lowerBound)
            let endYear = cal.component(.year, from: range.upperBound)
            let useYearPrefix = startYear != endYear

            let monthFmt = Date.FormatStyle.dateTime.month(.abbreviated)
            let yearFmt = Date.FormatStyle.dateTime.year(.twoDigits)

            var byMonth: [String: (income: Decimal, expense: Decimal)] = [:]
            var monthOrder: [String] = []

            for t in filtered {
                let key = useYearPrefix ? "\(t.date.formatted(yearFmt))\(t.date.formatted(monthFmt))" : t.date.formatted(monthFmt)
                if byMonth[key] == nil {
                    monthOrder.append(key)
                    byMonth[key] = (0, 0)
                }
                guard var entry = byMonth[key] else { continue }
                if t.type == .income {
                    entry.income += ledgerAmount(t)
                } else {
                    entry.expense += netAmount(t)
                }
                byMonth[key] = entry
            }
            trendData = monthOrder.compactMap { key in
                byMonth[key].map { v in
                    let (year, monthLabel) = parseYearMonth(from: key)
                    return TrendDataPoint(
                        label: key,
                        monthLabel: monthLabel,
                        year: year,
                        income: v.income,
                        expense: v.expense
                    )
                }
            }

        }
    }

    // MARK: - Assets Data

    func loadAssetsData(
        ledger: Ledger,
        accountService: AccountServiceProtocol,
        context: NSManagedObjectContext
    ) {
        guard let range = selectedPeriod.dateRange else { return }
        let accounts = (try? accountService.fetchAccounts(for: ledger, includeArchived: false, context: context)) ?? []
        guard !accounts.isEmpty else { assetData = []; return }

        let cal = Calendar.current
        var current = cal.date(from: cal.dateComponents([.year, .month], from: range.lowerBound)) ?? range.lowerBound
        let endDate = range.upperBound

        // Pre-fetch all transactions to avoid per-month fetches
        let ledgerID = ledger.id
        let fetch = NSFetchRequest<Transaction>(entityName: "Transaction")
        fetch.predicate = NSPredicate(format: "ledger.id == %@ AND date < %@", ledgerID as CVarArg, endDate as CVarArg)
        let allTx = (try? context.fetch(fetch)) ?? []

        // Group transactions by account
        var txByAccount: [UUID: [Transaction]] = [:]
        for t in allTx {
            guard let accountID = t.account?.id else { continue }
            txByAccount[accountID, default: []].append(t)
        }

        var dataPoints: [AssetDataPoint] = []

        while current < endDate {
            guard let monthEnd = cal.date(byAdding: .month, value: 1, to: current) else { break }

            var totalAssets: Decimal = 0
            var totalLiabilities: Decimal = 0

            for account in accounts {
                let balance = computeBalance(
                    account: account,
                    upTo: monthEnd,
                    transactions: txByAccount[account.id] ?? []
                )
                if account.type == .creditCard || account.type == .loan {
                    totalLiabilities += abs(balance)
                } else {
                    totalAssets += balance
                }
            }

            let year = cal.component(.year, from: current)
            let month = cal.component(.month, from: current)
            let label = String(format: "%02d年%d月", year % 100, month)
            let yearMonth = String(format: "%04d-%02d", year, month)
            dataPoints.append(AssetDataPoint(
                label: label,
                yearMonth: yearMonth,
                totalAssets: totalAssets,
                totalLiabilities: totalLiabilities
            ))

            current = monthEnd
        }

        assetData = dataPoints
    }

    /// Compute account balance up to a specific date: initial + sum of amounts before cutoff
    private func computeBalance(account: Account, upTo cutoff: Date, transactions: [Transaction]) -> Decimal {
        var balance = account.initialBalance
        for t in transactions where t.date < cutoff {
            if account.type == .lending,
               let dir = t.lendingDirection,
               dir == .borrowIn,
               t.lendingStatus == .pending {
                balance += -ledgerAmount(t)
            } else {
                balance += ledgerAmount(t)
            }
        }
        return balance
    }

    // MARK: - Overall Budget Helpers

    /// 预算全景汇总（所有维度通用）
    var overviewSummary: BudgetOverviewSummary? {
        guard let bookID = selectedBudgetBookID,
              let book = budgetBooks.first(where: { $0.id == bookID }) else { return nil }

        let dim = budgetViewDimension
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.startOfDay(for: dim.burnRateStart(bookStart: book.startDate))

        // 计算维度的结束日期
        let dimEnd: Date
        switch dim {
        case .overall:
            dimEnd = max(cal.startOfDay(for: book.endDate), today)
        case .yearly:
            let yearStart = cal.date(from: cal.dateComponents([.year], from: today)) ?? today
            dimEnd = cal.date(byAdding: DateComponents(year: 1, day: -1), to: yearStart) ?? today
        case .quarterly:
            let month = cal.component(.month, from: today)
            let qStart = ((month - 1) / 3) * 3 + 1
            let qs = cal.date(from: DateComponents(year: cal.component(.year, from: today), month: qStart, day: 1)) ?? today
            dimEnd = cal.date(byAdding: DateComponents(month: 3, day: -1), to: qs) ?? today
        case .monthly:
            let ms = cal.date(from: cal.dateComponents([.year, .month], from: today)) ?? today
            dimEnd = cal.date(byAdding: DateComponents(month: 1, day: -1), to: ms) ?? today
        case .weekly:
            let ws = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today
            dimEnd = cal.date(byAdding: .day, value: 6, to: ws) ?? today
        }
        let end = max(dimEnd, today)

        let totalDays = max(1, (cal.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
        let elapsed = min(max(0, cal.dateComponents([.day], from: start, to: today).day ?? 0), totalDays)
        let remainingDays = max(0, totalDays - elapsed)

        let totalBudget = budgetItems.filter { !$0.isSubLimit }.reduce(Decimal(0)) { $0 + $1.budgetAmount }
        let totalSpent = budgetItems.filter { !$0.isSubLimit }.reduce(Decimal(0)) { $0 + $1.spentAmount }

        let timeProgress = totalDays > 0 ? Double(elapsed) / Double(totalDays) : 0
        let budgetProgress = totalBudget > 0 ? Double(truncating: (totalSpent / totalBudget) as NSNumber) : 0

        let dailyBudget = totalDays > 0 ? totalBudget / Decimal(totalDays) : 0
        let dailyAvailable: Double = remainingDays > 0
            ? Double(truncating: ((totalBudget - totalSpent) / Decimal(remainingDays)) as NSNumber)
            : 0

        return BudgetOverviewSummary(
            totalBudget: totalBudget, totalSpent: totalSpent,
            timeProgress: timeProgress, budgetProgress: budgetProgress,
            dailyBudget: dailyBudget, dailyAvailable: dailyAvailable,
            totalDays: totalDays, elapsedDays: elapsed, remainingDays: remainingDays
        )
    }

    // MARK: - Budget Data

    func loadBudgetData(
        ledger: Ledger,
        budgetService: BudgetServiceProtocol,
        context: NSManagedObjectContext
    ) {
        let books = (try? budgetService.fetchBooks(for: ledger, context: context)) ?? []
        budgetBooks = books

        // Select active book, or first book, or previously selected
        if selectedBudgetBookID == nil || !books.contains(where: { $0.id == selectedBudgetBookID }) {
            selectedBudgetBookID = books.first(where: { $0.isActive })?.id ?? books.first?.id
        }

        guard let bookID = selectedBudgetBookID,
              let book = books.first(where: { $0.id == bookID }) else {
            budgetItems = []
            return
        }

        let items = (try? budgetService.fetchItems(for: book, context: context)) ?? []
        let dim = budgetViewDimension
        let dimRange = dim.dateRange(bookStart: book.startDate)
        let categorySpending = budgetService.categorySpending(in: dimRange, for: book, context: context)
        let tp = dim.timeProgress(bookStart: book.startDate, bookEnd: book.endDate)

        // 预计算：哪些分类有预算（用于判断子限额），仅含活跃项，与 rootBudgetItems 保持一致
        let budgetedCatIDs = Set(items.filter { $0.isActive }.compactMap { $0.category?.id })

        budgetItems = items.compactMap { item in
            guard let cat = item.category else { return nil }
            // 如果该分类的任何祖先也有预算，则本项是子限额
            let isSubLimit = cat.allAncestorIDs.contains(where: { budgetedCatIDs.contains($0) })
            let period = item.period

            guard let target = dim.nativePeriod else {
                // 整体：periodCount × amount + 累计支出
                let totalBudget = item.totalBudget
                let cumulativeSpent = abs(budgetService.cumulativeSpending(for: item, context: context))
                return BudgetItemData(
                    id: item.id, name: cat.name, colorHex: cat.colorHex ?? "#999999",
                    period: period, budgetAmount: totalBudget, spentAmount: cumulativeSpent,
                    periodAmount: item.amount, periodCount: Double(item.periodCount),
                    isCumulative: false, isSubLimit: isSubLimit,
                    timeProgress: tp.progress, elapsedDays: tp.elapsed, totalPeriodDays: tp.total
                )
            }

            let spent = categorySpending[cat.id] ?? 0

            // 过滤：仅显示原生周期项 + 更小周期项的累计
            let isNative = period == target
            let isSmaller = period < target

            guard isNative || isSmaller else { return nil }

            let budget = isNative
                ? item.amount
                : item.amount.normalized(from: period, to: target)

            return BudgetItemData(
                id: item.id, name: cat.name, colorHex: cat.colorHex ?? "#999999",
                period: period, budgetAmount: budget, spentAmount: abs(spent),
                periodAmount: item.amount, periodCount: 1,
                isCumulative: !isNative, isSubLimit: isSubLimit,
                timeProgress: tp.progress, elapsedDays: tp.elapsed, totalPeriodDays: tp.total
            )
        }.sorted {
            // Sort by overspend ratio; zero-budget items (unplanned spending) surface at top
            let r0 = $0.budgetAmount > 0 ? $0.spentAmount / $0.budgetAmount : Decimal.greatestFiniteMagnitude
            let r1 = $1.budgetAmount > 0 ? $1.spentAmount / $1.budgetAmount : Decimal.greatestFiniteMagnitude
            if r0 != r1 { return r0 > r1 }
            return $0.spentAmount > $1.spentAmount
        }

        // 加载每日支出趋势（维度感知的时间轴起点）
        let trendStart = Calendar.current.startOfDay(for: dim.burnRateStart(bookStart: book.startDate))
        let trendEnd = Calendar.current.startOfDay(for: Date())

        // Per-category trend: only meaningful when matchBudgetItems is true
        if book.matchBudgetItems {
            var trendByCat: [UUID: [DailySpendingPoint]] = [:]
            for item in items {
                guard let cat = item.category else { continue }
                trendByCat[item.id] = budgetService.dailySpending(in: trendStart...trendEnd, categoryID: cat.id, ledgerID: ledger.id, context: context)
            }
            dailyTrendByCategory = trendByCat
        } else {
            dailyTrendByCategory = [:]
        }

        // 消耗速率：matchBudgetItems 决定范围
        let burnPoints: [DailySpendingPoint]
        if book.matchBudgetItems {
            let budgetedCatIDs = Set(items.filter { $0.isActive }.compactMap { $0.category?.id })
            var dailyAggregate: [Date: Decimal] = [:]
            for item in items {
                guard let cat = item.category else { continue }
                // 找出该分类下已有独立预算的后代，作为排除项传给 dailySpending
                let childBudgetedIDs = cat.allDescendantIDs.filter { budgetedCatIDs.contains($0) }
                let points = budgetService.dailySpending(in: trendStart...trendEnd, categoryID: cat.id, excludeCategoryIDs: childBudgetedIDs, ledgerID: ledger.id, context: context)
                for point in points {
                    dailyAggregate[point.date, default: 0] += point.amount
                }
            }
            burnPoints = dailyAggregate.map { DailySpendingPoint(date: $0.key, amount: $0.value) }
                .sorted { $0.date < $1.date }
        } else {
            burnPoints = budgetService.dailySpending(in: trendStart...trendEnd, categoryID: nil, ledgerID: ledger.id, context: context)
        }

        let totalDays = max(1, Calendar.current.dateComponents([.day], from: trendStart, to: trendEnd).day ?? 0)
        let bucketDays = max(1, totalDays / 24)
        var buckets: [BurnRateBucket] = []
        let cal = Calendar.current
        for i in 0..<24 {
            let bucketStart = cal.date(byAdding: .day, value: i * bucketDays, to: trendStart) ?? trendStart
            let bucketEnd = min(cal.date(byAdding: .day, value: bucketDays - 1, to: bucketStart) ?? bucketStart, trendEnd)
            var sum: Decimal = 0
            for point in burnPoints {
                if point.date >= bucketStart && point.date <= bucketEnd { sum += point.amount }
            }
            buckets.append(BurnRateBucket(index: i, startDate: bucketStart, endDate: bucketEnd, amount: sum, maxAmount: 0))
        }
        let maxAmt = buckets.map(\.amount).max() ?? 1
        burnRateData = buckets.map { b in
            BurnRateBucket(index: b.index, startDate: b.startDate, endDate: b.endDate, amount: b.amount, maxAmount: maxAmt)
        }
    }


// MARK: - Test data seeding (DEBUG only)

    // MARK: - Asset Allocation

    /// Loads ALL non-archived accounts regardless of `allocationFilter`.
    /// Filtering is a view-level concern — the full dataset is always available
    /// so the "全部" tab can show assets-only in the donut while listing all accounts.
    func loadAllocationData(
        ledger: Ledger,
        accountService: AccountServiceProtocol,
        context: NSManagedObjectContext
    ) {
        guard let accounts = try? accountService.fetchAccounts(for: ledger, includeArchived: false, context: context) else {
            allocationData = []
            totalAllocationNetWorth = 0
            return
        }

        let accountsWithBalance: [(Account, Decimal)] = accounts.map { account in
            let bal = accountService.calculateBalance(for: account, context: context)
            return (account, bal)
        }

        // Exclude zero-balance accounts
        let nonZero = accountsWithBalance.filter { $0.1 != 0 }
        let totalPositive = nonZero.filter { $0.1 > 0 }.reduce(Decimal.zero) { $0 + $1.1 }
        let totalNegative = nonZero.filter { $0.1 < 0 }.reduce(Decimal.zero) { $0 + abs($1.1) }
        totalAllocationNetWorth = totalPositive - totalNegative

        // Sort by absolute balance descending, assets first then liabilities
        let sorted = nonZero.sorted { abs($0.1) > abs($1.1) }
        let totalAbs = sorted.reduce(Decimal.zero) { $0 + abs($1.1) }

        allocationData = sorted.map { account, bal in
            AccountAllocationItem(
                id: account.id,
                name: account.name,
                accountType: account.type,
                iconName: account.iconName ?? account.type.systemIcon,
                balance: bal,
                percentage: totalAbs > 0 ? Double(truncating: (abs(bal) / totalAbs) as NSNumber) : 0,
                isLiability: bal < 0
            )
        }
    }

    #if DEBUG
    /// Self-contained: creates categories + account if missing, then generates realistic transaction data.
    func seedTestData(
        ledger: Ledger,
        context: NSManagedObjectContext
    ) {
        let ledgerID = ledger.id
        let cal = Calendar.current

        // ── Ensure categories ──
        let catDefs: [(name: String, icon: String, hex: String, children: [(String, String, String)])] = [
            ("餐饮", "fork.knife", "#FF6B6B", [("三餐", "takeoutbag", "#FF8E8E"), ("外卖", "bicycle", "#FFA5A5")]),
            ("交通", "car", "#4ECDC4", [("停车", "parkingsign", "#6EE7DE"), ("打车", "car.2", "#45B7AA")]),
            ("购物", "bag", "#FFD93D", [("日用品", "basket", "#FFE566"), ("服饰", "tshirt", "#FFCC00")]),
            ("娱乐", "gamecontroller", "#6C5CE7", [("电影", "film", "#8B7FEA"), ("游戏", "dpad", "#5A4BD1")]),
            ("居住", "house", "#A8E6CF", [("物业", "building.2", "#BFF5DF"), ("水电", "bolt", "#8FD5B5")]),
            ("通讯", "phone", "#74B9FF", [("话费", "antenna.radiowaves.left.and.right", "#8ECAFF"), ("宽带", "wifi", "#5AA8E7")]),
            ("医疗", "cross.case", "#FF8A80", []),
            ("教育", "book", "#B388FF", []),
        ]

        let catFetch = NSFetchRequest<Category>(entityName: "Category")
        catFetch.predicate = NSPredicate(format: "ledger.id == %@", ledgerID as CVarArg)
        var allCats = (try? context.fetch(catFetch)) ?? []
        var catByName = Dictionary(uniqueKeysWithValues: allCats.map { ($0.name, $0) })

        for def in catDefs {
            let parent: Category
            if let existing = catByName[def.name] {
                parent = existing
            } else {
                parent = Category(name: def.name, iconName: def.icon, colorHex: def.hex, type: .expense, context: context)
                parent.ledger = ledger
                allCats.append(parent)
                catByName[def.name] = parent
            }
            for childDef in def.children {
                if catByName[childDef.0] == nil {
                    let child = Category(name: childDef.0, iconName: childDef.1, colorHex: childDef.2, type: .expense, context: context)
                    child.ledger = ledger
                    child.parent = parent
                    allCats.append(child)
                    catByName[childDef.0] = child
                }
            }
        }
        try? context.save()

        // ── Ensure account ──
        let acctFetch = NSFetchRequest<Account>(entityName: "Account")
        acctFetch.predicate = NSPredicate(format: "ledger.id == %@", ledgerID as CVarArg)
        let allAccounts = (try? context.fetch(acctFetch)) ?? []
        let account: Account
        if let existing = allAccounts.first(where: { $0.name == "微信支付" }) {
            account = existing
        } else {
            account = Account(name: "微信支付", currencyCode: ledger.defaultCurrencyCode, type: .eWallet, context: context)
            account.ledger = ledger
            try? context.save()
        }

        // ── Generate 18 months of transactions ──
        guard var date = cal.date(from: DateComponents(year: 2025, month: 1, day: 1)),
              let endDate = cal.date(from: DateComponents(year: 2026, month: 7, day: 1)) else {
            print("Seed: date creation failed")
            return
        }

        var count = 0
        while date < endDate {
            let dow = cal.component(.weekday, from: date)
            let dom = cal.component(.day, from: date)

            // Daily: 三餐 35±10
            let meals = catByName["三餐"]!
            for _ in 0..<Int.random(in: 2...4) {
                let t = Transaction(type: .expense, amount: Decimal(-35 + Int.random(in: -10...15)), date: date, account: account, category: meals, context: context)
                t.ledger = ledger; count += 1
            }
            // Daily: 交通 (parking or taxi)
            if Int.random(in: 1...10) <= 7 {
                let transportCat = Bool.random() ? catByName["停车"]! : catByName["打车"]!
                let t = Transaction(type: .expense, amount: Decimal(-15 + Int.random(in: -5...25)), date: date, account: account, category: transportCat, context: context)
                t.ledger = ledger; count += 1
            }
            // 2-3x/week: 外卖
            if Int.random(in: 1...10) <= 4 {
                let t = Transaction(type: .expense, amount: Decimal(-25 + Int.random(in: -10...20)), date: date, account: account, category: catByName["外卖"]!, context: context)
                t.ledger = ledger; count += 1
            }
            // Weekend: 娱乐 boost
            if dow == 1 || dow == 7 {
                for _ in 0..<Int.random(in: 1...3) {
                    let entCat = Bool.random() ? catByName["电影"]! : catByName["游戏"]!
                    let t = Transaction(type: .expense, amount: Decimal(-40 + Int.random(in: -20...80)), date: date, account: account, category: entCat, context: context)
                    t.ledger = ledger; count += 1
                }
            }
            // Twice a week: 购物
            if Int.random(in: 1...10) <= 3 {
                let shopCat = Bool.random() ? catByName["日用品"]! : catByName["服饰"]!
                let t = Transaction(type: .expense, amount: Decimal(-50 + Int.random(in: -30...150)), date: date, account: account, category: shopCat, context: context)
                t.ledger = ledger; count += 1
            }
            // Monthly 1st: 物业, 通讯, 话费, 宽带
            if dom == 1 {
                for catName in ["物业", "通讯", "话费", "宽带"] {
                    let cat = catByName[catName]!
                    let amt: Int = catName == "物业" ? -700 + Int.random(in: -100...100) : -150 + Int.random(in: -30...30)
                    let t = Transaction(type: .expense, amount: Decimal(amt), date: date, account: account, category: cat, context: context)
                    t.ledger = ledger; count += 1
                }
            }
            // Monthly 5th: 工资 (income!)
            if dom == 5 {
                let t = Transaction(type: .income, amount: Decimal(12000 + Int.random(in: -2000...3000)), date: date, account: account, category: nil, context: context)
                t.ledger = ledger; count += 1
                // Side income sometimes
                if Int.random(in: 1...10) <= 3 {
                    let t2 = Transaction(type: .income, amount: Decimal(1500 + Int.random(in: -500...2000)), date: date, account: account, category: nil, context: context)
                    t2.ledger = ledger; count += 1
                }
            }
            // Occasional: 医疗, 教育
            if dom == 15 && Int.random(in: 1...10) <= 3 {
                let cat = catByName[Int.random(in: 1...10) <= 5 ? "医疗" : "教育"]!
                let t = Transaction(type: .expense, amount: Decimal(-200 + Int.random(in: -300...500)), date: date, account: account, category: cat, context: context)
                t.ledger = ledger; count += 1
            }

            guard let nextDate = cal.date(byAdding: .day, value: 1, to: date) else { break }
            date = nextDate

            if count % 500 == 0 {
                try? context.save()
                print("Seed: \(count) transactions...")
            }
        }
        try? context.save()
        print("Seed complete: \(count) transactions")
    }
    #endif

    func selectCategory(_ id: UUID?) {
        if selectedCategoryID == id {
            selectedCategoryID = nil
        } else {
            selectedCategoryID = id
        }
    }

    func goBack() {
        guard let id = selectedCategoryID else { return }
        selectedCategoryID = findItem(id: id)?.parentID
    }

    private func findItem(id: UUID) -> CategoryExpenseItem? {
        for top in categoryExpenses {
            if top.id == id { return top }
            for child in top.children {
                if child.id == id { return child }
                for grandchild in child.children {
                    if grandchild.id == id { return grandchild }
                }
            }
        }
        return nil
    }

    /// Amount in ledger's default currency (converted if cross-currency)
    private func ledgerAmount(_ t: Transaction) -> Decimal {
        t.convertedAmount ?? t.amount
    }

    /// Net amount for expense aggregation: positive for regular, negative for refunds
    private func netAmount(_ t: Transaction) -> Decimal {
        let base = ledgerAmount(t)
        return t.refundGroupId != nil ? -abs(base) : abs(base)
    }

    private func rootCategory(for cat: Category) -> Category {
        var current = cat
        while let p = current.parent {
            current = p
        }
        return current
    }

    /// Parse compound key into (year, monthLabel). E.g. "24年6月" → (2024, "6月"), "6月" → (nil, "6月")
    private func parseYearMonth(from key: String) -> (year: Int?, monthLabel: String) {
        guard let nianIdx = key.firstIndex(of: "年") else {
            return (nil, key)
        }
        let yearStr = String(key[..<nianIdx])
        let monthStr = String(key[key.index(after: nianIdx)...])
        guard let yy = Int(yearStr) else { return (nil, key) }
        let year = yy >= 100 ? yy : 2000 + yy
        return (year, monthStr)
    }
}
