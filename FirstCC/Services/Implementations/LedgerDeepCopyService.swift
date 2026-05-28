import Foundation
@preconcurrency import CoreData

/// Two-pass deep copy: Pass 1 copies all scalar values into new objects.
/// Pass 2 re-wires relationships using the UUID→NSManagedObject mapping table.
/// User entities (CKShare participants) are intentionally excluded — the
/// cloned ledger is a local-only copy.
@MainActor
enum LedgerDeepCopyService {

    /// Returns a new Ledger that is a local-only clone of the source.
    /// All child entities are recursively copied; isShared is set to false.
    static func deepCopy(_ source: Ledger, into context: NSManagedObjectContext) throws -> Ledger {
        var map: [UUID: NSManagedObject] = [:]
        let fetcher = EntityFetcher(ledger: source)

        // ── Pass 1: Create new entities ──────────────────────────────

        let newLedger = copyLedger(source, into: context, map: &map)

        for m in fetcher.members {
            _ = copyMember(m, into: context, map: &map)
        }
        for m in fetcher.merchants {
            _ = copyMerchant(m, into: context, map: &map)
        }
        for p in fetcher.projects {
            _ = copyProject(p, into: context, map: &map)
        }
        for a in fetcher.accounts {
            _ = copyAccount(a, into: context, map: &map)
        }
        for c in fetcher.allCategories {
            _ = copyCategory(c, into: context, map: &map)
        }
        for t in fetcher.allTemplates {
            _ = copyTemplate(t, into: context, map: &map)
        }
        for r in fetcher.recurringRules {
            _ = copyRecurringRule(r, into: context, map: &map)
        }
        for b in fetcher.budgetBooks {
            _ = copyBudgetBook(b, into: context, map: &map)
        }
        for s in fetcher.splitGroups {
            _ = copySplitGroup(s, into: context, map: &map)
        }
        for t in fetcher.allTransactions {
            _ = copyTransaction(t, into: context, map: &map)
        }
        // Credit card statements via accounts
        for stmt in fetcher.creditCardStatements {
            _ = copyCreditCardStatement(stmt, into: context, map: &map)
        }

        // ── Pass 2: Re-wire relationships ────────────────────────────

        rewireLedger(newLedger, source: source, map: map, fetcher: fetcher, context: context)

        for m in fetcher.members {
            rewireMember(m, map: map)
        }
        for m in fetcher.merchants {
            rewireMerchant(m, map: map)
        }
        for p in fetcher.projects {
            rewireProject(p, map: map)
        }
        for a in fetcher.accounts {
            rewireAccount(a, map: map)
        }
        for c in fetcher.allCategories {
            rewireCategory(c, map: map)
        }
        for t in fetcher.allTemplates {
            rewireTemplate(t, map: map)
        }
        for r in fetcher.recurringRules {
            rewireRecurringRule(r, map: map)
        }
        for b in fetcher.budgetBooks {
            rewireBudgetBook(b, map: map)
        }
        for s in fetcher.splitGroups {
            rewireSplitGroup(s, map: map)
        }
        for t in fetcher.allTransactions {
            rewireTransaction(t, map: map)
        }
        for stmt in fetcher.creditCardStatements {
            rewireCreditCardStatement(stmt, map: map)
        }

        // Save once at the end so the whole graph is consistent
        if context.hasChanges {
            try context.save()
        }
        return newLedger
    }

    // MARK: - Pass 1 helpers: copy scalar values

    private static func copyLedger(_ src: Ledger, into ctx: NSManagedObjectContext,
                                   map: inout [UUID: NSManagedObject]) -> Ledger {
        let n = Ledger(context: ctx)
        n.id = UUID()  // new UUID to avoid ambiguity with source ledger
        n.name = src.name + " (副本)"
        n.iconName = src.iconName
        n.typeRaw = src.typeRaw
        n.defaultCurrencyCode = src.defaultCurrencyCode
        n.isShared = false
        n.ownerUserRecordID = nil
        map[n.id] = n
        return n
    }

    private static func copyMember(_ src: Member, into ctx: NSManagedObjectContext,
                                   map: inout [UUID: NSManagedObject]) -> Member {
        let n = Member(context: ctx)
        n.id = src.id; n.name = src.name; n.avatar = src.avatar
        n.isActive = src.isActive; n.sortOrder = src.sortOrder
        map[n.id] = n
        return n
    }

