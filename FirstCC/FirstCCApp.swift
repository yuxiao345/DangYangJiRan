import SwiftUI
import SwiftData
import CoreText
import UIKit

private struct SceneDelegateAdaptor: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    // Older URL-based delivery path (sometimes works when SceneDelegate doesn't)
    func application(
        _ application: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        let count = UserDefaults.standard.integer(forKey: "diag_appDelegateOpenURL") + 1
        UserDefaults.standard.set(count, forKey: "diag_appDelegateOpenURL")
        UserDefaults.standard.set(url.absoluteString, forKey: "diag_appDelegateOpenURLLast")

        DiagnosticLog.log("AppDelegate: openURL #\(count) url=\(url)")
        Logger.info("AppDelegate: openURL #\(count) url=\(url)")

        Task {
            for i in 1...10 {
                if let appContainer = AppContainer.shared {
                    await appContainer.handleShareURL(url)
                    return
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        return true
    }
}

private extension View {
    func attachSceneDelegate() -> some View {
        background(SceneDelegateAdaptor().frame(width: 0, height: 0))
    }
}


@main
struct FirstCCApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appContainer = AppContainer()
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system

    init() {
        registerCustomFonts()

        // Navigation bar: Space Grotesk for titles
        let largeTitle = UIFont(name: "SpaceGrotesk-Bold", size: 34) ?? UIFont.systemFont(ofSize: 34, weight: .bold)
        let inlineTitle = UIFont(name: "SpaceGrotesk-SemiBold", size: 17) ?? UIFont.systemFont(ofSize: 17, weight: .semibold)
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: largeTitle]
        UINavigationBar.appearance().titleTextAttributes = [.font: inlineTitle]

        // Tab bar: Space Grotesk Regular for item labels
        let tabBarItem = UIFont(name: "SpaceGrotesk-Regular", size: 10) ?? UIFont.systemFont(ofSize: 10)
        UITabBarItem.appearance().setTitleTextAttributes([.font: tabBarItem], for: .normal)

        // Segmented control: Space Grotesk Medium
        let segmentFont = UIFont(name: "SpaceGrotesk-Medium", size: 13) ?? UIFont.systemFont(ofSize: 13, weight: .medium)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: segmentFont], for: .normal)
    }

    private func registerCustomFonts() {
        let fontNames = [
            "SpaceGrotesk-Light", "SpaceGrotesk-Regular", "SpaceGrotesk-Medium",
            "SpaceGrotesk-SemiBold", "SpaceGrotesk-Bold",
            "JetBrainsMono-Regular", "JetBrainsMono-Medium", "JetBrainsMono-Bold"
        ]
        for name in fontNames {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                print("[Font] WARNING: \(name).ttf not found in bundle")
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                let msg = error?.takeRetainedValue().localizedDescription ?? "unknown"
                print("[Font] Failed to register \(name): \(msg)")
            }
        }
    }

    private var preferredScheme: ColorScheme? {
        switch appearanceMode {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appContainer)
                .tint(Color.designAccentGreen)
                .preferredColorScheme(preferredScheme)
                .attachSceneDelegate()
                .onOpenURL { url in
                    Task {
                        await appContainer.handleShareURL(url)
                    }
                }
        }
        .modelContainer(appContainer.modelContainer)
    }
}
