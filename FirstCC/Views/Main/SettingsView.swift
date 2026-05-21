import SwiftUI

enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    var displayName: String {
        switch self {
        case .system: String(localized: "跟随系统")
        case .light: String(localized: "浅色模式")
        case .dark: String(localized: "深色模式")
        }
    }

    var iconName: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

struct SettingsView: View {
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @State private var showToggleAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section("账本") {
                    NavigationLink("账本管理") {
                        LedgerListView()
                    }
                }
                Section("安全") {
                    if BiometricAuth.isAvailable {
                        Toggle(isOn: $appLockEnabled) {
                            Label("\(BiometricAuth.biometryName) 锁", systemImage: "lock")
                        }
                    } else {
                        Label("生物识别不可用", systemImage: "lock.slash")
                            .foregroundStyle(Color.designOnSurfaceVariant)
                    }
                }
                Section("外观") {
                    Picker(selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Label(mode.displayName, systemImage: mode.iconName)
                                .tag(mode)
                        }
                    } label: {
                        Label("主题", systemImage: "paintpalette")
                    }
                }
            }
            .designScreen()
            .scrollContentBackground(.hidden)
            .navigationTitle("设置")
        }
    }
}