    private static func copyMerchant(_ src: Merchant, into ctx: NSManagedObjectContext,
                                     map: inout [UUID: NSManagedObject]) -> Merchant {
        let n = Merchant(context: ctx)
        n.id = src.id; n.name = src.name; n.category = src.category
        n.isActive = src.isActive; n.sortOrder = src.sortOrder
        map[n.id] = n
        return n
    }

    private static func copyProject(_ src: Project, into ctx: NSManagedObjectContext,
                                    map: inout [UUID: NSManagedObject]) -> Project {
        let n = Project(context: ctx)
        n.id = src.id; n.name = src.name; n.desc = src.desc
        n.startDate = src.startDate; n.endDate = src.endDate
        n.budgetInFen = src.budgetInFen; n.isActive = src.isActive; n.sortOrder = src.sortOrder
        map[n.id] = n
        return n
    }

    private static func copyAccount(_ src: Account, into ctx: NSManagedObjectContext,
                                    map: inout [UUID: NSManagedObject]) -> Account {
        let n = Account(context: ctx)
        n.id = src.id; n.name = src.name; n.currencyCode = src.currencyCode
        n.typeRaw = src.typeRaw; n.iconName = src.iconName; n.colorHex = src.colorHex
        n.customIconData = src.customIconData
        n.initialBalanceInFen = src.initialBalanceInFen
        n.creditLimitInFen = src.creditLimitInFen
        n.billingDay = src.billingDay; n.dueDay = src.dueDay
        n.isArchived = src.isArchived; n.sortOrder = src.sortOrder
        map[n.id] = n
        return n
    }

    private static func copyCategory(_ src: Category, into ctx: NSManagedObjectContext,
                                     map: inout [UUID: NSManagedObject]) -> Category {
        let n = Category(context: ctx)
        n.id = src.id; n.name = src.name; n.iconName = src.iconName
        n.colorHex = src.colorHex; n.typeRaw = src.typeRaw
        n.isSystem = src.isSystem; n.isHidden = src.isHidden; n.sortOrder = src.sortOrder
        map[n.id] = n
        return n
    }

    private static func copyTransaction(_ src: Transaction, into ctx: NSManagedObjectContext,
                                        map: inout [UUID: NSManagedObject]) -> Transaction {
        let n = Transaction(context: ctx)
        n.id = src.id; n.typeRaw = src.typeRaw
        n.amountInFen = src.amountInFen; n.currencyCode = src.currencyCode
        n.exchangeRate = src.exchangeRate; n.convertedAmountInFen = src.convertedAmountInFen
        n.note = src.note; n.date = src.date; n.createdAt = src.createdAt; n.modifiedAt = src.modifiedAt
        n.isReconciled = src.isReconciled
        n.transferGroupId = src.transferGroupId; n.refundGroupId = src.refundGroupId
        n.refundAmountInFen = src.refundAmountInFen
        n.reimbursementStatusRaw = src.reimbursementStatusRaw; n.reimbursedById = src.reimbursedById
        n.lendingDirectionRaw = src.lendingDirectionRaw; n.lendingStatusRaw = src.lendingStatusRaw
        n.settledByLendingTransactionId = src.settledByLendingTransactionId
        n.settledAmountInFen = src.settledAmountInFen
        n.tagsJSON = src.tagsJSON; n.photoURLsJSON = src.photoURLsJSON
        n.isSplitParent = src.isSplitParent
        map[n.id] = n
        return n
    }

    private static func copyTemplate(_ src: TransactionTemplate, into ctx: NSManagedObjectContext,
                                     map: inout [UUID: NSManagedObject]) -> TransactionTemplate {
        let n = TransactionTemplate(context: ctx)
        n.id = src.id; n.name = src.name; n.typeRaw = src.typeRaw
        n.amountInFen = src.amountInFen; n.currencyCode = src.currencyCode
        n.note = src.note; n.tagsJSON = src.tagsJSON
        n.isRecurring = src.isRecurring; n.sortOrder = src.sortOrder
        map[n.id] = n
        return n
    }

    private static func copyRecurringRule(_ src: RecurringRule, into ctx: NSManagedObjectContext,
                                          map: inout [UUID: NSManagedObject]) -> RecurringRule {
        let n = RecurringRule(context: ctx)
        n.id = src.id; n.frequencyRaw = src.frequencyRaw; n.interval = src.interval
        n.startDate = src.startDate; n.endDate = src.endDate
        n.lastGeneratedDate = src.lastGeneratedDate; n.nextGenerateDate = src.nextGenerateDate
        n.isActive = src.isActive
        map[n.id] = n
        return n
    }

