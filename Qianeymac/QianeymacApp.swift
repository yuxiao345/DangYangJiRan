import SwiftUI
@preconcurrency import CoreData
import CoreText

enum AppearanceMode: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"
}

extension Notification.Name {
    static let macMenuNavigate = Notification.Name("macMenuNavigate")
    static let macMenuNewTransaction = Notification.Name("macMenuNewTransaction")
    static let macMenuSearch = Notification.Name("macMenuSearch")
}

@main
struct QianeymacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appContainer = AppContainer()
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @State private var storesLoaded = false

    init() {
        registerCustomFonts()
    }

    private func registerCustomFonts() {
        let fontNames = [
            "SpaceGrotesk-Light", "SpaceGrotesk-Regular", "SpaceGrotesk-Medium",
            "SpaceGrotesk-SemiBold", "SpaceGrotesk-Bold",
            "JetBrainsMono-Regular", "JetBrainsMono-Medium", "JetBrainsMono-Bold"
        ]
        for name in fontNames {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                print("[Font] WARNING: \(name).ttf not found in bundle")
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                let msg = error?.takeRetainedValue().localizedDescription ?? "unknown"
                print("[Font] Failed to register \(name): \(msg)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            // UITEST_MODE 跳过 ProgressView（loadStores 在 in-memory 模式下也应秒完成，
            // 但 ProgressView 持有的 .task 在 XCUITest 环境下可能因 scenePhase 未 active
            // 而不触发；UI 测试需要直接看到 MainSplitView 而不是 ProgressView）
            if storesLoaded || ProcessInfo.processInfo.arguments.contains("-UITEST_MODE") {
                MainSplitView()
                    .environment(\.managedObjectContext, appContainer.viewContext)
                    .environment(appContainer)
                    .tint(Color.designAccentGreen)
                    .preferredColorScheme(preferredScheme)
            } else {
                ProgressView("正在准备数据...")
                    .frame(width: 300, height: 200)
                    .task {
                        do {
                            try await appContainer.loadStores()
                            storesLoaded = true
                        } catch {
                            storesLoaded = true
                        }
                    }
            }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1200, height: 780)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .newItem) {
                Button("记一笔") {
                    NotificationCenter.default.post(name: .macMenuNewTransaction, object: nil)
                }
                .keyboardShortcut("n")
            }
            CommandGroup(after: .newItem) {
                Button("搜索") {
                    NotificationCenter.default.post(name: .macMenuSearch, object: nil)
                }
                .keyboardShortcut("F", modifiers: [.command, .shift])
            }
            CommandMenu("导航") {
                Button("总览") { postNavigate(.dashboard) }
                    .keyboardShortcut("1")
                Button("账户") { postNavigate(.accounts) }
                    .keyboardShortcut("2")
                Button("流水") { postNavigate(.transactions) }
                    .keyboardShortcut("3")
                Button("报表") { postNavigate(.reports) }
                    .keyboardShortcut("4")
            }
        }

        Settings {
            SettingsWindow()
                .environment(\.managedObjectContext, appContainer.viewContext)
                .environment(appContainer)
                .tint(Color.designAccentGreen)
                .preferredColorScheme(preferredScheme)
        }
    }

    private func postNavigate(_ item: MacNavItem) {
        NotificationCenter.default.post(name: .macMenuNavigate, object: item)
    }

    private var preferredScheme: ColorScheme? {
        switch appearanceMode {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}
