import Foundation
import CoreGraphics
import ApplicationServices
import Carbon
import Darwin
import PawsOffCore

private final class TapContext {
    weak var owner: InputShield?
    let generation: UInt64
    init(owner: InputShield, generation: UInt64) {
        self.owner = owner; self.generation = generation
    }
}

/// Active Quartz session filter. The callback runs on its own run loop, not AppKit's.
/// Lifecycle calls are main-thread-only; shared policy/resources are protected by lock.
final class InputShield {
    var onUnlock: (() -> Void)?
    var onDrained: (() -> Void)?
    var onFailure: ((String) -> Void)?
    private let lock = NSLock()
    private var gate = InputGate()
    private var generation: UInt64 = 0
    private var tap: CFMachPort?
    private var workerLoop: CFRunLoop?
    private var running = false
    private var failureSent = false
    private var drainedSent = false
    private var heartbeat = ProcessInfo.processInfo.systemUptime
    private var drainStarted: Double?
    private var awaitingPasskey = false
    var isAwaitingPasskey: Bool {
        get { locked { awaitingPasskey } }
        set { locked { awaitingPasskey = newValue } }
    }

    private static let types: [CGEventType] = [
        .keyDown, .keyUp, .flagsChanged,
        .leftMouseDown, .leftMouseUp, .leftMouseDragged,
        .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged,
        .mouseMoved, .scrollWheel, .tabletPointer, .tabletProximity
    ]
    private static let requiredMask: CGEventMask = types.reduce(0) {
        $0 | (CGEventMask(1) << $1.rawValue)
    }
    // NSEvent.EventType.systemDefined is 14. This best-effort extra mask catches
    // consumer/media keys where Quartz exposes them; it is NOT a power-button guard.
    private static let requestedMask = requiredMask | (CGEventMask(1) << 14)
    private static let modifierKeys: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    var isRunning: Bool { locked { running } }

    static var permissionReady: Bool { AXIsProcessTrusted() }
    static var secureInputEnabled: Bool { IsSecureEventInputEnabled() }

    static func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func mainHeartbeat() {
        locked { heartbeat = ProcessInfo.processInfo.systemUptime }
    }

