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
        case .last12Months:
            guard let start = cal.date(byAdding: .month, value: -12, to: now)?.startOfMonth else { return nil }
            return start..<end
        case .last18Months:
            guard let start = cal.date(byAdding: .month, value: -18, to: now)?.startOfMonth else { return nil }
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
                percentage: totalExpense > 0 ? Double(truncating: (entry.total / totalExpense) as NSNumber) : 0,
                parentID: nil,
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
                parentID: nil,
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

    // MARK: - Test data seeding (DEBUG only)

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
