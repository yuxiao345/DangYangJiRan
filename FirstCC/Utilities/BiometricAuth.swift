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
        // Try biometrics first (Face ID / Touch ID without passcode fallback)
        let bioContext = LAContext()
        var error: NSError?
        if bioContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            let success = await withCheckedContinuation { c in
                bioContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { result, _ in
                    c.resume(returning: result)
                }
            }
            if success { return true }
        }

        // Fallback to device passcode
        let passcodeContext = LAContext()
        return await withCheckedContinuation { c in
            passcodeContext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                c.resume(returning: success)
            }
        }
    }
}
