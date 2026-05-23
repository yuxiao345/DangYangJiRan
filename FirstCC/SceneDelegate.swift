import UIKit
import CloudKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        DiagnosticLog.log("SceneDelegate: userDidAcceptCloudKitShareWith fired")
        Logger.info("SceneDelegate: userDidAcceptCloudKitShareWith fired")

        // Try static shared first (survives cold starts)
        if let appContainer = AppContainer.shared {
            DiagnosticLog.log("SceneDelegate: AppContainer.shared OK")
            Logger.info("SceneDelegate: using AppContainer.shared")
            Task {
                await appContainer.handleAcceptedShareMetadata(cloudKitShareMetadata)
            }
            return
        }

        // Fallback: wait for view hierarchy to wire up
        DiagnosticLog.log("SceneDelegate: AppContainer.shared nil, retrying...")
        Logger.info("SceneDelegate: shared nil, will retry after delay")
        Task {
            for i in 1...10 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if let appContainer = AppContainer.shared {
                    DiagnosticLog.log("SceneDelegate: got AppContainer on retry \(i)")
                    Logger.info("SceneDelegate: got AppContainer on retry \(i)")
                    await appContainer.handleAcceptedShareMetadata(cloudKitShareMetadata)
                    return
                }
            }
            DiagnosticLog.log("SceneDelegate: FAILED - AppContainer.shared still nil after 10 retries")
            Logger.error("SceneDelegate: AppContainer.shared still nil after 10 retries")
        }
    }
}