    private static func copyBudgetBook(_ src: BudgetBook, into ctx: NSManagedObjectContext,
                                       map: inout [UUID: NSManagedObject]) -> BudgetBook {
        let n = BudgetBook(context: ctx)
        n.id = src.id; n.name = src.name
        n.startDate = src.startDate; n.endDate = src.endDate
        n.isActive = src.isActive; n.sortOrder = src.sortOrder
        map[n.id] = n
        // BudgetItems copied inline
        if let items = src.items {
            for item in items {
                _ = copyBudgetItem(item, into: ctx, map: &map)
            }
        }
        return n
    }

    private static func copyBudgetItem(_ src: BudgetItem, into ctx: NSManagedObjectContext,
                                       map: inout [UUID: NSManagedObject]) -> BudgetItem {
        let n = BudgetItem(context: ctx)
        n.id = src.id; n.amountInFen = src.amountInFen
        n.periodRaw = src.periodRaw; n.alertThreshold = src.alertThreshold
        n.isActive = src.isActive
        map[n.id] = n
        return n
    }

    private static func copySplitGroup(_ src: SplitGroup, into ctx: NSManagedObjectContext,
                                       map: inout [UUID: NSManagedObject]) -> SplitGroup {
        let n = SplitGroup(context: ctx)
        n.id = src.id; n.totalAmountInFen = src.totalAmountInFen
        n.currencyCode = src.currencyCode; n.splitTypeRaw = src.splitTypeRaw
        n.note = src.note; n.date = src.date
        map[n.id] = n
        // SplitEntries copied inline
        if let entries = src.entries {
            for e in entries {
                _ = copySplitEntry(e, into: ctx, map: &map)
            }
        }
        return n
    }

    private static func copySplitEntry(_ src: SplitEntry, into ctx: NSManagedObjectContext,
                                       map: inout [UUID: NSManagedObject]) -> SplitEntry {
        let n = SplitEntry(context: ctx)
        n.id = src.id; n.amountInFen = src.amountInFen
        n.isPaid = src.isPaid; n.paidDate = src.paidDate
        map[n.id] = n
        return n
    }

    private static func copyCreditCardStatement(_ src: CreditCardStatement, into ctx: NSManagedObjectContext,
                                                map: inout [UUID: NSManagedObject]) -> CreditCardStatement {
        let n = CreditCardStatement(context: ctx)
        n.id = src.id; n.periodYear = src.periodYear; n.periodMonth = src.periodMonth
        n.statementAmountInFen = src.statementAmountInFen
        n.reconciledAppAmountInFen = src.reconciledAppAmountInFen
        n.isReconciled = src.isReconciled; n.reconciledAt = src.reconciledAt
        n.note = src.note; n.bankCSVData = src.bankCSVData; n.bankCSVFileName = src.bankCSVFileName
        map[n.id] = n
        return n
    }

    // MARK: - Pass 2 helpers: re-wire relationships

    private static func rewireLedger(_ n: Ledger, source: Ledger, map: [UUID: NSManagedObject],
                                     fetcher: EntityFetcher, context: NSManagedObjectContext) {
        n.accounts = setOf(Account.self, from: map, ids: fetcher.accounts.map(\.id))
        n.categories = setOf(Category.self, from: map, ids: fetcher.allCategories.map(\.id))
        n.transactions = setOf(Transaction.self, from: map, ids: fetcher.allTransactions.map(\.id))
        n.templates = setOf(TransactionTemplate.self, from: map, ids: fetcher.allTemplates.map(\.id))
        n.budgetBooks = setOf(BudgetBook.self, from: map, ids: fetcher.budgetBooks.map(\.id))
        n.memberContacts = setOf(Member.self, from: map, ids: fetcher.members.map(\.id))
        n.merchants = setOf(Merchant.self, from: map, ids: fetcher.merchants.map(\.id))
        n.projects = setOf(Project.self, from: map, ids: fetcher.projects.map(\.id))
        n.splitGroups = setOf(SplitGroup.self, from: map, ids: fetcher.splitGroups.map(\.id))
    }

