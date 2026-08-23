import UIKit
import CloudKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    // MARK: - Scene connection (cold start — connectionOptions may have CKShare metadata)

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        let count = UserDefaults.standard.integer(forKey: "diag_willConnectFired") + 1
        UserDefaults.standard.set(count, forKey: "diag_willConnectFired")

        if let metadata = connectionOptions.cloudKitShareMetadata {
            DiagnosticLog.log("SceneDelegate: willConnect has CKShare metadata!!!")
            UserDefaults.standard.set(true, forKey: "diag_willConnectHasMetadata")
            handle(metadata)
        } else {
            DiagnosticLog.log("SceneDelegate: willConnect #\(count) — no CKShare metadata")
        }
    }

    // MARK: - CKShare (warm start or system-delivered)

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        let count = UserDefaults.standard.integer(forKey: "diag_sceneDelegateFired") + 1
        UserDefaults.standard.set(count, forKey: "diag_sceneDelegateFired")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "diag_sceneDelegateLastTime")

        DiagnosticLog.log("SceneDelegate: userDidAcceptCloudKitShareWith fired #\(count)")
        Logger.info("SceneDelegate: userDidAcceptCloudKitShareWith fired #\(count)")
        handle(cloudKitShareMetadata)
    }

    // MARK: - URL context fallback

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        let count = UserDefaults.standard.integer(forKey: "diag_openURLContextsFired") + 1
        UserDefaults.standard.set(count, forKey: "diag_openURLContextsFired")

        guard let urlContext = URLContexts.first else { return }
        let url = urlContext.url
        DiagnosticLog.log("SceneDelegate: openURLContexts #\(count) url=\(url)")
        UserDefaults.standard.set(url.absoluteString, forKey: "diag_openURLContextsURL")
        deliverURL(url)
    }

    // MARK: - Internal

    private func handle(_ metadata: CKShare.Metadata) {
        if let appContainer = AppContainer.shared {
            DiagnosticLog.log("SceneDelegate: AppContainer.shared OK")
            UserDefaults.standard.set(true, forKey: "diag_sceneDelegateSharedOK")
            Task { await appContainer.handleAcceptedShareMetadata(metadata) }
            return
        }

        DiagnosticLog.log("SceneDelegate: AppContainer.shared nil, retrying...")
        UserDefaults.standard.set(true, forKey: "diag_sceneDelegateSharedNil")
        Task {
            for i in 1...10 {
                try? await Task.sleep(for: .seconds(1))
                if let appContainer = AppContainer.shared {
                    DiagnosticLog.log("SceneDelegate: got AppContainer on retry \(i)")
                    UserDefaults.standard.set(i, forKey: "diag_sceneDelegateRetrySuccess")
                    await appContainer.handleAcceptedShareMetadata(metadata)
                    return
                }
            }
            DiagnosticLog.log("SceneDelegate: FAILED after 10 retries")
            UserDefaults.standard.set(true, forKey: "diag_sceneDelegateFailed")
        }
    }

    private func deliverURL(_ url: URL) {
        if let appContainer = AppContainer.shared {
            Task { await appContainer.handleShareURL(url) }
        } else {
            Task {
                for i in 1...10 {
                    try? await Task.sleep(for: .seconds(1))
                    if let appContainer = AppContainer.shared {
                        await appContainer.handleShareURL(url)
                        return
                    }
                }
            }
        }
    }
}
