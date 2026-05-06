import SwiftUI
import SwiftData

struct RootView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if appContainer.currentLedger != nil {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .onAppear {
            appContainer.configureDefaultLedger(modelContext: modelContext)
            processRecurring()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                processRecurring()
            }
        }
    }

    private func processRecurring() {
        guard appContainer.currentLedger != nil else { return }
        try? appContainer.recurringService.processDueRecurring(context: modelContext)
    }
}
