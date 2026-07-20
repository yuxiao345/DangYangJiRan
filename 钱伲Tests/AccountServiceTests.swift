import XCTest
@preconcurrency import CoreData
@testable import 钱伲

final class AccountServiceTests: XCTestCase {

    var context: NSManagedObjectContext!
    var service: AccountServiceImpl!

    override func setUp() {
        super.setUp()
        context = createInMemoryContext()
        service = AccountServiceImpl()
    }

    override func tearDown() {
        context = nil
        service = nil
        super.tearDown()
    }

    // MARK: - Test Infrastructure

    private func createInMemoryContext() -> NSManagedObjectContext {
        guard let modelURL = Bundle(for: Account.self).url(forResource: "FirstCC", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Failed to load CoreData model from bundle")
        }
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try! coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let ctx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        ctx.persistentStoreCoordinator = coordinator
        return ctx
    }

    // MARK: Helpers

    @discardableResult
    private func makeLedger(_ name: String = "测试", defaultCurrencyCode: String = "CNY") -> Ledger {
        let l = Ledger(name: name, context: context)
        l.defaultCurrencyCode = defaultCurrencyCode
        try! context.save()
        return l
    }

    @discardableResult
    private func makeAccount(
        _ name: String = "测试账户",
        _ ledger: Ledger,
        type: AccountType = .cash,
        currencyCode: String = "CNY",
        initialBalance: Decimal = 0
    ) -> Account {
        let a = Account(name: name, currencyCode: currencyCode, type: type, initialBalance: initialBalance, context: context)
        a.ledger = ledger
        try! context.save()
        return a
    }

    @discardableResult
    private func makeTx(
        amount: Decimal,
        date: Date = Date(),
        account: Account,
        toAccount: Account? = nil,
        ledger: Ledger,
        type: TransactionType = .lending,
        lendingDirection: LendingDirection? = nil,
        lendingStatus: LendingStatus = .none,
        settledAmount: Decimal? = nil
    ) -> Transaction {
        let t = Transaction(
            type: type,
            amount: amount,
            date: date,
            lendingDirection: lendingDirection,
            lendingStatus: lendingStatus,
            settledAmount: settledAmount,
            account: account,
            toAccount: toAccount,
            context: context
        )
        t.ledger = ledger
        try! context.save()
        return t
    }

    // MARK: - A: lendOut（借出）

    /// A1: lendOut pending → +应收
    func testA1_lendOutPending_addsToBalance() {
        let ledger = makeLedger()
        let sanGe = makeAccount("三哥", ledger, type: .lending)
        let cash = makeAccount("现金", ledger)

        makeTx(amount: -800, account: cash, toAccount: sanGe, ledger: ledger,
               lendingDirection: .lendOut, lendingStatus: .pending)

        XCTAssertEqual(service.calculateBalance(for: sanGe, context: context), 800)
    }

    /// A2: lendOut settled → 0
    func testA2_lendOutSettled_noEffect() {
        let ledger = makeLedger()
        let sanGe = makeAccount("三哥", ledger, type: .lending)
        let cash = makeAccount("现金", ledger)

        makeTx(amount: -800, account: cash, toAccount: sanGe, ledger: ledger,
               lendingDirection: .lendOut, lendingStatus: .settled)

        XCTAssertEqual(service.calculateBalance(for: sanGe, context: context), 0)
    }

    /// A3: lendOut pending + settledAmount 部分 → +净应收
    func testA3_lendOutPartialSettlement_netReceivable() {
        let ledger = makeLedger()
        let sanGe = makeAccount("三哥", ledger, type: .lending)
        let cash = makeAccount("现金", ledger)

        makeTx(amount: -800, account: cash, toAccount: sanGe, ledger: ledger,
               lendingDirection: .lendOut, lendingStatus: .pending, settledAmount: 400)

        XCTAssertEqual(service.calculateBalance(for: sanGe, context: context), 400)
    }

    /// A4: lendOut + collect 全额结清 → 0
    func testA4_lendOutFullCollect_netZero() {
        let ledger = makeLedger()
        let sanGe = makeAccount("三哥", ledger, type: .lending)
        let cash = makeAccount("现金", ledger)

        let lo = makeTx(amount: -800, account: cash, toAccount: sanGe, ledger: ledger,
                        lendingDirection: .lendOut, lendingStatus: .pending)

        lo.settledAmount = 800
        lo.lendingStatus = .settled
        try! context.save()

        makeTx(amount: 800, account: sanGe, toAccount: cash, ledger: ledger,
               lendingDirection: .collect)

        XCTAssertEqual(service.calculateBalance(for: sanGe, context: context), 0)
    }

    // MARK: - B: borrowIn（借入）

    /// B1: borrowIn pending → −应付
    func testB1_borrowInPending_subtractsFromBalance() {
        let ledger = makeLedger()
        let sanGe = makeAccount("三哥", ledger, type: .lending)
        let cash = makeAccount("工资卡", ledger)

        makeTx(amount: 400, account: sanGe, toAccount: cash, ledger: ledger,
               lendingDirection: .borrowIn, lendingStatus: .pending)

        XCTAssertEqual(service.calculateBalance(for: sanGe, context: context), -400)
    }

