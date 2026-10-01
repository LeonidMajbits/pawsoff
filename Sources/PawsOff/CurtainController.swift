import AppKit
import PawsOffCore

final class CurtainController: NSObject {
    private let settings: SettingsManager
    private let input = InputShield()
    private let power = PowerAssertionManager()
    private var windows: [UInt32: CurtainWindow] = [:]
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var heartbeatTimer: Timer?
    private var pointerTimer: Timer?
    private(set) var isActive = false
    private var previousApp: NSRunningApplication?
    var isDraining: Bool { !isActive && input.isRunning }
    var onStateChanged: ((String?) -> Void)?
    var onInputReleased: (() -> Void)?

    init(settings: SettingsManager) {
        self.settings = settings
        super.init()
        input.onUnlock = { [weak self] in self?.handleUnlockRequest() }
        input.onDrained = { [weak self] in
            guard let self else { return }
            guard !self.isActive else { return }
            self.input.stopImmediately()
            self.onInputReleased?()
            self.onStateChanged?(nil)
        }
        input.onFailure = { [weak self] message in self?.abort(message) }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshDisplays() })
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.isActive || self.input.isRunning else { return }
                self.abort("The OS slept, blanked its displays, or switched sessions. PawsOff is off; re-arm manually.")
            })
        }
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshDisplays() })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updateAppearance() })
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.input.mainHeartbeat()
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    func drop(fromHotkey: Bool = false) {
        precondition(Thread.isMainThread)
        guard !isActive && !input.isRunning else { return }
        guard !NSScreen.screens.isEmpty else {
            onStateChanged?("No active display is available.")
            return
        }

        previousApp = NSWorkspace.shared.frontmostApplication

        do {
            try power.acquire()
            settings.passkey.resetAttempts()
            input.isAwaitingPasskey = false

            // Optional Quartz session tap for low-level system modifier interception:
            if InputShield.permissionReady && !InputShield.secureInputEnabled {
                do {
                    try input.start(activationChordConsumed: fromHotkey)
                } catch {
                    NSLog("[PawsOff] Optional Quartz session tap failed: %@. Proceeding with window shield.", error.localizedDescription)
                }
            }

            NSCursor.hide()
            defer { NSCursor.unhide() }
            isActive = true
            refreshDisplays()
            guard isActive else {
                input.stopImmediately()
                power.release()
                return
            }

            // Activate PawsOff and make the curtain key so all keyboard and mouse events
            // are swallowed by CurtainWindow and ShieldView:
            NSApp.activate(ignoringOtherApps: true)
            if let keyWin = windows.values.first(where: { $0.screen == NSScreen.main }) ?? windows.values.first {
                keyWin.makeKeyAndOrderFront(nil)
                keyWin.makeFirstResponder(keyWin.shieldView)
            }

            NSCursor.setHiddenUntilMouseMoves(false)
            NSCursor.arrow.set()
            startPointerLocator()
            onStateChanged?(nil)
        } catch {
            NSLog("[PawsOff] drop() error: %@", error.localizedDescription)
            input.stopImmediately()
            power.release()
            isActive = false
            removeWindows()
            onStateChanged?("Failed to block keyboard: \(error.localizedDescription)")
        }
    }

    func lift() {
        precondition(Thread.isMainThread)
        guard isActive else { return }
        input.isAwaitingPasskey = false
        if input.isRunning {
            input.requestDrain()
        }
        isActive = false
        removeWindows()
        power.release()
        onStateChanged?(nil)

        // Seamlessly restore focus to whatever app was active before:
        if let prev = previousApp, !prev.isTerminated {
            prev.activate(options: [.activateIgnoringOtherApps])
        }
        previousApp = nil
    }

    func handleUnlockRequest() {
        if settings.passkey.isPasskeyEnabled {
            input.cancelDrain()
            promptForPasskey()
        } else {
            lift()
        }
    }

    func promptForPasskey() {
        guard isActive else { return }
        input.cancelDrain()
        input.isAwaitingPasskey = true
        settings.passkey.resetAttempts()
        for window in windows.values {
            window.shieldView.showPasskeyPrompt()
            window.orderFrontRegardless()
            window.makeKey()
            window.makeFirstResponder(window.shieldView.passkeyField)
        }
        onInputReleased?()
    }

    func cancelPasskeyPrompt() {
        input.isAwaitingPasskey = false
        settings.passkey.resetAttempts()
        for window in windows.values {
            window.shieldView.hidePasskeyPrompt()
            window.makeFirstResponder(window.shieldView)
        }
    }

    func emergencyLockdown() {
        NSLog("[PawsOff] Emergency lockout triggered. Handing off to macOS native login screen.")
        lift()
        PasskeyManager.triggerNativeMacLockScreen()
    }

    func updateAppearance() {
        for window in windows.values { window.shieldView.apply(settings.appearance) }
    }

    private func refreshDisplays() {
        guard isActive else { return }
        let screens = NSScreen.screens
        guard !screens.isEmpty else { abort("All displays disconnected; PawsOff is off."); return }
        var desired = Set<UInt32>()
        // Create/resize replacements first, then retire obsolete windows.
        for screen in screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                abort("Could not identify an active display; PawsOff is off."); return
            }
            let identifier = number.uint32Value
            desired.insert(identifier)
            let window: CurtainWindow
            if let existing = windows[identifier] {
                window = existing
                window.setFrame(screen.frame, display: true)
            } else {
                window = CurtainWindow(screen: screen, appearance: settings.appearance)
                window.shieldView.onDismiss = { [weak self] in self?.handleUnlockRequest() }
                window.shieldView.onPasskeySubmitted = { [weak self] pin in
                    guard let self else { return }
                    if self.settings.passkey.verify(pin: pin) {
                        self.lift()
                    } else {
                        if self.settings.passkey.isLockedOut {
                            for w in self.windows.values {
                                w.shieldView.showPasskeyError("Too many attempts. Locking macOS…")
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                                self?.emergencyLockdown()
                            }
                        } else {
                            let left = self.settings.passkey.remainingAttempts
                            for w in self.windows.values {
                                w.shieldView.showPasskeyError("Incorrect PIN (\(left) attempt\(left == 1 ? "" : "s") remaining)")
                            }
                        }
                    }
                }
                window.shieldView.onEmergencyLock = { [weak self] in
                    self?.emergencyLockdown()
                }
                window.shieldView.onCancelPasskey = { [weak self] in
                    self?.cancelPasskeyPrompt()
                }
                windows[identifier] = window
            }
            window.present()
        }
        for identifier in Array(windows.keys) where !desired.contains(identifier) {
            windows.removeValue(forKey: identifier)?.orderOut(nil)
        }
    }

    private func startPointerLocator() {
        pointerTimer?.invalidate()
        updatePointerLocator()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.updatePointerLocator()
        }
        timer.tolerance = 0.008
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }
    private func updatePointerLocator() {
        guard isActive else { return }
        let location = NSEvent.mouseLocation
        for window in windows.values {
            let point = window.shieldView.convert(window.convertPoint(fromScreen: location), from: nil)
            window.shieldView.updatePointerLocator(point)
        }
    }
    private func removeWindows() {
        pointerTimer?.invalidate(); pointerTimer = nil
        for window in windows.values { window.orderOut(nil) }
        windows.removeAll()
    }
    private func abort(_ reason: String) {
        isActive = false
        input.stopImmediately()
        removeWindows()
        power.release()
        onInputReleased?()
        onStateChanged?(reason)
    }
    func shutdown() {
        input.stopImmediately()
        isActive = false
        removeWindows()
        power.release()
        heartbeatTimer?.invalidate(); heartbeatTimer = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll(); workspaceObservers.removeAll()
    }
}
