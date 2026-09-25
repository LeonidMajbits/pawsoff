import Foundation

/// Values are percentages; the renderer never interprets tintPercent as opacity.
public struct AppearanceSettings: Equatable {
    public static let maximumTintOpacity = 0.82
    public static let defaults = AppearanceSettings(blurPercent: 65, tintPercent: 45, showHUD: true)
    public let blurPercent: Double
    public let tintPercent: Double
    public let showHUD: Bool

    public init(blurPercent: Double, tintPercent: Double, showHUD: Bool = true) {
        self.blurPercent = Self.clamp(blurPercent, fallback: 65)
        self.tintPercent = Self.clamp(tintPercent, fallback: 45)
        self.showHUD = showHUD
    }
    public var blurOpacity: Double { blurPercent / 100 }
    public var tintOpacity: Double { tintPercent / 100 * Self.maximumTintOpacity }

    private static func clamp(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(100, max(0, value))
    }
}

/// A separate, injectable defaults suite makes persistence testable without AppKit.
public final class PreferenceStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["blurPercent": 65.0, "tintPercent": 45.0, "showHUD": true])
    }
    public func load() -> AppearanceSettings {
        // NSNumber check avoids malformed strings silently becoming a zero percent setting.
        let blur = (defaults.object(forKey: "blurPercent") as? NSNumber)?.doubleValue ?? 65
        let tint = (defaults.object(forKey: "tintPercent") as? NSNumber)?.doubleValue ?? 45
        let hud = defaults.object(forKey: "showHUD") as? Bool ?? true
        return AppearanceSettings(blurPercent: blur, tintPercent: tint, showHUD: hud)
    }
    public func save(_ settings: AppearanceSettings) {
        defaults.set(settings.blurPercent, forKey: "blurPercent")
        defaults.set(settings.tintPercent, forKey: "tintPercent")
        defaults.set(settings.showHUD, forKey: "showHUD")
    }
}
