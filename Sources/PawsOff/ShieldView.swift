import AppKit
import QuartzCore
import PawsOffCore

final class ShieldView: NSView {
    var onDismiss: (() -> Void)?
    private let frost = NSVisualEffectView()
    private let tint = NSView()
    private let badge = NSView()
    private let pointerLocator = CAShapeLayer()
    private var previousPointer: NSPoint?
    private let titleLabel = NSTextField(labelWithString: "PawsOff Active")
    private let hintLabel = NSTextField(labelWithString: "Press Ctrl+1 or double-tap Esc to dismiss")
    private let subLabel = NSTextField(labelWithString: "Keyboard and mouse clicks suppressed")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        frost.blendingMode = .behindWindow
        frost.material = .underWindowBackground
        frost.state = .active
        frost.appearance = NSAppearance(named: .aqua)
        frost.frame = bounds; frost.autoresizingMask = [.width, .height]
        addSubview(frost)
        tint.wantsLayer = true
        tint.frame = bounds; tint.autoresizingMask = [.width, .height]
        addSubview(tint)
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 15
        badge.layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.76).cgColor
        badge.layer?.borderWidth = 0.5
        badge.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .white
        hintLabel.font = .systemFont(ofSize: 12, weight: .medium)
        hintLabel.textColor = .white.withAlphaComponent(0.86)
        subLabel.font = .systemFont(ofSize: 11, weight: .regular)
        subLabel.textColor = .white.withAlphaComponent(0.65)
        for label in [titleLabel, hintLabel, subLabel] {
            label.alignment = .center
            label.lineBreakMode = .byWordWrapping
            label.maximumNumberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            badge.addSubview(label)
        }
        // A small locator remains visible even if the formerly focused app keeps
        // its own cursor hidden. It does not need focus or alter foreign hide counts.
        pointerLocator.path = CGPath(ellipseIn: CGRect(x: -10, y: -10, width: 20, height: 20), transform: nil)
        pointerLocator.fillColor = NSColor.clear.cgColor
        pointerLocator.strokeColor = NSColor.white.cgColor
        pointerLocator.lineWidth = 1.5
        pointerLocator.shadowColor = NSColor.black.cgColor
        pointerLocator.shadowOpacity = 1
        pointerLocator.shadowRadius = 1.5
        pointerLocator.shadowOffset = .zero
        pointerLocator.zPosition = 1000
        pointerLocator.isHidden = true
        layer?.addSublayer(pointerLocator)
        NSLayoutConstraint.activate([
            badge.centerXAnchor.constraint(equalTo: centerXAnchor),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -24),
            titleLabel.topAnchor.constraint(equalTo: badge.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 22),
            titleLabel.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -22),
            hintLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 7),
            hintLabel.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 22),
            hintLabel.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -22),
            subLabel.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 6),
            subLabel.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 22),
            subLabel.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -22),
            subLabel.bottomAnchor.constraint(equalTo: badge.bottomAnchor, constant: -16)
        ])
    }
    required init?(coder: NSCoder) { nil }

    func apply(_ value: AppearanceSettings) {
        // A disabled transparency effect may become opaque on macOS. Remove it instead
        // of allowing an accessibility setting to defeat the non-blackout invariant.
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        frost.isHidden = reduce || value.blurOpacity == 0
        frost.alphaValue = reduce ? 0 : CGFloat(value.blurOpacity)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(CGFloat(value.tintOpacity)).cgColor
        CATransaction.commit()
        badge.isHidden = !value.showHUD
    }

    func updatePointerLocator(_ point: NSPoint) {
        let inside = bounds.contains(point)
        guard previousPointer != point || pointerLocator.isHidden == inside else { return }
        previousPointer = point
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pointerLocator.isHidden = !inside
        pointerLocator.position = point
        CATransaction.commit()
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        return bounds.contains(point) ? self : nil
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }

    private var lastEscapeTime: TimeInterval = 0

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) && event.charactersIgnoringModifiers == "1" {
            onDismiss?()
            return
        }
        if event.keyCode == 53 { // Esc
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastEscapeTime <= 0.65 {
                onDismiss?()
                lastEscapeTime = 0
                return
            }
            lastEscapeTime = now
            return
        }
        lastEscapeTime = 0
    }
    override func keyUp(with event: NSEvent) {}
    override func flagsChanged(with event: NSEvent) {}
    override func performKeyEquivalent(with event: NSEvent) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseMoved(with event: NSEvent) { NSCursor.arrow.set() }
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func rightMouseDragged(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func otherMouseUp(with event: NSEvent) {}
    override func otherMouseDragged(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
    override func magnify(with event: NSEvent) {}
    override func rotate(with event: NSEvent) {}
    override func swipe(with event: NSEvent) {}
    override func smartMagnify(with event: NSEvent) {}
    override func pressureChange(with event: NSEvent) {}
    override func tabletPoint(with event: NSEvent) {}
    override func tabletProximity(with event: NSEvent) {}
}
