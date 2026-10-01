import Foundation
import CryptoKit

public final class PasskeyManager {
    public static let maxAttempts = 3
    private let defaults: UserDefaults
    private var failedAttempts = 0
    
    private let enabledKey = "passkey_enabled"
    private let hashKey = "passkey_hash"
    private let saltKey = "passkey_salt"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isPasskeyEnabled: Bool {
        get { defaults.bool(forKey: enabledKey) && hasPasskey }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    public var hasPasskey: Bool {
        guard let hash = defaults.string(forKey: hashKey), !hash.isEmpty,
              let salt = defaults.string(forKey: saltKey), !salt.isEmpty else {
            return false
        }
        return true
    }

    public func setPasskey(_ pin: String) {
        let trimmed = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let salt = UUID().uuidString
        let hash = computeHash(pin: trimmed, salt: salt)
        defaults.set(salt, forKey: saltKey)
        defaults.set(hash, forKey: hashKey)
        defaults.set(true, forKey: enabledKey)
        failedAttempts = 0
    }

    public func clearPasskey() {
        defaults.removeObject(forKey: hashKey)
        defaults.removeObject(forKey: saltKey)
        defaults.set(false, forKey: enabledKey)
        failedAttempts = 0
    }

    public func verify(pin: String) -> Bool {
        guard isPasskeyEnabled else { return true }
        guard let storedHash = defaults.string(forKey: hashKey),
              let salt = defaults.string(forKey: saltKey) else {
            return true
        }
        let inputHash = computeHash(pin: pin.trimmingCharacters(in: .whitespacesAndNewlines), salt: salt)
        if inputHash == storedHash {
            failedAttempts = 0
            return true
        } else {
            failedAttempts += 1
            return false
        }
    }

    public var remainingAttempts: Int {
        max(0, Self.maxAttempts - failedAttempts)
    }

    public var isLockedOut: Bool {
        failedAttempts >= Self.maxAttempts
    }

    public func resetAttempts() {
        failedAttempts = 0
    }

    private func computeHash(pin: String, salt: String) -> String {
        let payload = "\(salt):\(pin)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    public static func triggerNativeMacLockScreen() {
        typealias SACLockScreenImmediateFunc = @convention(c) () -> Void
        if let bundle = CFBundleCreate(
            kCFAllocatorDefault,
            NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/login.framework")
        ) {
            if let funcPtr = CFBundleGetFunctionPointerForName(bundle, "SACLockScreenImmediate" as CFString) {
                let lockScreen = unsafeBitCast(funcPtr, to: SACLockScreenImmediateFunc.self)
                lockScreen()
                return
            }
        }
        // Fallback: displaysleepnow
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["displaysleepnow"]
        try? task.run()
    }
}