    /// B2: borrowIn settled → 0
    func testB2_borrowInSettled_noEffect() {
        let ledger = makeLedger()
        let sanGe = makeAccount("三哥", ledger, type: .lending)
        let cash = makeAccount("工资卡", ledger)

        makeTx(amount: 400, account: sanGe, toAccount: cash, ledger: ledger,
               lendingDirection: .borrowIn, lendingStatus: .settled)

        XCTAssertEqual(service.calculateBalance(for: sanGe, context: context), 0)
    }

    /// B3: borrowIn pending + settledAmount 部分 → −净应付
    func testB3_borrowInPartialRepay_netPayable() {
        let ledger = makeLedger()
        let sanGe = makeAccount("三哥", ledger, type: .lending)
        let cash = makeAccount("工资卡", ledger)

        makeTx(amount: 400, account: sanGe, toAccount: cash, ledger: ledger,
               lendingDirection: .borrowIn, lendingStatus: .pending, settledAmount: 100)

        XCTAssertEqual(service.calculateBalance(for: sanGe, context: context), -300)
    }

    /// B4: borrowIn + repay 全额还清 → 0
    func testB4_borrowInFullRepay_netZero() {
        let ledger = makeLedger()
        let sanGe = makeAccount("三哥", ledger, type: .lending)
        let cash = makeAccount("工资卡", ledger)

        let bi = makeTx(amount: 400, account: sanGe, toAccount: cash, ledger: ledger,
                        lendingDirection: .borrowIn, lendingStatus: .pending)

        bi.settledAmount = 400
        bi.lendingStatus = .settled
        try! context.save()

        makeTx(amount: -400, account: cash, toAccount: sanGe, ledger: ledger,
               lendingDirection: .repay)

        XCTAssertEqual(service.calculateBalance(for: sanGe, context: context), 0)
    }

    // MARK: - C: 组合场景

    /// C1: lendOut + borrowIn 混合（全pending）→ 净额
    func testC1_lendOutAndBorrowIn_netBalance() {
        let ledger = makeLedger()
        let sanGe = makeAccount("三哥", ledger, type: .lending)
        let cash = makeAccount("现金", ledger)
        let card = makeAccount("工资卡", ledger)

        makeTx(amount: -800, account: cash, toAccount: sanGe, ledger: ledger,
               lendingDirection: .lendOut, lendingStatus: .pending)
        makeTx(amount: 400, account: sanGe, toAccount: card, ledger: ledger,
               lendingDirection: .borrowIn, lendingStatus: .pending)

        XCTAssertEqual(service.calculateBalance(for: sanGe, context: context), 400)
    }

    /// C2: lendOut 部分结 + borrowIn 部分还 → 各自 net 合计
    func testC2_partialSettleAndRepay_netBalance() {
        let ledger = makeLedger()
        let sanGe = makeAccount("三哥", ledger, type: .lending)
        let cash = makeAccount("现金", ledger)
        let card = makeAccount("工资卡", ledger)

        makeTx(amount: -800, account: cash, toAccount: sanGe, ledger: ledger,
               lendingDirection: .lendOut, lendingStatus: .pending, settledAmount: 400)
        makeTx(amount: 300, account: sanGe, toAccount: card, ledger: ledger,
               lendingDirection: .borrowIn, lendingStatus: .pending, settledAmount: 100)

        // lendOut net: 800-400=400, borrowIn net: 300-100=200 → 400-200=200
        XCTAssertEqual(service.calculateBalance(for: sanGe, context: context), 200)
    }

    // MARK: - D: 边界场景

    /// D1: initialBalance 计入
    func testD1_initialBalanceIncluded() {
        let ledger = makeLedger()
        let sanGe = makeAccount("三哥", ledger, type: .lending, initialBalance: 100)

        XCTAssertEqual(service.calculateBalance(for: sanGe, context: context), 100)
    }

    /// D2: collect 无对应 lendOut → 0
    func testD2_collectWithoutLendOut_noEffect() {
        let ledger = makeLedger()
        let sanGe = makeAccount("三哥", ledger, type: .lending)
        let cash = makeAccount("现金", ledger)

        makeTx(amount: 500, account: sanGe, toAccount: cash, ledger: ledger,
               lendingDirection: .collect)

        XCTAssertEqual(service.calculateBalance(for: sanGe, context: context), 0)
    }

    /// D3: repay 无对应 borrowIn → 0
    func testD3_repayWithoutBorrowIn_noEffect() {
        let ledger = makeLedger()
        let sanGe = makeAccount("三哥", ledger, type: .lending)
        let cash = makeAccount("现金", ledger)

        makeTx(amount: -400, account: cash, toAccount: sanGe, ledger: ledger,
               lendingDirection: .repay)

        XCTAssertEqual(service.calculateBalance(for: sanGe, context: context), 0)
    }

