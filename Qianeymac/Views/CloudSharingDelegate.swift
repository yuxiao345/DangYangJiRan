import CloudKit
import AppKit

/// Shared NSSharingService delegate for CloudKit share operations.
/// Used by both toolbar (MainSplitView) and settings (SettingsWindow).
final class CloudSharingDelegate: NSObject, NSSharingServiceDelegate, NSCloudSharingServiceDelegate {
    let onStop: () -> Void

    init(onStop: @escaping () -> Void) { self.onStop = onStop }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {}
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {}

    func sharingService(_ sharingService: NSSharingService, sourceWindowForShareItems items: [Any], sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
        NSApp.keyWindow
    }

    func sharingService(_ sharingService: NSSharingService, didStopSharing share: CKShare) {
        onStop()
    }

    func options(for sharingService: NSSharingService, share: CKShare) -> NSSharingService.CloudKitOptions {
        [.allowPublic, .allowPrivate, .allowReadOnly, .allowReadWrite]
    }
}
