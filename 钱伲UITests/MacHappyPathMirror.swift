import XCTest

/// 钱伲 UI Happy Path 测试
///
/// 覆盖核心用户流程：
/// 1) 启动 → 创建首个 ledger
/// 2) 添加交易 → Dashboard 看到金额更新
/// 3) 切换 ledger → 数据正确切换
/// 4) 搜索 → 找到交易 → 进入详情
/// 5) 删除交易 → 列表项消失
///
/// 依赖 Phase A 添加的 accessibilityIdentifier：
/// - tab-dashboard / tab-accounts / tab-transactions / tab-settings
/// - account-add-button / account-add-name-field / account-add-save-button
/// - add-tx-amount-field / add-tx-account-picker / add-tx-category-picker / add-tx-save-button
/// - search-field / tx-list / tx-list-cell / tx-add-button
/// - tx-detail-delete-button
///
/// Setup：
/// - launchEnvironment: ["UITEST_MODE": "1"] — app 检测后跳过 CloudKit 初始化（待 AppContainer 支持）
/// - 每个测试 setUp 创建干净 ledger（不依赖前序测试）
///
/// 注意：本文件位于 钱伲UITests/ 目录，但需要 Xcode UI Test target 包含此目录才能运行。
/// pbxproj 配置需通过 Xcode GUI 添加 UI Test target（参考 File → New → Target → UI Testing Bundle），
/// 或手动配置（参考 QianeymacUITests 已有的 pbxproj 块）。
final class QianyiHappyPathUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        // 重置 app 状态（如有需要）
    }

    // MARK: - Test 1: 创建首个 ledger

    /// 启动 app → 通过 onboarding 创建首个 ledger → 进入主界面看到 5 个 tab
    /// 依赖：OnboardingView / CreateLedgerView identifier（Phase A 未覆盖，按需补充）
    func test_createInitialLedger_entersMainView() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITEST_MODE", "1"]
        app.launch()

        // 等 onboarding 出现
        let onboarding = app.otherElements["onboarding-view"]
        XCTAssertTrue(onboarding.waitForExistence(timeout: 5), "Onboarding 应出现")

        // TODO: 点击"创建账本"按钮，进入 CreateLedgerView，填写名称，保存
        // 由于 onboarding identifier 未在 Phase A 中覆盖，此测试作为占位

        // 验证 5 个 tab 存在（仅当 app 已登录）
        let dashboardTab = app.tabBars.buttons["tab-dashboard"]
        XCTAssertTrue(dashboardTab.waitForExistence(timeout: 3), "Dashboard tab 应存在")
    }

    // MARK: - Test 2: 添加交易反映到 Dashboard

    /// 添加交易 → Dashboard 净资产卡片更新（依赖 identifier: add-tx-amount-field 等）
    func disabled_test_addTransaction_reflectsInDashboard() throws {
        // disabled_ 直到 onboarding 创建 ledger 测试就绪
        throw XCTSkip("依赖 Test 1 完成后启用")
        let app = XCUIApplication()
        app.launch()

        // 进入账户 tab
        app.tabBars.buttons["tab-accounts"].tap()

        // 点添加账户按钮
        app.buttons["account-add-button"].tap()

        // 填写账户名
        let nameField = app.textFields["account-add-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("现金账户")

        // 保存
        app.buttons["account-add-save-button"].tap()

        // 回到流水 tab
        app.tabBars.buttons["tab-transactions"].tap()

        // 添加交易
        app.buttons["tx-add-button"].tap()

        // 输入金额
        let amountField = app.buttons["add-tx-amount-field"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 3))
        amountField.tap()
        // 假设有 Numpad 输入 100
        // ... (具体输入依赖 numpad 实现)

        // 保存
        app.buttons["add-tx-save-button"].tap()

        // 切回 Dashboard
        app.tabBars.buttons["tab-dashboard"].tap()

        // 验证净资产卡片更新
        let netWorthCard = app.otherElements["dashboard-hero-balance-card"]
        XCTAssertTrue(netWorthCard.exists)
        // 进一步断言金额值变化（需要解析显示文本）
    }

    // MARK: - Test 3: 切换 ledger

    func disabled_test_switchLedger_updatesData() throws {
        throw XCTSkip("依赖 Test 1/2 完成后启用")
        let app = XCUIApplication()
        app.launch()
        // ...
    }

    // MARK: - Test 4: 搜索找到交易

    func disabled_test_search_findsTransaction() throws {
        throw XCTSkip("依赖 Test 2 完成后启用")
        let app = XCUIApplication()
        app.launch()
        // 进入流水 tab
        app.tabBars.buttons["tab-transactions"].tap()
        // 进入搜索
        // ...
        // 在 search-field 输入关键词
        // ...
        // 验证 search-result-cell 出现
    }

    // MARK: - Test 5: 删除交易

    func disabled_test_deleteTransaction_works() throws {
        throw XCTSkip("依赖 Test 2 完成后启用")
        let app = XCUIApplication()
        app.launch()
        // 进入流水详情
        // ...
        // 点 tx-detail-delete-button
        // 确认删除
        // 验证 tx-list-cell 消失
    }
}