    private static func rewireMember(_ src: Member, map: [UUID: NSManagedObject]) {
        guard let n = map[src.id] as? Member else { return }
        n.ledger = nil  // set later via ledger rewire
        n.transactions = setOf(Transaction.self, from: map, ids: src.transactions?.map(\.id) ?? [])
        n.templateTransactions = setOf(TransactionTemplate.self, from: map, ids: src.templateTransactions?.map(\.id) ?? [])
        n.splitEntries = setOf(SplitEntry.self, from: map, ids: src.splitEntries?.map(\.id) ?? [])
    }

    private static func rewireMerchant(_ src: Merchant, map: [UUID: NSManagedObject]) {
        guard let n = map[src.id] as? Merchant else { return }
        n.ledger = nil
        n.transactions = setOf(Transaction.self, from: map, ids: src.transactions?.map(\.id) ?? [])
        n.templateTransactions = setOf(TransactionTemplate.self, from: map, ids: src.templateTransactions?.map(\.id) ?? [])
    }

    private static func rewireProject(_ src: Project, map: [UUID: NSManagedObject]) {
        guard let n = map[src.id] as? Project else { return }
        n.ledger = nil
        n.transactions = setOf(Transaction.self, from: map, ids: src.transactions?.map(\.id) ?? [])
        n.templateTransactions = setOf(TransactionTemplate.self, from: map, ids: src.templateTransactions?.map(\.id) ?? [])
    }

    private static func rewireAccount(_ src: Account, map: [UUID: NSManagedObject]) {
        guard let n = map[src.id] as? Account else { return }
        n.ledger = nil
        n.transactions = setOf(Transaction.self, from: map, ids: src.transactions?.map(\.id) ?? [])
        n.incomingTransactions = setOf(Transaction.self, from: map, ids: src.incomingTransactions?.map(\.id) ?? [])
        n.templates = setOf(TransactionTemplate.self, from: map, ids: src.templates?.map(\.id) ?? [])
        n.incomingTemplates = setOf(TransactionTemplate.self, from: map, ids: src.incomingTemplates?.map(\.id) ?? [])
        n.creditCardStatements = setOf(CreditCardStatement.self, from: map, ids: src.creditCardStatements?.map(\.id) ?? [])
    }

    private static func rewireCategory(_ src: Category, map: [UUID: NSManagedObject]) {
        guard let n = map[src.id] as? Category else { return }
        n.ledger = nil
        n.parent = lookup(src.parent?.id, in: map)
        n.children = setOf(Category.self, from: map, ids: src.children?.map(\.id) ?? [])
        n.transactions = setOf(Transaction.self, from: map, ids: src.transactions?.map(\.id) ?? [])
        n.budgetItems = setOf(BudgetItem.self, from: map, ids: src.budgetItems?.map(\.id) ?? [])
        n.templateTransactions = setOf(TransactionTemplate.self, from: map, ids: src.templateTransactions?.map(\.id) ?? [])
    }

    private static func rewireTransaction(_ src: Transaction, map: [UUID: NSManagedObject]) {
        guard let n = map[src.id] as? Transaction else { return }
        n.ledger = nil
        n.account = lookup(src.account?.id, in: map)
        n.toAccount = lookup(src.toAccount?.id, in: map)
        n.category = lookup(src.category?.id, in: map)
        n.member = lookup(src.member?.id, in: map)
        n.merchant = lookup(src.merchant?.id, in: map)
        n.project = lookup(src.project?.id, in: map)
        n.splitGroup = lookup(src.splitGroup?.id, in: map)
        n.parentTransaction = lookup(src.parentTransaction?.id, in: map)
        n.splitChildren = setOf(Transaction.self, from: map, ids: src.splitChildren?.map(\.id) ?? [])
        n.template = lookup(src.template?.id, in: map)
        // createdBy intentionally skipped (is a User / CKShare participant)
        n.createdBy = nil
    }

    private static func rewireTemplate(_ src: TransactionTemplate, map: [UUID: NSManagedObject]) {
        guard let n = map[src.id] as? TransactionTemplate else { return }
        n.ledger = nil
        n.account = lookup(src.account?.id, in: map)
        n.toAccount = lookup(src.toAccount?.id, in: map)
        n.category = lookup(src.category?.id, in: map)
        n.member = lookup(src.member?.id, in: map)
        n.merchant = lookup(src.merchant?.id, in: map)
        n.project = lookup(src.project?.id, in: map)
        n.generatedTransactions = setOf(Transaction.self, from: map, ids: src.generatedTransactions?.map(\.id) ?? [])
        n.recurringRule = lookup(src.recurringRule?.id, in: map)
    }

