import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appContainer: AppContainer

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "book.pages")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)

                Text("荡漾计然")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("家庭记账，一目了然")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                VStack(spacing: 16) {
                    NavigationLink {
                        CreateLedgerView()
                    } label: {
                        Label("创建账本", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    NavigationLink {
                        JoinLedgerView()
                    } label: {
                        Label("加入账本", systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.horizontal, 40)
            }
            .padding(.bottom, 60)
        }
    }
}
