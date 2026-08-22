import AppKit

/// macOS AppDelegate — 强制激活窗口，解决 WindowGroup 在 XCUITest + sandbox 环境下
/// 不显示主窗口的问题（PG-1 调研：激活策略问题最可能）。
///
/// 现象：直接 `open -a Qianeymac.app` 或 XCUITest `app.launch()` 后，进程在跑但
/// `osascript ... System Events get name of every window` 返回空。
///
/// 根因（Agent 调研）：SwiftUI `@main App` 在 macOS 26+ sandbox + GENERATE_INFOPLIST_FILE
/// 配置下，NSApplication.shared.setActivationPolicy(.regular) 可能未及时调用，导致
/// WindowGroup 创建的 window 处于"逻辑存在但前台不可见"状态。
///
/// 修复：在 applicationDidFinishLaunching 显式设 activationPolicy + activate，
/// 保证 macOS UI 测试环境下窗口能被 XCUITest 看到。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}