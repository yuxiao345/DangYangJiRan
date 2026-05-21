import LocalAuthentication

enum BiometricAuth {
    static var biometryType: LABiometryType {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return context.biometryType
    }

    static var biometryIconName: String {
        switch biometryType {
        case .faceID: "faceid"
        case .touchID: "touchid"
        default: "lock"
        }
    }

    static var biometryName: String {
        switch biometryType {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        default:
            // Fallback to device passcode on simulator or devices without biometrics
            isDeviceOwnerAuthAvailable ? String(localized: "密码") : String(localized: "生物识别")
        }
    }

    private static var isDeviceOwnerAuthAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    static var isAvailable: Bool {
        isDeviceOwnerAuthAvailable
    }

    static func authenticate(reason: String = String(localized: "解锁以访问账本")) async -> Bool {
        guard isAvailable else { return true }

        let context = LAContext()
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            ) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
