import XCTest
@testable import PawsOffCore

final class InputGateTests: XCTestCase {
    private func down(_ code: UInt16, _ time: Double = 1, mods: Modifiers = [], repeatFlag: Bool = false) -> GuardInput {
        .keyDown(code: code, repeating: repeatFlag, modifiers: mods, time: time)
    }
    func testIdlePassesEveryInputClass() {
        var gate = InputGate()
        for e: GuardInput in [down(0), .keyUp(code: 0), .flagsChanged(.command), .buttonDown(0),
                              .buttonUp(0), .pointerMoved, .dragged, .scroll, .other] {
            XCTAssertEqual(gate.consume(e), .pass)
        }
    }
    func testArmSetsActive() { var g = InputGate(); g.arm(); XCTAssertEqual(g.phase, .active) }
    func testOrdinaryKeyDownBlocked() { var g = InputGate(); g.arm(); XCTAssertEqual(g.consume(down(0)), .block) }
    func testOrdinaryKeyUpBlocked() { var g = InputGate(); g.arm(); XCTAssertEqual(g.consume(.keyUp(code: 0)), .block) }
    func testCtrlOneUnlocks() {
        var g = InputGate(); g.arm()
        XCTAssertEqual(g.consume(down(18, mods: .control)), .unlockAndBlock)
        XCTAssertEqual(g.phase, .draining)
    }
    func testOneAloneDoesNotUnlock() { var g = InputGate(); g.arm(); XCTAssertEqual(g.consume(down(18)), .block) }
    func testCommandOneDoesNotUnlock() { var g = InputGate(); g.arm(); XCTAssertEqual(g.consume(down(18, mods: .command)), .block) }
    func testOtherModifierCombinationsDoNotUnlock() {
        for raw: UInt8 in 0...31 where raw != Modifiers.control.rawValue {
            var g = InputGate(); g.arm()
            XCTAssertEqual(g.consume(down(18, mods: Modifiers(rawValue: raw))), .block)
        }
    }
    func testAllNonShortcutKeysBlocked() {
        for key: UInt16 in 0...127 where key != 18 {
            var g = InputGate(); g.arm()
            XCTAssertEqual(g.consume(down(key, mods: .control)), .block)
        }
    }
    func testActivationChordRepeatCannotUnlock() {
        var g = InputGate(); g.arm(keys: [18], modifiers: .control, consumedKeys: [18])
        XCTAssertEqual(g.consume(down(18, mods: .control, repeatFlag: true)), .block)
        XCTAssertEqual(g.consume(down(18, mods: .control)), .block)
        XCTAssertEqual(g.phase, .active)
    }
    func testFreshChordAfterReleaseUnlocks() {
        var g = InputGate(); g.arm(keys: [18], modifiers: .control, consumedKeys: [18])
        XCTAssertEqual(g.consume(.keyUp(code: 18)), .block)
        XCTAssertEqual(g.consume(.flagsChanged([])), .pass)
        XCTAssertEqual(g.consume(down(18, mods: .control)), .unlockAndBlock)
    }
    func testAutorepeatFlagCannotUnlockEvenWithoutSeed() {
        var g = InputGate(); g.arm()
        XCTAssertEqual(g.consume(down(18, mods: .control, repeatFlag: true)), .block)
    }
    func testEscapeNeedsTwoPressesAndRelease() {
        var g = InputGate(); g.arm()
        XCTAssertEqual(g.consume(down(53, 1)), .block)
        XCTAssertEqual(g.consume(.keyUp(code: 53)), .block)
        XCTAssertEqual(g.consume(down(53, 1.5)), .unlockAndBlock)
    }
    func testHeldEscapeCannotUnlock() {
        var g = InputGate(); g.arm()
        XCTAssertEqual(g.consume(down(53, 1)), .block)
        XCTAssertEqual(g.consume(down(53, 1.1)), .block)
        XCTAssertEqual(g.consume(down(53, 1.2, repeatFlag: true)), .block)
    }
    func testSlowEscapesDoNotUnlock() {
        var g = InputGate(); g.arm()
        _ = g.consume(down(53, 1)); _ = g.consume(.keyUp(code: 53))
        XCTAssertEqual(g.consume(down(53, 2)), .block)
    }
    func testLateEscapeStartsNewPair() {
        var g = InputGate(); g.arm()
        _ = g.consume(down(53, 1)); _ = g.consume(.keyUp(code: 53))
        _ = g.consume(down(53, 2)); _ = g.consume(.keyUp(code: 53))
        XCTAssertEqual(g.consume(down(53, 2.3)), .unlockAndBlock)
    }
    func testBoundaryInsideInterval() {
        var g = InputGate(); g.arm()
        _ = g.consume(down(53, 0)); _ = g.consume(.keyUp(code: 53))
        XCTAssertEqual(g.consume(down(53, InputGate.escapeInterval)), .unlockAndBlock)
    }
    func testOutsideInterval() {
        var g = InputGate(); g.arm()
        _ = g.consume(down(53, 0)); _ = g.consume(.keyUp(code: 53))
        XCTAssertEqual(g.consume(down(53, InputGate.escapeInterval + 0.0001)), .block)
    }
    func testClockRegressionCannotUnlock() {
        var g = InputGate(); g.arm()
        _ = g.consume(down(53, 2)); _ = g.consume(.keyUp(code: 53))
        XCTAssertEqual(g.consume(down(53, 1)), .block)
    }
    func testNonFiniteEscapeTimeCannotUnlock() {
        for time in [Double.nan, .infinity, -.infinity] {
            var g = InputGate(); g.arm()
            _ = g.consume(down(53, 1)); _ = g.consume(.keyUp(code: 53))
            XCTAssertEqual(g.consume(down(53, time)), .block)
        }
    }
    func testEscapeWithModifiersDoesNotUnlock() {
        var g = InputGate(); g.arm()
        _ = g.consume(down(53, 1)); _ = g.consume(.keyUp(code: 53))
        XCTAssertEqual(g.consume(down(53, 1.1, mods: .control)), .block)
    }
    func testUnrelatedKeyBreaksEscapePair() {
        var g = InputGate(); g.arm()
        _ = g.consume(down(53, 1)); _ = g.consume(.keyUp(code: 53)); _ = g.consume(down(0, 1.1))
        XCTAssertEqual(g.consume(down(53, 1.2)), .block)
    }
    func testMouseClickBreaksEscapePair() {
        var g = InputGate(); g.arm()
        _ = g.consume(down(53, 1)); _ = g.consume(.keyUp(code: 53)); _ = g.consume(.buttonDown(0))
        XCTAssertEqual(g.consume(down(53, 1.2)), .block)
    }
    func testScrollBreaksEscapePair() {
        var g = InputGate(); g.arm()
        _ = g.consume(down(53, 1)); _ = g.consume(.keyUp(code: 53)); _ = g.consume(.scroll)
        XCTAssertEqual(g.consume(down(53, 1.2)), .block)
    }
    func testModifierBreaksEscapePair() {
        var g = InputGate(); g.arm()
        _ = g.consume(down(53, 1)); _ = g.consume(.keyUp(code: 53))
        _ = g.consume(.flagsChanged(.control)); _ = g.consume(.flagsChanged([]))
        XCTAssertEqual(g.consume(down(53, 1.2)), .block)
    }
    func testPointerMotionDoesNotBreakEscapePair() {
        var g = InputGate(); g.arm()
        _ = g.consume(down(53, 1)); _ = g.consume(.keyUp(code: 53))
        XCTAssertEqual(g.consume(.pointerMoved), .pass)
        XCTAssertEqual(g.consume(down(53, 1.2)), .unlockAndBlock)
    }
    func testAllButtonsAreBlocked() {
        for button: UInt32 in 0...31 {
            var g = InputGate(); g.arm()
            XCTAssertEqual(g.consume(.buttonDown(button)), .block)
            XCTAssertEqual(g.consume(.buttonUp(button)), .block)
        }
    }
    func testDragScrollOtherBlocked() {
        var g = InputGate(); g.arm()
        for event: GuardInput in [.dragged, .scroll, .other] { XCTAssertEqual(g.consume(event), .block) }
    }
    func testNewModifiersBlocked() {
        var g = InputGate(); g.arm()
        XCTAssertEqual(g.consume(.flagsChanged(.command)), .block)
        XCTAssertEqual(g.consume(.flagsChanged([])), .block)
    }
    func testPreArmKeyReleasePassesExactlyOnce() {
        var g = InputGate(); g.arm(keys: [0])
        XCTAssertEqual(g.consume(.keyUp(code: 0)), .pass)
        XCTAssertEqual(g.consume(.keyUp(code: 0)), .block)
        XCTAssertTrue(g.heldKeys.isEmpty)
    }
    func testPreArmMouseReleasePassesExactlyOnce() {
        var g = InputGate(); g.arm(buttons: [0])
        XCTAssertEqual(g.consume(.buttonUp(0)), .pass)
        XCTAssertEqual(g.consume(.buttonUp(0)), .block)
    }
    func testPreArmModifierNeutralReleaseOnce() {
        var g = InputGate(); g.arm(modifiers: .control)
        XCTAssertEqual(g.consume(.flagsChanged([.control, .shift])), .block)
        XCTAssertEqual(g.consume(.flagsChanged(.shift)), .block)
        XCTAssertEqual(g.consume(.flagsChanged([])), .pass)
        XCTAssertEqual(g.consume(.flagsChanged([])), .block)
    }
    func testActivationOneReleaseIsNeverForwarded() {
        var g = InputGate(); g.arm(keys: [18], consumedKeys: [18])
        XCTAssertEqual(g.consume(.keyUp(code: 18)), .block)
    }
    func testDrainWaitsForAllKeysAndModifiers() {
        var g = InputGate(); g.arm()
        _ = g.consume(down(18, mods: .control))
        XCTAssertFalse(g.finishDrainIfNeutral())
        XCTAssertEqual(g.consume(.keyUp(code: 18)), .block)
        XCTAssertFalse(g.finishDrainIfNeutral())
        XCTAssertEqual(g.consume(.flagsChanged([])), .pass)
        XCTAssertTrue(g.finishDrainIfNeutral())
        XCTAssertEqual(g.phase, .idle)
    }
    func testDrainBlocksNewInputsUntilNeutral() {
        var g = InputGate(); g.arm(); g.beginDrain()
        XCTAssertEqual(g.consume(down(0)), .block)
        XCTAssertEqual(g.consume(.buttonDown(1)), .block)
        XCTAssertFalse(g.finishDrainIfNeutral())
        _ = g.consume(.keyUp(code: 0)); _ = g.consume(.buttonUp(1))
        XCTAssertTrue(g.finishDrainIfNeutral())
    }
    func testEscapeReleaseDoesNotLeakOnUnlock() {
        var g = InputGate(); g.arm()
        _ = g.consume(down(53, 1)); _ = g.consume(.keyUp(code: 53))
        _ = g.consume(down(53, 1.1))
        XCTAssertEqual(g.consume(.keyUp(code: 53)), .block)
        XCTAssertTrue(g.finishDrainIfNeutral())
    }
    func testDrainDoesNotUnlockTwice() {
        var g = InputGate(); g.arm(); g.beginDrain()
        XCTAssertEqual(g.consume(down(18, mods: .control)), .block)
    }
    func testManualLiftDrainsHeldMouse() {
        var g = InputGate(); g.arm(); _ = g.consume(.buttonDown(0)); g.beginDrain()
        XCTAssertFalse(g.finishDrainIfNeutral())
        XCTAssertEqual(g.consume(.buttonUp(0)), .block)
        XCTAssertTrue(g.finishDrainIfNeutral())
    }
    func testActiveCannotFinishDrain() { var g = InputGate(); g.arm(); XCTAssertFalse(g.finishDrainIfNeutral()) }
    func testIdleCannotBeginDrain() { var g = InputGate(); g.beginDrain(); XCTAssertEqual(g.phase, .idle) }
    func testResetIsIdempotentAndPassesInput() {
        var g = InputGate(); g.arm(); _ = g.consume(down(0)); g.reset(); g.reset()
        XCTAssertEqual(g.phase, .idle); XCTAssertTrue(g.neutral)
        XCTAssertEqual(g.consume(down(0)), .pass)
    }
    func testNewActivationHasNoOldEscapeMemory() {
        var g = InputGate(); g.arm(); _ = g.consume(down(53, 1)); g.reset(); g.arm()
        XCTAssertEqual(g.consume(down(53, 1.1)), .block)
    }
    func testRearmClearsHeldInputs() {
        var g = InputGate(); g.arm(keys: [0], buttons: [1], modifiers: .shift); g.arm()
        XCTAssertTrue(g.neutral)
    }
    func testTenThousandBlockedKeystrokes() {
        var g = InputGate(); g.arm()
        for i in 0..<10_000 {
            let code = UInt16(i % 18)
            XCTAssertEqual(g.consume(down(code, Double(i))), .block)
            XCTAssertEqual(g.consume(.keyUp(code: code)), .block)
        }
        XCTAssertEqual(g.phase, .active); XCTAssertTrue(g.neutral)
    }
    func testOneThousandFullCycles() {
        var g = InputGate()
        for i in 0..<1000 {
            g.arm(keys: [18], modifiers: .control, consumedKeys: [18])
            _ = g.consume(.keyUp(code: 18)); _ = g.consume(.flagsChanged([]))
            XCTAssertEqual(g.consume(down(18, Double(i), mods: .control)), .unlockAndBlock)
            _ = g.consume(.keyUp(code: 18)); _ = g.consume(.flagsChanged([]))
            XCTAssertTrue(g.finishDrainIfNeutral())
        }
    }
    func testMenuActivationReleasesAnOrdinaryPreheldOne() {
        var gate = InputGate()
        gate.arm(keys: [18])
        XCTAssertEqual(gate.consume(.keyUp(code: 18)), .pass)
        XCTAssertEqual(gate.consume(.keyUp(code: 18)), .block)
    }
    func testOnlyExplicitlyConsumedKeysLoseTheirPairedRelease() {
        var gate = InputGate()
        gate.arm(keys: [0, 18], consumedKeys: [18])
        XCTAssertEqual(gate.consume(.keyUp(code: 0)), .pass)
        XCTAssertEqual(gate.consume(.keyUp(code: 18)), .block)
    }

}
