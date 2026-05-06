import SwiftUI
import SwiftData

struct RootView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if appContainer.isAuthenticated {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .onAppear {
            appContainer.configureDefaultLedger(modelContext: modelContext)
        }
    }
}
