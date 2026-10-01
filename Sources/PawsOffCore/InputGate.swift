import Foundation

public struct Modifiers: OptionSet, Equatable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let control = Modifiers(rawValue: 1 << 0)
    public static let shift = Modifiers(rawValue: 1 << 1)
    public static let option = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)
    public static let function = Modifiers(rawValue: 1 << 4)
    // Caps Lock is deliberately not a held modifier. It must not trap the exit drain.
}

public enum GuardInput: Equatable {
    case keyDown(code: UInt16, repeating: Bool, modifiers: Modifiers, time: Double)
    case keyUp(code: UInt16)
    case flagsChanged(Modifiers)
    case buttonDown(UInt32), buttonUp(UInt32)
    case pointerMoved, dragged, scroll, other
}

public enum GateDecision: Equatable { case pass, block, unlockAndBlock }
public enum GatePhase: String { case idle, active, draining }

/// Deterministic input policy. The native adapter serializes access with one short lock.
/// No text, Unicode input, window titles, or event history are retained.
public struct InputGate {
    public static let oneKey: UInt16 = 18      // kVK_ANSI_1: physical top-row 1 key
    public static let escapeKey: UInt16 = 53   // kVK_Escape
    public static let escapeInterval = 0.65
    public private(set) var phase: GatePhase = .idle
    public private(set) var heldKeys = Set<UInt16>()
    public private(set) var heldButtons = Set<UInt32>()
    public private(set) var modifiers: Modifiers = []
    private var initialReleases = Set<UInt16>()
    private var initialButtonReleases = Set<UInt32>()
    private var owesInitialModifierRelease = false
    private var lastEscape: Double?

    public init() {}
    public var neutral: Bool { heldKeys.isEmpty && heldButtons.isEmpty && modifiers.isEmpty }

    public mutating func arm(keys: Set<UInt16> = [], buttons: Set<UInt32> = [],
                             modifiers: Modifiers = [], consumedKeys: Set<UInt16> = []) {
        reset()
        phase = .active
        heldKeys = keys; heldButtons = buttons; self.modifiers = modifiers
        // Release already-delivered downs exactly once to avoid stuck keys/drags.
        // Carbon-consumed activation keys have no delivered down to pair with.
        // Menu activation must still release an ordinary pre-held 1 key.
        initialReleases = keys.subtracting(consumedKeys)
        initialButtonReleases = buttons
        owesInitialModifierRelease = !modifiers.isEmpty
    }

    public mutating func beginDrain() {
        guard phase == .active else { return }
        phase = .draining
        lastEscape = nil
    }
    public mutating func cancelDrain() {
        guard phase == .draining else { return }
        phase = .active
        lastEscape = nil
    }
    public mutating func reset() { self = InputGate() }

    /// Called after all tracked physical releases, after at least a short drain interval.
    /// Removing the native event tap is the adapter's job, never the callback's job.
    public mutating func finishDrainIfNeutral() -> Bool {
        guard phase == .draining && neutral else { return false }
        reset()
        return true
    }

    public mutating func consume(_ input: GuardInput) -> GateDecision {
        guard phase != .idle else { return .pass }
        switch input {
        case .pointerMoved:
            // Keep the native pointer live. The top-level curtain absorbs AppKit motion.
            return .pass
        case .keyDown(let code, let repeating, let mods, let time):
            let fresh = !repeating && !heldKeys.contains(code)
            heldKeys.insert(code); modifiers = mods
            guard phase == .active else { return .block }
            guard fresh else { return .block }
            if code == Self.oneKey && mods == .control {
                beginDrain()
                return .unlockAndBlock
            }
            if code == Self.escapeKey && mods.isEmpty && time.isFinite {
                if let last = lastEscape, time >= last, time - last <= Self.escapeInterval {
                    beginDrain()
                    return .unlockAndBlock
                }
                lastEscape = time
            } else {
                lastEscape = nil
            }
            return .block
        case .keyUp(let code):
            heldKeys.remove(code)
            return initialReleases.remove(code) != nil ? .pass : .block
        case .flagsChanged(let mods):
            modifiers = mods
            if !mods.isEmpty { lastEscape = nil }
            // Only a neutral release is passed, never a newly pressed modifier.
            if mods.isEmpty && (owesInitialModifierRelease || phase == .draining) {
                owesInitialModifierRelease = false
                return .pass
            }
            return .block
        case .buttonDown(let button):
            heldButtons.insert(button); lastEscape = nil
            return .block
        case .buttonUp(let button):
            heldButtons.remove(button)
            return initialButtonReleases.remove(button) != nil ? .pass : .block
        case .scroll, .dragged, .other:
            lastEscape = nil
            return .block
        }
    }
}