    // MARK: - E: 非 lending 账户收到借贷资金

    /// E1: collect toAccount=非lending → +金额
    func testE1_nonLendingReceivesCollect() {
        let ledger = makeLedger()
        let sanGe = makeAccount("三哥", ledger, type: .lending)
        let feiziA = makeAccount("肥子A", ledger, type: .debitCard)

        makeTx(amount: 1000, account: feiziA, ledger: ledger, type: .income)
        makeTx(amount: -800, account: feiziA, toAccount: sanGe, ledger: ledger,
               lendingDirection: .lendOut, lendingStatus: .pending)
        makeTx(amount: 400, account: sanGe, toAccount: feiziA, ledger: ledger,
               lendingDirection: .collect)

        // 1000 - 800 + 400 = 600
        XCTAssertEqual(service.calculateBalance(for: feiziA, context: context), 600)
    }

    /// E2: borrowIn toAccount=非lending → +金额
    func testE2_nonLendingReceivesBorrowIn() {
        let ledger = makeLedger()
        let sanGe = makeAccount("三哥", ledger, type: .lending)
        let card = makeAccount("工资卡", ledger, type: .debitCard)

        makeTx(amount: 400, account: sanGe, toAccount: card, ledger: ledger,
               lendingDirection: .borrowIn, lendingStatus: .pending)

        // 从三哥借入 → 工资卡到账 400
        XCTAssertEqual(service.calculateBalance(for: card, context: context), 400)
    }

    // MARK: - F: 非 lending 账户流出借贷资金

    /// F1: lendOut account=非lending → −金额
    func testF1_nonLendingLendOut_decreasesBalance() {
        let ledger = makeLedger()
        let sanGe = makeAccount("三哥", ledger, type: .lending)
        let cash = makeAccount("现金", ledger, type: .cash)

        makeTx(amount: 1000, account: cash, ledger: ledger, type: .income)
        makeTx(amount: -800, account: cash, toAccount: sanGe, ledger: ledger,
               lendingDirection: .lendOut, lendingStatus: .pending)

        XCTAssertEqual(service.calculateBalance(for: cash, context: context), 200)
    }

    /// F2: repay account=非lending → −金额
    func testF2_nonLendingRepay_decreasesBalance() {
        let ledger = makeLedger()
        let sanGe = makeAccount("三哥", ledger, type: .lending)
        let cash = makeAccount("现金", ledger, type: .cash)

        makeTx(amount: 1000, account: cash, ledger: ledger, type: .income)
        makeTx(amount: -400, account: cash, toAccount: sanGe, ledger: ledger,
               lendingDirection: .repay)

        // 1000 - 400 = 600（还款=钱流出）
        XCTAssertEqual(service.calculateBalance(for: cash, context: context), 600)
    }

    // MARK: - G: 非借贷账户常规交易不受影响

    /// G: 支出+收入正常计算
    func testG_regularExpenseAndIncome() {
        let ledger = makeLedger()
        let cash = makeAccount("现金", ledger, type: .cash)

        makeTx(amount: -500, account: cash, ledger: ledger, type: .expense)
        makeTx(amount: 300, account: cash, ledger: ledger, type: .income)

        XCTAssertEqual(service.calculateBalance(for: cash, context: context), -200)
    }

    // MARK: - H: 借贷交易账户校验

    /// H1: 两个非借贷账户 → 无效
    func testH1_twoNonLending_invalid() {
        XCTAssertFalse(AddEditTransactionView.validateLendingAccounts(.cash, .debitCard))
    }

    /// H2: 两个借贷账户 → 无效
    func testH2_twoLending_invalid() {
        XCTAssertFalse(AddEditTransactionView.validateLendingAccounts(.lending, .lending))
    }

    /// H3: 借贷+非借贷 → 有效
    func testH3_lendingAndNonLending_valid() {
        XCTAssertTrue(AddEditTransactionView.validateLendingAccounts(.lending, .cash))
    }

    /// H4: 非借贷+借贷 → 有效
    func testH4_nonLendingAndLending_valid() {
        XCTAssertTrue(AddEditTransactionView.validateLendingAccounts(.cash, .lending))
    }

    /// H5: 两个都未选 → 无效
    func testH5_bothNil_invalid() {
        XCTAssertFalse(AddEditTransactionView.validateLendingAccounts(nil, nil))
    }

    /// H6: 借贷+nil → 有效（toAccount 未选但主账户是借贷）
    func testH6_lendingAndNil_valid() {
        XCTAssertTrue(AddEditTransactionView.validateLendingAccounts(.lending, nil))
    }

    /// H7: nil+借贷 → 有效
    func testH7_nilAndLending_valid() {
        XCTAssertTrue(AddEditTransactionView.validateLendingAccounts(nil, .lending))
    }

    /// H8: nil+非借贷 → 无效
    func testH8_nilAndNonLending_invalid() {
        XCTAssertFalse(AddEditTransactionView.validateLendingAccounts(nil, .cash))
    }
}