    private static func rewireRecurringRule(_ src: RecurringRule, map: [UUID: NSManagedObject]) {
        guard let n = map[src.id] as? RecurringRule else { return }
        n.template = lookup(src.template?.id, in: map)
    }

    private static func rewireBudgetBook(_ src: BudgetBook, map: [UUID: NSManagedObject]) {
        guard let n = map[src.id] as? BudgetBook else { return }
        n.ledger = nil
        n.items = setOf(BudgetItem.self, from: map, ids: src.items?.map(\.id) ?? [])
        // Rewire budget items too
        if let items = src.items {
            for item in items {
                rewireBudgetItem(item, map: map)
            }
        }
    }

    private static func rewireBudgetItem(_ src: BudgetItem, map: [UUID: NSManagedObject]) {
        guard let n = map[src.id] as? BudgetItem else { return }
        n.book = lookup(src.book?.id, in: map)
        n.category = lookup(src.category?.id, in: map)
    }

    private static func rewireSplitGroup(_ src: SplitGroup, map: [UUID: NSManagedObject]) {
        guard let n = map[src.id] as? SplitGroup else { return }
        n.ledger = nil
        n.entries = setOf(SplitEntry.self, from: map, ids: src.entries?.map(\.id) ?? [])
        n.transaction = lookup(src.transaction?.id, in: map)
        // Rewire entries too
        if let entries = src.entries {
            for e in entries {
                rewireSplitEntry(e, map: map)
            }
        }
    }

    private static func rewireSplitEntry(_ src: SplitEntry, map: [UUID: NSManagedObject]) {
        guard let n = map[src.id] as? SplitEntry else { return }
        n.splitGroup = lookup(src.splitGroup?.id, in: map)
        n.member = lookup(src.member?.id, in: map)
        // user intentionally skipped (CKShare participant)
        n.user = nil
    }

    private static func rewireCreditCardStatement(_ src: CreditCardStatement, map: [UUID: NSManagedObject]) {
        guard let n = map[src.id] as? CreditCardStatement else { return }
        n.ledger = nil
        n.account = lookup(src.account?.id, in: map)
    }

    // MARK: - Utility

    private static func setOf<T: NSManagedObject>(_: T.Type, from map: [UUID: NSManagedObject],
                                                  ids: [UUID]) -> Set<T> {
        let items = ids.compactMap { map[$0] as? T }
        return Set(items)
    }

    private static func lookup<T: NSManagedObject>(_ id: UUID?, in map: [UUID: NSManagedObject]) -> T? {
        guard let id else { return nil }
        return map[id] as? T
    }
}

// MARK: - Entity fetcher: pre-loads all related entities from the source ledger

private struct EntityFetcher {
    let accounts: [Account]
    let allCategories: [Category]
    let allTransactions: [Transaction]
    let allTemplates: [TransactionTemplate]
    let recurringRules: [RecurringRule]
    let budgetBooks: Set<BudgetBook>
    let members: [Member]
    let merchants: [Merchant]
    let projects: [Project]
    let splitGroups: Set<SplitGroup>
    let creditCardStatements: [CreditCardStatement]

    init(ledger: Ledger) {
        accounts = (ledger.accounts ?? []).sorted { $0.sortOrder < $1.sortOrder }
        allCategories = EntityFetcher.flattenCategories(ledger.categories ?? [])
        allTransactions = (ledger.transactions ?? []).sorted { $0.date > $1.date }
        allTemplates = (ledger.templates ?? []).sorted { $0.sortOrder < $1.sortOrder }
        recurringRules = allTemplates.compactMap { $0.recurringRule }
        budgetBooks = ledger.budgetBooks ?? []
        members = (ledger.memberContacts ?? []).sorted { $0.sortOrder < $1.sortOrder }
        merchants = (ledger.merchants ?? []).sorted { $0.sortOrder < $1.sortOrder }
        projects = (ledger.projects ?? []).sorted { $0.sortOrder < $1.sortOrder }
        splitGroups = ledger.splitGroups ?? []
        creditCardStatements = accounts.flatMap { $0.creditCardStatements ?? [] }
    }

    private static func flattenCategories(_ categories: Set<Category>) -> [Category] {
        var result: [Category] = []
        for c in categories.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            result.append(c)
            if let children = c.children { result.append(contentsOf: flattenCategories(children)) }
        }
        return result
    }
}
