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
    var isDraining: Bool { !isActive && input.isRunning }
    var onStateChanged: ((String?) -> Void)?
    var onInputReleased: (() -> Void)?

    init(settings: SettingsManager) {
        self.settings = settings
        super.init()
        input.onUnlock = { [weak self] in self?.lift() }
        input.onDrained = { [weak self] in
            guard let self else { return }
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
                guard let self, self.input.isRunning else { return }
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
        guard InputShield.permissionReady else {
            onStateChanged?("Accessibility permission is required to guard inputs.")
            return
        }
        guard !InputShield.secureInputEnabled else {
            onStateChanged?("Secure Event Input is active; unable to intercept events.")
            return
        }
        do {
            try power.acquire()
            do {
                try input.start(activationChordConsumed: fromHotkey)
            } catch {
                power.release()
                onStateChanged?("Input shield failed to start: \(error.localizedDescription)")
                return
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
            NSCursor.setHiddenUntilMouseMoves(false)
            NSCursor.arrow.set()
            startPointerLocator()
            onStateChanged?(nil)
        } catch {
            abort(error.localizedDescription)
        }
    }

    func lift() {
        precondition(Thread.isMainThread)
        guard isActive else { return }
        if input.isRunning {
            input.requestDrain()
        }
        isActive = false
        removeWindows()
        power.release()
        onStateChanged?(nil)
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
                window.shieldView.onDismiss = { [weak self] in self?.lift() }
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
