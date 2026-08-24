import AppIntents
import CoreData

// MARK: - AppEntity Conformance

// MARK: Ledger

struct LedgerEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "账本")

    let id: UUID
    let name: String

    static var defaultQuery = LedgerEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct LedgerEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [LedgerEntity] {
        guard let container = AppContainer.shared else { return [] }
        let context = container.viewContext
        let request = NSFetchRequest<Ledger>(entityName: "Ledger")
        request.predicate = NSPredicate(format: "id IN %@", identifiers)
        let results = try context.fetch(request)
        return results.map { LedgerEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities(phase: EntityQueryPhase) async throws -> [LedgerEntity] {
        guard let container = AppContainer.shared else { return [] }
        let context = container.viewContext
        let request = NSFetchRequest<Ledger>(entityName: "Ledger")
        request.fetchLimit = 10
        let results = try context.fetch(request)
        return results.map { LedgerEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: Account

struct AccountEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "账户")

    let id: UUID
    let name: String
    let accountType: String

    static var defaultQuery = AccountEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(accountType)")
    }
}

struct AccountEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [AccountEntity] {
        guard let container = AppContainer.shared else { return [] }
        let context = container.viewContext
        let request = NSFetchRequest<Account>(entityName: "Account")
        request.predicate = NSPredicate(format: "id IN %@ AND isArchived == NO", identifiers)
        let results = try context.fetch(request)
        return results.map { AccountEntity(id: $0.id, name: $0.name, accountType: $0.typeDisplayName) }
    }

    func suggestedEntities(phase: EntityQueryPhase) async throws -> [AccountEntity] {
        guard let container = AppContainer.shared else { return [] }
        let context = container.viewContext
        let request = NSFetchRequest<Account>(entityName: "Account")
        request.predicate = NSPredicate(format: "isArchived == NO")
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        request.fetchLimit = 10
        let results = try context.fetch(request)
        return results.map { AccountEntity(id: $0.id, name: $0.name, accountType: $0.typeDisplayName) }
    }
}

// MARK: Category

struct CategoryEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "分类")

    let id: UUID
    let name: String
    let iconName: String

    static var defaultQuery = CategoryEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: iconName))
    }
}

struct CategoryEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [CategoryEntity] {
        guard let container = AppContainer.shared else { return [] }
        let context = container.viewContext
        let request = NSFetchRequest<Category>(entityName: "Category")
        request.predicate = NSPredicate(format: "id IN %@ AND isHidden == NO", identifiers)
        let results = try context.fetch(request)
        return results.map { CategoryEntity(id: $0.id, name: $0.name, iconName: $0.iconName) }
    }

    func suggestedEntities(phase: EntityQueryPhase) async throws -> [CategoryEntity] {
        guard let container = AppContainer.shared else { return [] }
        let context = container.viewContext
        let request = NSFetchRequest<Category>(entityName: "Category")
        request.predicate = NSPredicate(format: "isHidden == NO")
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        request.fetchLimit = 20
        let results = try context.fetch(request)
        return results.map { CategoryEntity(id: $0.id, name: $0.name, iconName: $0.iconName) }
    }
}

// MARK: Member

