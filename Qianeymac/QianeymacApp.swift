import SwiftUI
@preconcurrency import CoreData

enum AppearanceMode: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"
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
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 600)
    }

    private var preferredScheme: ColorScheme? {
        switch appearanceMode {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}
