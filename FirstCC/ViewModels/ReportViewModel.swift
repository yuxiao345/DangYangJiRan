import Foundation
@preconcurrency import CoreData

enum ReportPeriod: Hashable {
    case thisMonth
    case last3Months
    case last6Months
    case lastYear
    case last2Years
    case last3Years

    var label: String {
        switch self {
        case .thisMonth: String(localized: "本月")
        case .last3Months: String(localized: "近3月")
        case .last6Months: String(localized: "近6月")
        case .lastYear: String(localized: "近1年")
        case .last2Years: String(localized: "近2年")
        case .last3Years: String(localized: "近3年")
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
        case .last2Years:
            guard let start = cal.date(byAdding: .year, value: -2, to: now)?.startOfMonth else { return nil }
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
        guard let id = selectedCategoryID else { return String(localized: "支出分类") }
        for top in categoryExpenses {
            if top.id == id { return top.name }
            if let child = top.children.first(where: { $0.id == id }) { return child.name }
        }
        if id == Self.uncategorizedUUID { return String(localized: "未分类") }
        return String(localized: "支出分类")
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
        context: NSManagedObjectContext
    ) {
        guard let range = selectedPeriod.dateRange else { return }

        let ledgerID = ledger.id
        let startDate = range.lowerBound
        let endDate = range.upperBound
        let fetch = NSFetchRequest<Transaction>(entityName: "Transaction")
        fetch.predicate = NSPredicate(format: "ledger.id == %@ AND date >= %@ AND date < %@", ledgerID as CVarArg, startDate as CVarArg, endDate as CVarArg)
        fetch.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        let all = (try? context.fetch(fetch)) ?? []

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
            let monthFmt = Date.FormatStyle.dateTime.month(.abbreviated)
            let yearFmt = Date.FormatStyle.dateTime.year(.twoDigits)

            var byYearMonth: [String: (yearLabel: String?, monthLabel: String, income: Decimal, expense: Decimal)] = [:]
            var order: [String] = []
            var prevYear: String?

            for t in filtered {
                let yearKey = t.date.formatted(yearFmt)
                let monthKey = t.date.formatted(monthFmt)
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
            }
            if let maxEx = trendData.max(by: { $0.expense < $1.expense }), maxEx.expense > 0 {
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
                    TrendDataPoint(label: key, yearLabel: nil, income: v.income, expense: v.expense)
                }
            }

            if let maxIn = trendData.max(by: { $0.income < $1.income }), maxIn.income > 0 {
            }
            if let maxEx = trendData.max(by: { $0.expense < $1.expense }), maxEx.expense > 0 {
            }
        }
    }

    // MARK: - Test data seeding (DEBUG only)

    #if DEBUG
    func seedTestData(
        ledger: Ledger,
        context: NSManagedObjectContext
    ) {
        let ledgerID = ledger.id

        // Category names
        let catNames: [String] = ["三餐", "停车", "娱乐", "物业", "通讯"]
        let catFetch = NSFetchRequest<Category>(entityName: "Category")
        catFetch.predicate = NSPredicate(format: "ledger.id == %@", ledgerID as CVarArg)
        let allCats = (try? context.fetch(catFetch)) ?? []
        let catByName: [String: Category] = Dictionary(uniqueKeysWithValues: allCats.compactMap { c in
            catNames.contains(c.name) ? (c.name, c) : nil
        })
        guard catByName.count == 5 else {
            print("Seed: missing categories, found \(catByName.keys.sorted())")
            return
        }

        // Get 微信支付 account
        let acctFetch = NSFetchRequest<Account>(entityName: "Account")
        acctFetch.predicate = NSPredicate(format: "ledger.id == %@", ledgerID as CVarArg)
        guard let allAccounts = try? context.fetch(acctFetch) else { return }
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
                let t = Transaction(type: .expense, amount: -30, date: date, account: account, category: catByName["三餐"], context: context)
                t.ledger = ledger
                count += 1
            }
            // 1x 停车 20
            let p = Transaction(type: .expense, amount: -20, date: date, account: account, category: catByName["停车"], context: context)
            p.ledger = ledger
            count += 1

            // Weekly 娱乐 on Sundays
            if cal.component(.weekday, from: date) == 1 {
                let e = Transaction(type: .expense, amount: -100, date: date, account: account, category: catByName["娱乐"], context: context)
                e.ledger = ledger
                count += 1
            }

            // Monthly on 1st
            if cal.component(.day, from: date) == 1 {
                let prop = Transaction(type: .expense, amount: -700, date: date, account: account, category: catByName["物业"], context: context)
                prop.ledger = ledger
                count += 1
                let tel = Transaction(type: .expense, amount: -199, date: date, account: account, category: catByName["通讯"], context: context)
                tel.ledger = ledger
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

    func goBack() {
        guard let id = selectedCategoryID else { return }
        // If current selection is a child of a top-level category, go back to parent
        for top in categoryExpenses {
            if top.children.contains(where: { $0.id == id }) {
                selectedCategoryID = top.id
                return
            }
        }
        // Already at top level, go to root
        selectedCategoryID = nil
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
