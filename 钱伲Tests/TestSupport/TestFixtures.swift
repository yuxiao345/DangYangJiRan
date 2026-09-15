import XCTest
@preconcurrency import CoreData
@testable import 钱伲

/// 共享测试数据工厂。所有 factory 返回已 save 的对象，可直接用于断言。
extension NSManagedObjectContext {

    @discardableResult
    func makeLedger(_ name: String = "测试账本", defaultCurrencyCode: String = "CNY") -> Ledger {
        let l = Ledger(name: name, context: self)
        l.defaultCurrencyCode = defaultCurrencyCode
        try! save()
        return l
    }

    @discardableResult
    func makeAccount(
        _ name: String = "测试账户",
        ledger: Ledger,
        type: AccountType = .cash,
        currencyCode: String = "CNY",
        initialBalance: Decimal = 0
    ) -> Account {
        let a = Account(
            name: name,
            currencyCode: currencyCode,
            type: type,
            initialBalance: initialBalance,
            context: self
        )
        a.ledger = ledger
        try! save()
        return a
    }

    @discardableResult
    func makeCategory(
        _ name: String = "测试分类",
        ledger: Ledger,
        type: TransactionType = .expense,
        parent: 钱伲.Category? = nil
    ) -> 钱伲.Category {
        let c = 钱伲.Category(name: name, context: self)
        c.typeRaw = type.rawValue
        c.ledger = ledger
        c.parent = parent
        try! save()
        return c
    }

    @discardableResult
    func makeMember(_ name: String = "测试成员", ledger: Ledger) -> Member {
        let m = Member(name: name, context: self)
        m.ledger = ledger
        try! save()
        return m
    }

    @discardableResult
    func makeMerchant(_ name: String = "测试商户", ledger: Ledger) -> Merchant {
        let m = Merchant(name: name, context: self)
        m.ledger = ledger
        try! save()
        return m
    }

    @discardableResult
    func makeProject(_ name: String = "测试项目", ledger: Ledger) -> Project {
        let p = Project(name: name, context: self)
        p.ledger = ledger
        try! save()
        return p
    }

    @discardableResult
    func makeTransaction(
        amount: Decimal,
        date: Date = Date(),
        account: Account,
        toAccount: Account? = nil,
        ledger: Ledger,
        category: 钱伲.Category? = nil,
        type: TransactionType = .expense,
        note: String? = nil,
        lendingDirection: LendingDirection? = nil,
        lendingStatus: LendingStatus = .none,
        settledAmount: Decimal? = nil,
        reimbursementStatus: ReimbursementStatus = .none,
        refundAmount: Decimal? = nil,
        refundGroupId: UUID? = nil,
        transferGroupId: UUID? = nil
    ) -> Transaction {
        let t = Transaction(
            type: type,
            amount: amount,
            note: note,
            date: date,
            lendingDirection: lendingDirection,
            lendingStatus: lendingStatus,
            settledAmount: settledAmount,
            account: account,
            toAccount: toAccount,
            category: category,
            context: self
        )
        t.ledger = ledger
        t.reimbursementStatus = reimbursementStatus
        t.refundAmount = refundAmount
        t.refundGroupId = refundGroupId
        t.transferGroupId = transferGroupId
        try! save()
        return t
    }

    /// 拆分记账：一个父交易（`isSplitParent`）+ 若干子交易（`parentTransaction` 指回父）。
    ///
    /// 子项各自携带 category/member/merchant/project，**父交易这些字段全部为 nil**；
    /// 父交易金额 = 子项金额之和（子项一律记负数的绝对值）。
    ///
    /// 与 `AddEditTransactionView.createSplitChildren` 一致，唯一省略的是 `applyCurrency`
    /// ——测试账本均为单一基准币种，不涉及折算。
    @discardableResult
    func makeSplitTransaction(
        _ items: [SplitItemFixture],
        date: Date = Date(),
        account: Account,
        ledger: Ledger
    ) -> Transaction {
        let total = items.reduce(Decimal.zero) { $0 + abs($1.amount) }
        let parent = Transaction(
            type: .expense,
            amount: -total,
            date: date,
            account: account,
            isSplitParent: true,
            context: self
        )
        parent.ledger = ledger

        for item in items {
            let child = Transaction(
                type: .expense,
                amount: -abs(item.amount),
                note: item.note,
                date: date,
                account: account,
                category: item.category,
                member: item.member,
                merchant: item.merchant,
                project: item.project,
                parentTransaction: parent,
                context: self
            )
            child.ledger = ledger
        }

        try! save()
        return parent
    }

    @discardableResult
    func makeBudgetBook(_ name: String = "测试预算", ledger: Ledger) -> BudgetBook {
        let b = BudgetBook(name: name, context: self)
        b.ledger = ledger
        try! save()
        return b
    }

    @discardableResult
    func makeBudgetItem(
        amount: Decimal = 1000,
        book: BudgetBook,
        category: 钱伲.Category? = nil,
        period: BudgetPeriod = .monthly
    ) -> BudgetItem {
        let item = BudgetItem(
            amount: amount,
            period: period,
            category: category,
            context: self
        )
        item.book = book
        try! save()
        return item
    }
}

/// 拆分子项的描述（供 `makeSplitTransaction` 使用）
struct SplitItemFixture {
    var amount: Decimal
    var category: 钱伲.Category?
    var member: Member?
    var merchant: Merchant?
    var project: Project?
    var note: String?
}

/// 共享日期助手
enum TestDates {
    static func date(_ y: Int, _ m: Int, _ d: Int, hr: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: hr))!
    }
    static func today() -> Date { Date() }
}