struct MemberEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "成员")

    let id: UUID
    let name: String

    static var defaultQuery = MemberEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct MemberEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [MemberEntity] {
        guard let container = AppContainer.shared else { return [] }
        let context = container.viewContext
        let request = NSFetchRequest<Member>(entityName: "Member")
        request.predicate = NSPredicate(format: "id IN %@ AND isActive == YES", identifiers)
        let results = try context.fetch(request)
        return results.map { MemberEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities(phase: EntityQueryPhase) async throws -> [MemberEntity] {
        guard let container = AppContainer.shared else { return [] }
        let context = container.viewContext
        let request = NSFetchRequest<Member>(entityName: "Member")
        request.predicate = NSPredicate(format: "isActive == YES")
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        request.fetchLimit = 20
        let results = try context.fetch(request)
        return results.map { MemberEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: Merchant

struct MerchantEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "商户")

    let id: UUID
    let name: String

    static var defaultQuery = MerchantEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct MerchantEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [MerchantEntity] {
        guard let container = AppContainer.shared else { return [] }
        let context = container.viewContext
        let request = NSFetchRequest<Merchant>(entityName: "Merchant")
        request.predicate = NSPredicate(format: "id IN %@ AND isActive == YES", identifiers)
        let results = try context.fetch(request)
        return results.map { MerchantEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities(phase: EntityQueryPhase) async throws -> [MerchantEntity] {
        guard let container = AppContainer.shared else { return [] }
        let context = container.viewContext
        let request = NSFetchRequest<Merchant>(entityName: "Merchant")
        request.predicate = NSPredicate(format: "isActive == YES")
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        request.fetchLimit = 20
        let results = try context.fetch(request)
        return results.map { MerchantEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: Project

struct ProjectEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "项目")

    let id: UUID
    let name: String

    static var defaultQuery = ProjectEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ProjectEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [ProjectEntity] {
        guard let container = AppContainer.shared else { return [] }
        let context = container.viewContext
        let request = NSFetchRequest<Project>(entityName: "Project")
        request.predicate = NSPredicate(format: "id IN %@ AND isActive == YES", identifiers)
        let results = try context.fetch(request)
        return results.map { ProjectEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities(phase: EntityQueryPhase) async throws -> [ProjectEntity] {
        guard let container = AppContainer.shared else { return [] }
        let context = container.viewContext
        let request = NSFetchRequest<Project>(entityName: "Project")
        request.predicate = NSPredicate(format: "isActive == YES")
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        request.fetchLimit = 20
        let results = try context.fetch(request)
        return results.map { ProjectEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: Transaction (Read-only)

struct TransactionEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "交易")

    let id: UUID
    let amount: Decimal
    let date: Date
    let type: String
    let note: String?

    static var defaultQuery = TransactionEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        let sign = amount < 0 ? "-" : "+"
        let absAmount = abs(amount)
        return DisplayRepresentation(
            title: "\(type) \(sign)\(absAmount)",
            subtitle: "\(note ?? "")"
        )
    }
}

struct TransactionEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [TransactionEntity] {
        guard let container = AppContainer.shared else { return [] }
        let context = container.viewContext
        let request = NSFetchRequest<Transaction>(entityName: "Transaction")
        request.predicate = NSPredicate(format: "id IN %@", identifiers)
        let results = try context.fetch(request)
        return results.map { t in
            TransactionEntity(
                id: t.id,
                amount: t.amount,
                date: t.date,
                type: t.type == .expense ? "支出" : "收入",
                note: t.note
            )
        }
    }

    func suggestedEntities(phase: EntityQueryPhase) async throws -> [TransactionEntity] {
        // Transactions are usually looked up by ID, not suggested by name
        return []
    }
}

// MARK: - Intents

struct AddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "记一笔支出"
    static var description = IntentDescription("在钱伲中记录一笔支出")

    @Parameter(title: "金额")
    var amount: Decimal

    @Parameter(title: "账户")
    var account: AccountEntity

    @Parameter(title: "分类")
    var category: CategoryEntity?

    @Parameter(title: "成员")
    var member: MemberEntity?

    @Parameter(title: "商户")
    var merchant: MerchantEntity?

    @Parameter(title: "项目")
    var project: ProjectEntity?

    @Parameter(title: "备注")
    var note: String?

    @Parameter(title: "日期", default: Date())
    var date: Date

    @Dependency(AppContainer.self) private var container: AppContainer

    static var parameterSummary: some ParameterSummary {
        Summary("记 \(\.$amount) 元，账户 \(\.$account)") {
            \.$category
            \.$member
            \.$merchant
            \.$project
            \.$note
            \.$date
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let ledger = container.currentLedger else {
            return .result(dialog: "没有打开的账本，请在钱伲中先打开一个账本")
        }

        let context = container.viewContext

        // Resolve CoreData objects from AppEntity IDs
        let accountObject = try resolveAccount(account, context: context)
        let categoryObject = category.flatMap { try? resolveCategory($0, context: context) }
        let memberObject = member.flatMap { try? resolveMember($0, context: context) }
        let merchantObject = merchant.flatMap { try? resolveMerchant($0, context: context) }
        let projectObject = project.flatMap { try? resolveProject($0, context: context) }

        let transaction = Transaction(
            type: .expense,
            amount: -abs(amount),
            currencyCode: ledger.defaultCurrencyCode,
            note: note,
            date: date,
            account: accountObject,
            category: categoryObject,
            member: memberObject,
            merchant: merchantObject,
            project: projectObject,
            context: context
        )
        transaction.ledger = ledger

        try container.transactionService.createTransaction(transaction, ledger: ledger, context: context)

        return .result(dialog: "已记录 \(amount) 元支出")
    }

    @MainActor
    private func resolveAccount(_ entity: AccountEntity, context: NSManagedObjectContext) throws -> Account {
        let request = NSFetchRequest<Account>(entityName: "Account")
        request.predicate = NSPredicate(format: "id == %@", entity.id as CVarArg)
        request.fetchLimit = 1
        guard let account = try context.fetch(request).first else {
            throw IntentError.entityNotFound("账户不存在")
        }
        return account
    }

    @MainActor
    private func resolveCategory(_ entity: CategoryEntity, context: NSManagedObjectContext) throws -> Category {
        let request = NSFetchRequest<Category>(entityName: "Category")
        request.predicate = NSPredicate(format: "id == %@", entity.id as CVarArg)
        request.fetchLimit = 1
        guard let category = try context.fetch(request).first else {
            throw IntentError.entityNotFound("分类不存在")
        }
        return category
    }

    @MainActor
    private func resolveMember(_ entity: MemberEntity, context: NSManagedObjectContext) throws -> Member {
        let request = NSFetchRequest<Member>(entityName: "Member")
        request.predicate = NSPredicate(format: "id == %@", entity.id as CVarArg)
        request.fetchLimit = 1
        guard let member = try context.fetch(request).first else {
            throw IntentError.entityNotFound("成员不存在")
        }
        return member
    }

    @MainActor
    private func resolveMerchant(_ entity: MerchantEntity, context: NSManagedObjectContext) throws -> Merchant {
        let request = NSFetchRequest<Merchant>(entityName: "Merchant")
        request.predicate = NSPredicate(format: "id == %@", entity.id as CVarArg)
        request.fetchLimit = 1
        guard let merchant = try context.fetch(request).first else {
            throw IntentError.entityNotFound("商户不存在")
        }
        return merchant
    }

    @MainActor
    private func resolveProject(_ entity: ProjectEntity, context: NSManagedObjectContext) throws -> Project {
        let request = NSFetchRequest<Project>(entityName: "Project")
        request.predicate = NSPredicate(format: "id == %@", entity.id as CVarArg)
        request.fetchLimit = 1
        guard let project = try context.fetch(request).first else {
            throw IntentError.entityNotFound("项目不存在")
        }
        return project
    }
}

enum IntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case entityNotFound(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .entityNotFound(let message):
            return LocalizedStringResource(stringLiteral: message)
        }
    }
}

struct QuerySpendingIntent: AppIntent {
    static var title: LocalizedStringResource = "查询支出"
    static var description = IntentDescription("查询指定时间范围内的支出总额")

    @Parameter(title: "开始日期")
    var startDate: Date?

    @Parameter(title: "结束日期")
    var endDate: Date?

    @Parameter(title: "分类")
    var category: CategoryEntity?

    @Dependency(AppContainer.self) private var container: AppContainer

    static var parameterSummary: some ParameterSummary {
        Summary("查询支出") {
            \.$startDate
            \.$endDate
            \.$category
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let ledger = container.currentLedger else {
            return .result(dialog: "没有打开的账本，请在钱伲中先打开一个账本")
        }

        let context = container.viewContext

        // Infer date range: use provided dates or default to current month
        let (range, dateDescription): (ClosedRange<Date>, String) = resolveDateRange()

        if let cat = category {
            // Category-specific spending: compute via categorySpending
            let allSpending = try container.budgetService.categorySpending(
                in: range, for: ledger.budgetBooks.first { $0.isActive } ?? ledger.budgetBooks.first!,
                context: context
            )
            let catTotal = allSpending[cat.id] ?? 0
            return .result(dialog: "\(dateDescription)，分类「\(cat.name)」支出 \(catTotal) 元")
        } else {
            let total = try container.budgetService.totalExpense(in: range, ledger: ledger, context: context)
            return .result(dialog: "\(dateDescription)，总支出 \(total) 元")
        }
    }

    @MainActor
    private func resolveDateRange() -> (ClosedRange<Date>, String) {
        let calendar = Calendar.current
        let now = Date.now

        if let start = startDate, let end = endDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "M月d日"
            let desc = "\(formatter.string(from: start))到\(formatter.string(from: end))"
            return (start...end, desc)
        }

        // Default to current month
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!
        return (startOfMonth...endOfMonth, "本月")
    }
}

struct QueryOverspentIntent: AppIntent {
    static var title: LocalizedStringResource = "查询超支项目"
    static var description = IntentDescription("查询本月或本预算周期内哪些分类超支了")

    @Dependency(AppContainer.self) private var container: AppContainer

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let ledger = container.currentLedger else {
            return .result(dialog: "没有打开的账本，请在钱伲中先打开一个账本")
        }

        let context = container.viewContext

        // Fetch all budget books for this ledger
        let books: [BudgetBook]
        do {
            books = try container.budgetService.fetchBooks(for: ledger, context: context)
        } catch {
            return .result(dialog: "读取预算数据失败")
        }

        var overspent: [(categoryName: String, spent: Decimal, budget: Decimal)] = []

        for book in books where book.isActive {
            let items: [BudgetItem]
            do {
                items = try container.budgetService.fetchItems(for: book, context: context)
            } catch {
                continue
            }

            for item in items where item.isActive {
                let spent = container.budgetService.currentPeriodSpending(for: item, context: context)
                let budget = item.amount
                if budget > 0 && spent > budget {
                    let categoryName = item.category?.name ?? "未分类"
                    overspent.append((categoryName: categoryName, spent: spent, budget: budget))
                }
            }
        }

        if overspent.isEmpty {
            return .result(dialog: "本月没有分类超支，继续保持！")
        } else {
            let lines = overspent.map { "\($0.categoryName) 已花 \($0.spent) 元，预算 \($0.budget) 元" }
            return .result(dialog: "以下分类已超支：\(lines.joined(separator: "；"))")
        }
    }
}

// MARK: - AppShortcuts

struct QianeyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "记一笔 \(.applicationName) 支出",
                "在 \(.applicationName) 记一笔支出",
                "帮我在 \(.applicationName) 记一笔"
            ],
            shortTitle: "记支出",
            systemImageName: "arrow.up.circle"
        )
        AppShortcut(
            intent: QuerySpendingIntent(),
            phrases: [
                "花了多少 in \(.applicationName)",
                "查询 \(.applicationName) 支出",
                "\(.applicationName) 本月花了多少"
            ],
            shortTitle: "查支出",
            systemImageName: "chart.pie"
        )
        AppShortcut(
            intent: QueryOverspentIntent(),
            phrases: [
                "\(.applicationName) 哪些超支了",
                "查询 \(.applicationName) 超支"
            ],
            shortTitle: "查超支",
            systemImageName: "exclamationmark.triangle"
        )
    }
}
