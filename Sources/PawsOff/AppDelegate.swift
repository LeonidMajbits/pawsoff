import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsManager()
    private let hotkey = HotkeyManager()
    private var curtain: CurtainController!
    private var menu: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        curtain = CurtainController(settings: settings)
        menu = MenuBarController(settings: settings, curtain: curtain)
        curtain.onStateChanged = { [weak self] message in self?.menu.setState(message: message) }
        curtain.onInputReleased = { [weak self] in self?.hotkey.resetLatch() }
        settings.onChange = { [weak self] _ in self?.curtain.updateAppearance() }
        menu.onQuit = { NSApp.terminate(nil) }
        hotkey.onToggle = { [weak self] in
            guard let self else { return }
            if self.curtain.isActive {
                self.curtain.handleUnlockRequest()
                return
            }
            guard !self.curtain.isDraining else { return }
            self.menu.closePopover()
            self.curtain.drop(fromHotkey: true)
        }
        do {
            try hotkey.register()
            menu.shortcutReady = true
        } catch {
            NSLog("[PawsOff] hotkey.register() failed: %@", error.localizedDescription)
            menu.setState(message: error.localizedDescription)
        }
        TutorialController.shared.onProtect = { [weak self] in
            guard let self else { return }
            self.menu.closePopover()
            self.curtain.drop(fromHotkey: false)
        }
        if settings.shouldShowTutorialOnLaunch {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                TutorialController.shared.show(settings: self.settings)
            }
        }
        // Launch idle. Never block input, request TCC, or drop a curtain automatically.
    }
    func applicationWillTerminate(_ notification: Notification) {
        curtain?.shutdown()
        hotkey.unregister()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
