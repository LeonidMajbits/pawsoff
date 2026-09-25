import AppKit
import PawsOffCore

final class CurtainWindow: NSWindow {
    let shieldView: ShieldView
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

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
        // Explicitly cover entire display bounds including menu bar and Dock
        setFrame(screen.frame, display: false)
        shieldView.apply(appearance)
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    func present() {
        orderFrontRegardless() // Never makeKey, activate, or steal focus from background apps
    }
}
