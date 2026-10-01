import AppKit
import QuartzCore
import PawsOffCore

final class ShieldView: NSView {
    var onDismiss: (() -> Void)?
    var onPasskeySubmitted: ((String) -> Void)?
    var onEmergencyLock: (() -> Void)?
    var onCancelPasskey: (() -> Void)?

    private let frost = NSVisualEffectView()
    private let tint = NSView()
    private let badge = NSView()
    private let badgeStack = NSStackView()
    private let pointerLocator = CAShapeLayer()
    private var previousPointer: NSPoint?
    private let titleLabel = NSTextField(labelWithString: "🐾  PawsOff Active")
    private let hintLabel = NSTextField(labelWithString: "Press Ctrl+1 to Dismiss  •  or double Esc")
    private let dismissButton = NSButton(title: "Unlock Screen", target: nil, action: nil)

    let passkeyField = NSSecureTextField()
    var isPasskeyPromptVisible: Bool { !passkeyField.isHidden }
    private let passkeyErrorLabel = NSTextField(labelWithString: "")
    private let passkeyButtonsRow = NSStackView()
    private let passkeySubmitButton = NSButton(title: "Unlock", target: nil, action: nil)
    private let cancelPasskeyButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let forgotPasskeyButton = NSButton(title: "Forgot Passkey (Use Mac Password)", target: nil, action: nil)

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
        badge.layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.82).cgColor
        badge.layer?.borderWidth = 0.5
        badge.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)

        badgeStack.orientation = .vertical
        badgeStack.alignment = .centerX
        badgeStack.spacing = 8
        badgeStack.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(badgeStack)

        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center

        hintLabel.font = .systemFont(ofSize: 12, weight: .medium)
        hintLabel.textColor = .white.withAlphaComponent(0.86)
        hintLabel.alignment = .center
        hintLabel.lineBreakMode = .byWordWrapping
        hintLabel.maximumNumberOfLines = 0

        badgeStack.addArrangedSubview(titleLabel)
        badgeStack.addArrangedSubview(hintLabel)

        dismissButton.bezelStyle = .rounded
        dismissButton.target = self
        dismissButton.action = #selector(dismissClicked)
        badgeStack.addArrangedSubview(dismissButton)

        // Passkey controls
        passkeyField.font = .systemFont(ofSize: 14)
        passkeyField.alignment = .center
        passkeyField.placeholderString = "PIN / Passkey"
        passkeyField.target = self
        passkeyField.action = #selector(submitPasskeyClicked)
        passkeyField.isHidden = true
        badgeStack.addArrangedSubview(passkeyField)

        passkeyErrorLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        passkeyErrorLabel.textColor = NSColor(calibratedRed: 1.0, green: 0.35, blue: 0.35, alpha: 1.0)
        passkeyErrorLabel.alignment = .center
        passkeyErrorLabel.maximumNumberOfLines = 2
        passkeyErrorLabel.isHidden = true
        badgeStack.addArrangedSubview(passkeyErrorLabel)

        passkeyButtonsRow.orientation = .horizontal
        passkeyButtonsRow.spacing = 10
        passkeyButtonsRow.alignment = .centerY
        passkeyButtonsRow.isHidden = true

        cancelPasskeyButton.bezelStyle = .rounded
        cancelPasskeyButton.target = self
        cancelPasskeyButton.action = #selector(cancelPasskeyClicked)
        passkeyButtonsRow.addArrangedSubview(cancelPasskeyButton)

        passkeySubmitButton.bezelStyle = .rounded
        passkeySubmitButton.target = self
        passkeySubmitButton.action = #selector(submitPasskeyClicked)
        passkeySubmitButton.keyEquivalent = "\r"
        passkeyButtonsRow.addArrangedSubview(passkeySubmitButton)

        badgeStack.addArrangedSubview(passkeyButtonsRow)

        forgotPasskeyButton.bezelStyle = .inline
        forgotPasskeyButton.target = self
        forgotPasskeyButton.action = #selector(forgotPasskeyClicked)
        forgotPasskeyButton.contentTintColor = NSColor.white.withAlphaComponent(0.75)
        forgotPasskeyButton.font = .systemFont(ofSize: 11)
        forgotPasskeyButton.isHidden = true
        badgeStack.addArrangedSubview(forgotPasskeyButton)

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
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
            badge.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -32),

            badgeStack.topAnchor.constraint(equalTo: badge.topAnchor, constant: 16),
            badgeStack.bottomAnchor.constraint(equalTo: badge.bottomAnchor, constant: -16),
            badgeStack.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 22),
            badgeStack.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -22),

            passkeyField.widthAnchor.constraint(equalToConstant: 200),
            passkeyField.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    required init?(coder: NSCoder) { nil }

    private var showHUDOnDrop: Bool = true

    func apply(_ value: AppearanceSettings) {
        showHUDOnDrop = value.showHUD
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

    func showPasskeyPrompt() {
        badge.isHidden = false
        titleLabel.stringValue = "🔒  Enterprise Shield"
        hintLabel.stringValue = "Enter Passkey / PIN to unlock"
        dismissButton.isHidden = true
        passkeyField.isHidden = false
        passkeyField.stringValue = ""
        passkeyErrorLabel.isHidden = true
        passkeyErrorLabel.stringValue = ""
        passkeySubmitButton.isHidden = false
        cancelPasskeyButton.isHidden = false
        forgotPasskeyButton.isHidden = false
        passkeyButtonsRow.isHidden = false
        badge.layoutSubtreeIfNeeded()
        window?.makeFirstResponder(passkeyField)
    }

    func hidePasskeyPrompt() {
        titleLabel.stringValue = "🐾  PawsOff Active"
        hintLabel.stringValue = "Press Ctrl+1 to Dismiss  •  or double Esc"
        dismissButton.isHidden = false
        passkeyField.isHidden = true
        passkeyField.stringValue = ""
        passkeyErrorLabel.isHidden = true
        passkeyErrorLabel.stringValue = ""
        passkeySubmitButton.isHidden = true
        cancelPasskeyButton.isHidden = true
        forgotPasskeyButton.isHidden = true
        passkeyButtonsRow.isHidden = true
        badge.isHidden = !showHUDOnDrop
        badge.layoutSubtreeIfNeeded()
    }

    func showPasskeyError(_ message: String) {
        passkeyErrorLabel.stringValue = message
        passkeyErrorLabel.isHidden = false
        passkeyField.stringValue = ""
        shakeBadge()
    }

    func shakeBadge() {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.duration = 0.35
        animation.values = [-10.0, 10.0, -7.0, 7.0, -3.0, 3.0, 0.0]
        badge.layer?.add(animation, forKey: "shake")
    }

    @objc private func dismissClicked() {
        onDismiss?()
    }

    @objc private func submitPasskeyClicked() {
        let pin = passkeyField.stringValue
        guard !pin.isEmpty else { return }
        onPasskeySubmitted?(pin)
    }

    @objc private func cancelPasskeyClicked() {
        onCancelPasskey?()
    }

    @objc private func forgotPasskeyClicked() {
        onEmergencyLock?()
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        if !badge.isHidden {
            let pointInBadge = badge.convert(point, from: self)
            if badge.bounds.contains(pointInBadge) {
                let controls: [NSView] = [
                    dismissButton, passkeyField, passkeySubmitButton,
                    cancelPasskeyButton, forgotPasskeyButton
                ]
                for control in controls where !control.isHidden {
                    let pointInControl = control.convert(pointInBadge, from: badge)
                    if control.bounds.contains(pointInControl) {
                        return control
                    }
                }
                return badge
            }
        }
        return bounds.contains(point) ? self : nil
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }

    private var lastEscapeTime: TimeInterval = 0

    override func keyDown(with event: NSEvent) {
        if !passkeyField.isHidden {
            if event.keyCode == 53 { // Esc
                onCancelPasskey?()
                return
            }
            return
        }
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
