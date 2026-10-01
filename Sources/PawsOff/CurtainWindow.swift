import AppKit
import PawsOffCore

final class CurtainWindow: NSWindow {
    let shieldView: ShieldView
    var allowsKeyFocus: Bool = true
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(screen: NSScreen, appearance: AppearanceSettings) {
        shieldView = ShieldView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: [.borderless],
                   backing: .buffered, defer: false)
        title = "PawsOff Curtain"
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        contentView = shieldView
        setFrame(screen.frame, display: false)
        shieldView.apply(appearance)
    }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
    func present() {
        orderFrontRegardless()
    }
    private var lastEscapeTime: TimeInterval = 0

    override func keyDown(with event: NSEvent) {
        if shieldView.isPasskeyPromptVisible {
            if event.keyCode == 53 { // Esc while passkey entry is shown
                shieldView.onCancelPasskey?()
                return
            }
            super.keyDown(with: event)
            return
        }
        if event.modifierFlags.contains(.control) && event.charactersIgnoringModifiers == "1" {
            shieldView.onDismiss?()
            return
        }
        if event.keyCode == 53 { // Esc
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastEscapeTime <= 0.65 {
                shieldView.onDismiss?()
                lastEscapeTime = 0
                return
            }
            lastEscapeTime = now
            return
        }
        lastEscapeTime = 0
    }

    override func keyUp(with event: NSEvent) {
        if shieldView.isPasskeyPromptVisible {
            super.keyUp(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        if shieldView.isPasskeyPromptVisible {
            super.flagsChanged(with: event)
        }
    }
}
