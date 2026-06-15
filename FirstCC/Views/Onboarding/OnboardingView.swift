import SwiftUI

struct OnboardingView: View {
    @Environment(AppContainer.self) private var appContainer

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "book.pages")
                    .font(.system(size: 80))
                    .foregroundStyle(Color.designPrimaryContainer)

                Text("钱伲")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("家庭记账，一目了然")
                    .font(.designBodyMedium)
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

                }
                .padding(.horizontal, 40)
            }
            .padding(.bottom, 60)
        }
    }
}
