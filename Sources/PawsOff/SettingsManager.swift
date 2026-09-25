import Foundation
import PawsOffCore

final class SettingsManager {
    private let store = PreferenceStore()
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
}
