import SwiftUI

struct AppLockView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var authFailed = false

    private let biometryName = BiometricAuth.biometryName
    private let iconName = BiometricAuth.biometryIconName

    var body: some View {
        ZStack {
            Color.designBackground
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: iconName)
                        .font(.system(size: 48))
                        .foregroundStyle(Color.designPrimary)

                    Text("荡漾计然")
                        .font(.custom("SpaceGrotesk-Bold", fixedSize: 28))
                        .foregroundStyle(Color.designOnSurface)

                    Text(authFailed ? "验证失败，请重试" : "需要\(biometryName)验证")
                        .font(.designBodySmall)
                        .foregroundStyle(authFailed ? Color.designAccentRed : Color.designOnSurfaceVariant)
                }

                Button {
                    authenticate()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: iconName)
                        Text("使用\(biometryName)解锁")
                    }
                    .font(.designBodyMedium.weight(.medium))
                    .foregroundStyle(Color.designOnPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.designPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 48)

                Spacer()
            }
        }
        .task { authenticate() }
    }

    private func authenticate() {
        authFailed = false
        Task {
            let success = await BiometricAuth.authenticate()
            await MainActor.run {
                if success {
                    dismiss()
                } else {
                    authFailed = true
                }
            }
        }
    }
}
