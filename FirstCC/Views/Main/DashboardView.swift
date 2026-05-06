import SwiftUI

struct DashboardView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text("总览")
                    .font(.title)
                Text("即将在 Phase 1 实现")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("总览")
        }
    }
}
