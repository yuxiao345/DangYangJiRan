import Foundation
import SwiftData

enum ReportPeriod: Hashable {
    case thisMonth
    case last3Months
    case last6Months
    case lastYear
    case last3Years

    var label: String {
        switch self {
        case .thisMonth: "本月"
        case .last3Months: "近3月"
        case .last6Months: "近6月"
        case .lastYear: "近1年"
        case .last3Years: "近3年"
        }
    }

    var dateRange: Range<Date>? {
        let cal = Calendar.current
        let now = Date()
        let end = cal.date(byAdding: .day, value: 1, to: now) ?? now
        switch self {
        case .thisMonth:
            return now.startOfMonth..<end
        case .last3Months:
            guard let start = cal.date(byAdding: .month, value: -3, to: now)?.startOfMonth else { return nil }
            return start..<end
        case .last6Months:
            guard let start = cal.date(byAdding: .month, value: -6, to: now)?.startOfMonth else { return nil }
            return start..<end
        case .lastYear:
            guard let start = cal.date(byAdding: .year, value: -1, to: now)?.startOfMonth else { return nil }
            return start..<end
        case .last3Years:
            guard let start = cal.date(byAdding: .year, value: -3, to: now)?.startOfYear else { return nil }
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
    let children: [CategoryExpenseItem]
}

struct TrendDataPoint: Identifiable {
    let id = UUID()
    let label: String
    let yearLabel: String?
    let income: Decimal
    let expense: Decimal
}

@MainActor
@Observable
final class ReportViewModel {
    static let uncategorizedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    var selectedPeriod: ReportPeriod = .thisMonth
    var categoryExpenses: [CategoryExpenseItem] = []
    var totalExpense: Decimal = 0
    var selectedCategoryID: UUID?
    var txByCategory: [UUID: [Transaction]] = [:]
    var trendData: [TrendDataPoint] = []

    var displayCategories: [CategoryExpenseItem] {
        guard let id = selectedCategoryID else { return categoryExpenses }
        if let parent = categoryExpenses.first(where: { $0.id == id }), !parent.children.isEmpty {
            return parent.children
        }
        for top in categoryExpenses {
            if let child = top.children.first(where: { $0.id == id }), !child.children.isEmpty {
                return child.children
            }
        }
        return []
    }

    var isShowingTransactions: Bool {
        guard let id = selectedCategoryID else { return false }
        if id == Self.uncategorizedUUID { return true }
        for top in categoryExpenses {
            if top.id == id { return top.children.isEmpty }
            if let child = top.children.first(where: { $0.id == id }) {
                return child.children.isEmpty
            }
        }
        return true
    }

    var displayTitle: String {
        guard let id = selectedCategoryID else { return "支出分类" }
        for top in categoryExpenses {
            if top.id == id { return top.name }
            if let child = top.children.first(where: { $0.id == id }) { return child.name }
        }
        if id == Self.uncategorizedUUID { return "未分类" }
        return "支出分类"
    }

    var displayTotal: Decimal {
        if selectedCategoryID != nil {
            return displayCategories.map(\.amount).reduce(0, +)
        }
        return totalExpense
    }

    var displayTransactions: [Transaction] {
        guard let id = selectedCategoryID else { return [] }
        if id == Self.uncategorizedUUID { return txByCategory[id] ?? [] }
        return txByCategory[id] ?? []
    }

    func load(
        ledger: Ledger,
        transactionService: TransactionServiceProtocol,
        categoryService: CategoryServiceProtocol,
        context: ModelContext
    ) {
        guard let range = selectedPeriod.dateRange else { return }

        let ledgerID = ledger.id
        let startDate = range.lowerBound
        let endDate = range.upperBound
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate {
                $0.ledger?.id == ledgerID &&
                $0.date >= startDate &&
                $0.date < endDate
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let all = (try? context.fetch(descriptor)) ?? []

        let transactions = all.filter { t in
            guard t.type == .expense else { return false }
            guard !t.isSplitParent else { return false }
            guard !t.isReimbursable else { return false }
            return true
        }

        let allCategories = (try? categoryService.fetchAllCategories(for: ledger, type: .expense, context: context)) ?? []
        let categoryLookup = Dictionary(uniqueKeysWithValues: allCategories.map { ($0.id, $0) })

        txByCategory = [:]

        var rootMap: [UUID: (cat: Category, total: Decimal, directAmount: Decimal, children: [UUID: Decimal])] = [:]
        var directTXByRoot: [UUID: [Transaction]] = [:]
        var uncategorizedTotal: Decimal = 0
        var uncategorizedTxs: [Transaction] = []

        for t in transactions {
            guard let cat = t.category else {
                uncategorizedTotal += netAmount(t)
                uncategorizedTxs.append(t)
                continue
            }
            let rootCat = rootCategory(for: cat)
            let amt = netAmount(t)

            var entry = rootMap[rootCat.id] ?? (rootCat, 0, 0, [:])
            entry.total += amt
            if cat.id == rootCat.id {
                entry.directAmount += amt
                directTXByRoot[rootCat.id, default: []].append(t)
            } else {
                entry.children[cat.id, default: 0] += amt
                txByCategory[cat.id, default: []].append(t)
            }
            rootMap[rootCat.id] = entry
        }

        totalExpense = rootMap.values.map(\.total).reduce(0, +) + uncategorizedTotal

        categoryExpenses = rootMap.map { id, entry in
            let parentTotal = entry.total
            var childItems: [CategoryExpenseItem] = []

            if entry.directAmount > 0 {
                let directID = UUID()
                txByCategory[directID] = directTXByRoot[id] ?? []
                childItems.append(CategoryExpenseItem(
                    id: directID,
                    name: "本分类",
                    iconName: entry.cat.iconName,
                    colorHex: entry.cat.colorHex,
                    amount: entry.directAmount,
                    percentage: parentTotal > 0 ? Double(truncating: (entry.directAmount / parentTotal) as NSNumber) : 0,
                    children: []
                ))
            }

            let subItems = entry.children.map { childID, childAmount in
                let childCat = categoryLookup[childID]
                return CategoryExpenseItem(
                    id: childID,
                    name: childCat?.name ?? "未知",
                    iconName: childCat?.iconName ?? "questionmark",
                    colorHex: childCat?.colorHex ?? "#999999",
                    amount: childAmount,
                    percentage: parentTotal > 0 ? Double(truncating: (childAmount / parentTotal) as NSNumber) : 0,
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
                percentage: totalExpense > 0 ? Double(truncating: (entry.total / totalExpense) as NSNumber) : 0,
                children: childItems
            )
        }.sorted { $0.amount > $1.amount }

        if uncategorizedTotal > 0 {
            txByCategory[Self.uncategorizedUUID] = uncategorizedTxs
            let uncategorizedItem = CategoryExpenseItem(
                id: Self.uncategorizedUUID,
                name: "未分类",
                iconName: "questionmark.circle",
                colorHex: "#AAAAAA",
                amount: uncategorizedTotal,
                percentage: totalExpense > 0 ? Double(truncating: (uncategorizedTotal / totalExpense) as NSNumber) : 0,
                children: []
            )
            categoryExpenses.append(uncategorizedItem)
            categoryExpenses.sort { $0.amount > $1.amount }
        }

        if selectedCategoryID != nil, !categoryExpenses.contains(where: { $0.id == selectedCategoryID }) {
            selectedCategoryID = nil
        }
    }

    func loadTrendData(
        ledger: Ledger,
        transactionService: TransactionServiceProtocol,
        context: ModelContext
    ) {
        guard let range = selectedPeriod.dateRange else { return }

        let ledgerID = ledger.id
        let startDate = range.lowerBound
        let endDate = range.upperBound
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate {
                $0.ledger?.id == ledgerID &&
                $0.date >= startDate &&
                $0.date < endDate
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let all = (try? context.fetch(descriptor)) ?? []

        let settlementIDs = Set(all.compactMap(\.reimbursedById))
        let filtered = all.filter { t in
            guard t.type == .expense || t.type == .income else { return false }
            guard !t.isSplitParent else { return false }
            if t.type == .expense, t.isReimbursable { return false }
            if t.type == .income, settlementIDs.contains(t.id) { return false }
            return true
        }

        let cal = Calendar.current

        switch selectedPeriod {
        case .last3Years:
            let monthDF = DateFormatter()
            monthDF.dateFormat = "M月"
            let yearDF = DateFormatter()
            yearDF.dateFormat = "yyyy年"

            var byYearMonth: [String: (yearLabel: String?, monthLabel: String, income: Decimal, expense: Decimal)] = [:]
            var order: [String] = []
            var prevYear: String?

            for t in filtered {
                let yearKey = yearDF.string(from: t.date)
                let monthKey = monthDF.string(from: t.date)
                let compoundKey = "\(yearKey)\(monthKey)"

                if byYearMonth[compoundKey] == nil {
                    order.append(compoundKey)
                    let isNewYear = yearKey != prevYear
                    byYearMonth[compoundKey] = (
                        yearLabel: isNewYear ? yearKey : nil,
                        monthLabel: monthKey,
                        income: 0,
                        expense: 0
                    )
                    prevYear = yearKey
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
                    TrendDataPoint(
                        label: key,
                        yearLabel: v.yearLabel,
                        income: v.income,
                        expense: v.expense
                    )
                }
            }

            if let maxIn = trendData.max(by: { $0.income < $1.income }), maxIn.income > 0 {
                print("[DEBUG] 最大收入: \(maxIn.label) ¥\(maxIn.income)")
            }
            if let maxEx = trendData.max(by: { $0.expense < $1.expense }), maxEx.expense > 0 {
                print("[DEBUG] 最大支出: \(maxEx.label) ¥\(maxEx.expense)")
            }

        default:
            // Use year-qualified keys when the period spans multiple years to avoid merging
            // e.g. May 2025 and May 2026 must be separate bars
            let cal = Calendar.current
            let startYear = cal.component(.year, from: range.lowerBound)
            let endYear = cal.component(.year, from: range.upperBound)
            let useYearPrefix = startYear != endYear

            let monthDF = DateFormatter()
            monthDF.dateFormat = "M月"
            let yearDF = DateFormatter()
            yearDF.dateFormat = "yyyy年"

            var byMonth: [String: (income: Decimal, expense: Decimal)] = [:]
            var monthOrder: [String] = []

            for t in filtered {
                let key = useYearPrefix ? "\(yearDF.string(from: t.date))\(monthDF.string(from: t.date))" : monthDF.string(from: t.date)
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
                    TrendDataPoint(label: key, yearLabel: nil, income: v.income, expense: v.expense)
                }
            }

            if let maxIn = trendData.max(by: { $0.income < $1.income }), maxIn.income > 0 {
                print("[DEBUG] 最大收入: \(maxIn.label) ¥\(maxIn.income)")
            }
            if let maxEx = trendData.max(by: { $0.expense < $1.expense }), maxEx.expense > 0 {
                print("[DEBUG] 最大支出: \(maxEx.label) ¥\(maxEx.expense)")
            }
        }
    }

    // MARK: - Test data seeding (DEBUG only)

    #if DEBUG
    func seedTestData(
        ledger: Ledger,
        context: ModelContext
    ) {
        let ledgerID = ledger.id

        // Category names
        let catNames: [String] = ["三餐", "停车", "娱乐", "物业", "通讯"]
        let catDescriptor = FetchDescriptor<Category>(
            predicate: #Predicate { $0.ledger?.id == ledgerID }
        )
        let allCats = (try? context.fetch(catDescriptor)) ?? []
        let catByName: [String: Category] = Dictionary(uniqueKeysWithValues: allCats.compactMap { c in
            catNames.contains(c.name) ? (c.name, c) : nil
        })
        guard catByName.count == 5 else {
            print("Seed: missing categories, found \(catByName.keys.sorted())")
            return
        }

        // Get 微信支付 account
        let acctDescriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.ledger?.id == ledgerID }
        )
        guard let allAccounts = try? context.fetch(acctDescriptor) else { return }
        guard let account = allAccounts.first(where: { $0.name == "微信支付" }) else {
            print("Seed: 微信支付 account not found")
            return
        }

        let cal = Calendar.current
        guard var date = cal.date(from: DateComponents(year: 2025, month: 1, day: 1)),
              let endDate = cal.date(from: DateComponents(year: 2026, month: 5, day: 1)) else {
            print("Seed: date creation failed")
            return
        }

        var count = 0
        while date < endDate {
            // 3x 餐饮 30 each
            for _ in 0..<3 {
                let t = Transaction(type: .expense, amount: -30, date: date, account: account, category: catByName["三餐"])
                t.ledger = ledger
                context.insert(t)
                count += 1
            }
            // 1x 停车 20
            let p = Transaction(type: .expense, amount: -20, date: date, account: account, category: catByName["停车"])
            p.ledger = ledger
            context.insert(p)
            count += 1

            // Weekly 娱乐 on Sundays
            if cal.component(.weekday, from: date) == 1 {
                let e = Transaction(type: .expense, amount: -100, date: date, account: account, category: catByName["娱乐"])
                e.ledger = ledger
                context.insert(e)
                count += 1
            }

            // Monthly on 1st
            if cal.component(.day, from: date) == 1 {
                let prop = Transaction(type: .expense, amount: -700, date: date, account: account, category: catByName["物业"])
                prop.ledger = ledger
                context.insert(prop)
                count += 1
                let tel = Transaction(type: .expense, amount: -199, date: date, account: account, category: catByName["通讯"])
                tel.ledger = ledger
                context.insert(tel)
                count += 1
            }

            guard let nextDate = cal.date(byAdding: .day, value: 1, to: date) else {
                print("Seed: date iteration failed at \(date)")
                break
            }
            date = nextDate

            // Save in batches
            if count % 200 == 0 {
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
}
