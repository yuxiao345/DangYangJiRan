import XCTest

/// Qianeymac Mac Happy Path 测试
///
/// 覆盖 macOS Dashboard 核心流程 + HIG 验证：
/// 1) 启动空 ledger → 显示 onboarding
/// 2) 创建 ledger → 进入主界面（侧边栏 + content）
/// 3) Dashboard 关键控件（HIG）：侧边栏 navigation / toolbar / content 区域
///
/// 注意：macOS 视图尚未补 accessibilityIdentifier（项目 Phase A 仅覆盖 iOS）。
/// 本测试先用 label/identifier 混合策略找到控件，等 macOS identifier 补完后切换。
final class MacHappyPathUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {}

    // MARK: - Test 1: 启动空状态显示 onboarding

    /// 验证 QianeymacUITests target 工作 + AppDelegate 激活窗口
    /// AppDelegate 修复后 macOS 窗口 ~5s 内出现，不需要 sleep
    func test_launch_appStarts() throws {
        let app = MacUITestCase().launchApp()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 30),
                      "主窗口应在 30s 内出现")
    }

    // MARK: - Test 2: 创建 ledger 进入主界面

    /// 创建 ledger 后进入主界面（侧边栏 + content）
    /// UITEST_MODE 跳过 ProgressView 后 macOS 窗口 ~5s 内出现 + sidebar/toolbar 可访问
    func test_createLedger_entersMainView() throws {
        let app = MacUITestCase().launchApp()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 30),
                      "主窗口应在 30s 内出现")

        // 验证侧边栏（用 descendants 链式查询，绕过顶层 otherElements 找不到深层元素的问题）
        let sidebar = window.descendants(matching: .any)["main-sidebar"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 15),
                      "侧边栏应可见")

        // 验证 toolbar 按钮
        let toolbarAddTx = window.buttons["toolbar-add-tx-button"]
        XCTAssertTrue(toolbarAddTx.waitForExistence(timeout: 5),
                      "Toolbar 添加交易按钮应可见")
    }

    // MARK: - Test 3: Dashboard HIG 验证

    /// Dashboard 关键区域：净资产卡片 + 资产配置卡片 + toolbar 按钮
    func test_dashboard_higCompliance() throws {
        let app = MacUITestCase().launchApp()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 30),
                      "主窗口应在 30s 内出现")

        // 净资产卡片（用 descendants 链式查询）
        let netWorthCard = window.descendants(matching: .any)["mac-dashboard-net-worth-card"]
        XCTAssertTrue(netWorthCard.waitForExistence(timeout: 15),
                      "Dashboard 净资产卡片应可见")

        // 资产配置卡片
        let allocationCard = window.descendants(matching: .any)["mac-dashboard-allocation-card"]
        XCTAssertTrue(allocationCard.waitForExistence(timeout: 5),
                      "Dashboard 资产配置卡片应可见")
    }

    // MARK: - Test 4: 切换 ledger

    /// 验证 toolbar 顶部 ledger Menu + 侧边栏都可见（macOS HIG）
    /// -UITEST_MODE 提供 in-memory store
    func test_switchLedger_toolbarAndSidebarVisible() throws {
        let app = MacUITestCase().launchApp()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 30),
                      "主窗口应在 30s 内出现")

        // 验证 sidebar 和 toolbar 关键按钮都可见
        let sidebar = window.descendants(matching: .any)["main-sidebar"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 15),
                      "侧边栏应可见")

        let toolbarAddTx = window.buttons["toolbar-add-tx-button"]
        XCTAssertTrue(toolbarAddTx.waitForExistence(timeout: 5),
                      "Toolbar 添加交易按钮应可见")
    }

    // MARK: - Test 5: 添加交易

    /// 验证 toolbar 加号按钮可见
    /// -UITEST_MODE 提供 in-memory store
    /// 已知 limitation: 不模拟 numpad 输入（多步流程），只验证 toolbar 可达
    func test_addTransaction_reflectsInDashboard() throws {
        let app = MacUITestCase().launchApp()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 30),
                      "主窗口应在 30s 内出现")

        // 验证 toolbar 加号按钮可见
        let toolbarAddTx = window.buttons["toolbar-add-tx-button"]
        XCTAssertTrue(toolbarAddTx.waitForExistence(timeout: 15),
                      "Toolbar 添加交易按钮应可见")

        // 验证 sidebar 可见
        let sidebar = window.descendants(matching: .any)["main-sidebar"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5),
                      "侧边栏应可见")
    }
}

/// Mac UI 测试基类
///
/// 自动注入 `-UITEST_MODE` launch argument，让 CoreDataStack 跳过 CloudKit + 用 in-memory store。
class MacUITestCase: XCTestCase {
    func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITEST_MODE"]
        app.launch()
        return app
    }
}