import XCTest
@testable import PawsOffCore

final class AppearanceTests: XCTestCase {
    func testDefaults() {
        XCTAssertEqual(AppearanceSettings.defaults.blurPercent, 65)
        XCTAssertEqual(AppearanceSettings.defaults.tintPercent, 45)
    }
    func testZeroTint() { XCTAssertEqual(AppearanceSettings(blurPercent: 0, tintPercent: 0).tintOpacity, 0) }
    func testMaximumTintIsExactly082() {
        XCTAssertEqual(AppearanceSettings(blurPercent: 100, tintPercent: 100).tintOpacity, 0.82)
    }
    func testMidpointIsLinear() {
        XCTAssertEqual(AppearanceSettings(blurPercent: 50, tintPercent: 50).tintOpacity, 0.41)
    }
    func testBlurZero() { XCTAssertEqual(AppearanceSettings(blurPercent: 0, tintPercent: 0).blurOpacity, 0) }
    func testBlurMaximum() { XCTAssertEqual(AppearanceSettings(blurPercent: 100, tintPercent: 100).blurOpacity, 1) }
    func testLowerClamp() {
        let s = AppearanceSettings(blurPercent: -200, tintPercent: -0.1)
        XCTAssertEqual(s.blurPercent, 0); XCTAssertEqual(s.tintPercent, 0)
    }
    func testUpperClamp() {
        let s = AppearanceSettings(blurPercent: 800, tintPercent: 1_000_000)
        XCTAssertEqual(s.blurOpacity, 1); XCTAssertEqual(s.tintOpacity, 0.82)
    }
    func testNaNFallsBack() {
        XCTAssertEqual(AppearanceSettings(blurPercent: .nan, tintPercent: .nan), .defaults)
    }
    func testInfinityFallsBack() {
        XCTAssertEqual(AppearanceSettings(blurPercent: .infinity, tintPercent: -.infinity), .defaults)
    }
    func testAllPercentagesRespectNonBlackout() {
        for i in -1000...2000 {
            let s = AppearanceSettings(blurPercent: Double(i) / 10, tintPercent: Double(i) / 10)
            XCTAssertTrue((0...0.82).contains(s.tintOpacity))
            XCTAssertLessThan(s.tintOpacity, 1)
            XCTAssertTrue((0...1).contains(s.blurOpacity))
        }
    }
    func testTintMonotonic() {
        var previous = -1.0
        for i in 0...1000 {
            let current = AppearanceSettings(blurPercent: 0, tintPercent: Double(i) / 10).tintOpacity
            XCTAssertGreaterThanOrEqual(current, previous); previous = current
        }
    }
    func testPersistenceRoundTrip() {
        let name = "PawsOff.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let s = AppearanceSettings(blurPercent: 17.5, tintPercent: 88.2)
        PreferenceStore(defaults: defaults).save(s)
        XCTAssertEqual(PreferenceStore(defaults: defaults).load(), s)
    }
    func testRegisteredDefaults() {
        let name = "PawsOff.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(PreferenceStore(defaults: defaults).load(), .defaults)
    }
    func testMalformedDefaults() {
        let name = "PawsOff.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("garbage", forKey: "blurPercent")
        defaults.set([1, 2, 3], forKey: "tintPercent")
        XCTAssertEqual(PreferenceStore(defaults: defaults).load(), .defaults)
    }
    func testPersistedOutOfRangeClamped() {
        let name = "PawsOff.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(1234, forKey: "tintPercent")
        defaults.set(-70, forKey: "blurPercent")
        let value = PreferenceStore(defaults: defaults).load()
        XCTAssertEqual(value.tintOpacity, 0.82); XCTAssertEqual(value.blurOpacity, 0)
    }
}
