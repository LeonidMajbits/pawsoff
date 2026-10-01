import Foundation
import PawsOffCore

final class SettingsManager {
    private let store = PreferenceStore()
    let passkey = PasskeyManager()
    private(set) var appearance: AppearanceSettings
    var onChange: ((AppearanceSettings) -> Void)?

    init() { appearance = store.load() }
    func setBlur(_ percentage: Double) {
        update(AppearanceSettings(blurPercent: percentage, tintPercent: appearance.tintPercent, showHUD: appearance.showHUD))
    }
    func setTint(_ percentage: Double) {
        update(AppearanceSettings(blurPercent: appearance.blurPercent, tintPercent: percentage, showHUD: appearance.showHUD))
    }
    func setShowHUD(_ show: Bool) {
        update(AppearanceSettings(blurPercent: appearance.blurPercent, tintPercent: appearance.tintPercent, showHUD: show))
    }
    private func update(_ value: AppearanceSettings) {
        precondition(Thread.isMainThread)
        appearance = value
        store.save(value)
        onChange?(value)
    }

    private let tutorialSuppressedKey = "suppress_tutorial_on_launch"

    var shouldShowTutorialOnLaunch: Bool {
        !UserDefaults.standard.bool(forKey: tutorialSuppressedKey)
    }

    func setTutorialSuppressedOnLaunch(_ suppressed: Bool) {
        UserDefaults.standard.set(suppressed, forKey: tutorialSuppressedKey)
    }
}