    func start(activationChordConsumed: Bool = false) throws {
        precondition(Thread.isMainThread)
        guard !isRunning else { throw PawsOffError.message("Input shield is still finishing its previous session.") }
        guard Self.permissionReady else {
            throw PawsOffError.message("Accessibility permission is required. Grant it to this PawsOff.app, then relaunch.")
        }
        guard !Self.secureInputEnabled else {
            throw PawsOffError.message("Secure Event Input is enabled. Leave the password field or turn off Terminal’s Secure Keyboard Entry first.")
        }
        let token = locked { () -> UInt64 in
            generation &+= 1; failureSent = false; drainedSent = false
            drainStarted = nil; heartbeat = ProcessInfo.processInfo.systemUptime
            return generation
        }
        let context = TapContext(owner: self, generation: token)
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: Self.requestedMask,
            callback: { _, type, event, pointer in
                guard let pointer else { return Unmanaged.passUnretained(event) }
                let context = Unmanaged<TapContext>.fromOpaque(pointer).takeUnretainedValue()
                guard let owner = context.owner else { return Unmanaged.passUnretained(event) }
                // nil is the suppression signal: NEVER coalesce a handler result.
                return owner.handle(type, event, token: context.generation)
            }, userInfo: Unmanaged.passUnretained(context).toOpaque()
        ) else {
            NSLog("[PawsOff] CGEvent.tapCreate returned nil")
            throw PawsOffError.message("macOS refused the input tap. Check Accessibility and Input Monitoring for this exact app, then relaunch.")
        }
        CGEvent.tapEnable(tap: newTap, enable: false)
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            CFMachPortInvalidate(newTap)
            throw PawsOffError.message("Could not create the input run-loop source.")
        }
        do {
            try Self.verifyGrantedMask()
        } catch {
            NSLog("[PawsOff] verifyGrantedMask failed: %@", error.localizedDescription)
            CFMachPortInvalidate(newTap)
            throw error
        }

        let initialKeys = Set((UInt16(0)...UInt16(127)).filter {
            !Self.modifierKeys.contains($0) && CGEventSource.keyState(.hidSystemState, key: $0)
        })
        let initialButtons = Set([CGMouseButton.left, .right, .center].filter {
            CGEventSource.buttonState(.hidSystemState, button: $0)
        }.map { $0.rawValue })
        let initialModifiers = Self.modifiers(CGEventSource.flagsState(.hidSystemState))
        locked {
            gate.arm(keys: initialKeys, buttons: initialButtons, modifiers: initialModifiers,
                     consumedKeys: activationChordConsumed ? [InputGate.oneKey] : [])
            tap = newTap; running = true
        }

        let ready = DispatchSemaphore(value: 0)
        let worker = Thread { [self, context, newTap, source] in
            autoreleasepool {
                let loop = CFRunLoopGetCurrent()!
                let valid = locked { () -> Bool in
                    guard generation == token && running else { return false }
                    workerLoop = loop
                    return true
                }
                guard valid else { ready.signal(); return }
                CFRunLoopAddSource(loop, source, .commonModes)
                let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault,
                    CFAbsoluteTimeGetCurrent() + 0.10, 0.10, 0, 0) { [weak self] _ in
                    self?.poll(token: token)
                }!
                CFRunLoopAddTimer(loop, timer, .commonModes)
                CGEvent.tapEnable(tap: newTap, enable: true)
                ready.signal()
                withExtendedLifetime(context) { CFRunLoopRun() }
                CGEvent.tapEnable(tap: newTap, enable: false)
                CFRunLoopTimerInvalidate(timer)
                CFRunLoopRemoveSource(loop, source, .commonModes)
                CFMachPortInvalidate(newTap)
            }
        }
        worker.name = "PawsOff.InputShield"
        worker.qualityOfService = .userInteractive
        worker.start()
        guard ready.wait(timeout: .now() + 2) == .success,
              CGEvent.tapIsEnabled(tap: newTap) else {
            stopImmediately()
            throw PawsOffError.message("Input shield did not start. Nothing has been covered.")
        }
    }

    func requestDrain() {
        precondition(Thread.isMainThread)
        locked {
            guard running else { return }
            gate.beginDrain()
            if drainStarted == nil { drainStarted = ProcessInfo.processInfo.systemUptime }
        }
    }

    func cancelDrain() {
        precondition(Thread.isMainThread)
        locked {
            drainStarted = nil
            drainedSent = false
            gate.cancelDrain()
        }
    }

    func stopImmediately() {
        precondition(Thread.isMainThread)
        let resources = locked { () -> (CFMachPort?, CFRunLoop?) in
            generation &+= 1
            running = false; gate.reset(); drainStarted = nil
            awaitingPasskey = false
            let values = (tap, workerLoop)
            tap = nil; workerLoop = nil
            return values
        }
        if let tap = resources.0 {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let loop = resources.1 {
            // A scheduled stop also handles cancellation just before CFRunLoopRun.
            CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { CFRunLoopStop(loop) }
            CFRunLoopStop(loop)
            CFRunLoopWakeUp(loop)
        }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent,
                        token: UInt64) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let activeTap = tap { CGEvent.tapEnable(tap: activeTap, enable: true) }
            failOpen("macOS disabled the event tap; the curtain was removed. Re-arm manually.", token: token)
            return Unmanaged.passUnretained(event)
        }
        if locked({ awaitingPasskey }) {
            // While awaiting passkey entry, allow keyboard and mouse events to route
            // to PawsOff's frontmost key CurtainWindow so the user can interact with the PIN field.
            return Unmanaged.passUnretained(event)
        }
        let input: GuardInput
        switch type {
        case .keyDown:
            input = .keyDown(code: UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode)),
                repeating: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                modifiers: Self.modifiers(event.flags),
                time: Double(event.timestamp) / 1_000_000_000)
        case .keyUp:
            input = .keyUp(code: UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode)))
        case .flagsChanged: input = .flagsChanged(Self.modifiers(event.flags))
        case .leftMouseDown: input = .buttonDown(0)
        case .leftMouseUp: input = .buttonUp(0)
        case .rightMouseDown: input = .buttonDown(1)
        case .rightMouseUp: input = .buttonUp(1)
        case .otherMouseDown:
            input = .buttonDown(UInt32(clamping: event.getIntegerValueField(.mouseEventButtonNumber)))
        case .otherMouseUp:
            input = .buttonUp(UInt32(clamping: event.getIntegerValueField(.mouseEventButtonNumber)))
        case .mouseMoved: input = .pointerMoved
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: input = .dragged
        case .scrollWheel: input = .scroll
        default: input = .other
        }
        let decision = locked { () -> GateDecision in
            guard running && generation == token && !failureSent else { return .pass }
            let result = gate.consume(input)
            if result == .unlockAndBlock { drainStarted = ProcessInfo.processInfo.systemUptime }
            return result
        }
        if decision == .unlockAndBlock {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCurrent(token) else { return }
                self.onUnlock?()
            }
        }
        return decision == .pass ? Unmanaged.passUnretained(event) : nil
    }

    private func poll(token: UInt64) {
        let now = ProcessInfo.processInfo.systemUptime
        let snapshot = locked { (generation == token && running, heartbeat, tap, failureSent, drainStarted) }
        guard snapshot.0 else { return }
        // If the UI is wedged, disabling the tap alone leaves an unresponsive overlay.
        // Exit ONLY PawsOff; WindowServer and IOKit then reclaim its windows/assertions.
        if now - snapshot.1 > 3.0 { Darwin._exit(70) }
        guard !snapshot.3 else { return }
        guard Self.permissionReady, !Self.secureInputEnabled else {
            failOpen("Input permission changed or Secure Event Input began; the curtain was removed.", token: token)
            return
        }
        guard let tap = snapshot.2, CGEvent.tapIsEnabled(tap: tap) else {
            failOpen("Input tap is no longer enabled; the curtain was removed.", token: token)
            return
        }
        if let started = snapshot.4 {
            if now - started > 5 {
                failOpen("Release drain exceeded five seconds. PawsOff released input; check for a held key or button.", token: token)
                return
            }
            // Do not infer releases from physical polling: preserve key-down/up pairing.
            // Waiting at least 100 ms also absorbs the unlock event's queued tail.
            let finished = locked { () -> Bool in
                guard generation == token && !drainedSent && now - started >= 0.10 else { return false }
                guard gate.finishDrainIfNeutral() else { return false }
                drainedSent = true
                return true
            }
            if finished {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isCurrent(token) else { return }
                    self.onDrained?()
                }
            }
        }
    }

    private func failOpen(_ message: String, token: UInt64) {
        let resource = locked { () -> CFMachPort? in
            guard generation == token && running && !failureSent else { return nil }
            failureSent = true; gate.reset()
            return tap
        }
        guard let resource else { return }
        CGEvent.tapEnable(tap: resource, enable: false)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrent(token) else { return }
            self.onFailure?(message)
        }
    }

    private func isCurrent(_ token: UInt64) -> Bool { locked { generation == token && running } }
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }; return body()
    }

    private static func modifiers(_ flags: CGEventFlags) -> Modifiers {
        var result: Modifiers = []
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskSecondaryFn) { result.insert(.function) }
        return result
    }

    private static func verifyGrantedMask() throws {
        // CGEventTapCreate may silently remove unauthorized mask bits. Do not accept
        // a mouse-only tap and then display a misleading "protected" curtain.
        let capacity: UInt32 = 512
        let entries = UnsafeMutablePointer<CGEventTapInformation>.allocate(capacity: Int(capacity))
        defer { entries.deallocate() }
        var count: UInt32 = 0
        let status = CGGetEventTapList(capacity, entries, &count)
        guard status == .success, count <= capacity else {
            throw PawsOffError.message("Could not verify the input tap’s granted event mask.")
        }
        for index in 0..<Int(count) {
            let entry = entries[index]
            if entry.tappingProcess == getpid(), (entry.tapPoint == .cghidEventTap || entry.tapPoint == .cgSessionEventTap),
               entry.options == .defaultTap,
               entry.eventsOfInterest & requiredMask == requiredMask { return }
        }
        throw PawsOffError.message("macOS did not grant the full keyboard/mouse mask. Check Accessibility and Input Monitoring, then relaunch.")
    }
}
