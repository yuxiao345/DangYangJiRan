import SwiftUI
@preconcurrency import CoreData

enum AppearanceMode: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"
}

extension Notification.Name {
    static let macMenuNavigate = Notification.Name("macMenuNavigate")
}

@main
struct QianeymacApp: App {
    @StateObject private var appContainer = AppContainer()
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @State private var storesLoaded = false

    var body: some Scene {
        WindowGroup {
            if storesLoaded {
                MainSplitView()
                    .environment(\.managedObjectContext, appContainer.viewContext)
                    .environmentObject(appContainer)
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
            CommandMenu("导航") {
                Button("总览") { postNavigate(.dashboard) }
                    .keyboardShortcut("1")
                Button("账户") { postNavigate(.accounts) }
                    .keyboardShortcut("2")
                Button("流水") { postNavigate(.transactions) }
                    .keyboardShortcut("3")
                Button("报表") { postNavigate(.reports) }
                    .keyboardShortcut("4")
                Button("设置") { postNavigate(.settings) }
                    .keyboardShortcut("5")
            }
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
