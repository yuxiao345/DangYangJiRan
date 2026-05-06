import SwiftUI
import SwiftData

@main
struct FirstCCApp: App {
    @StateObject private var appContainer = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appContainer)
                .onOpenURL { url in
                    // Handle CKShare invitation deep link
                    Task {
                        await appContainer.handleShareURL(url)
                    }
                }
        }
        .modelContainer(appContainer.modelContainer)
    }
}
