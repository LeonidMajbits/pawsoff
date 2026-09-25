import AppKit

final class MenuBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let panel: SettingsViewController
    private let curtain: CurtainController
    var onQuit: (() -> Void)?
    var shortcutReady = false { didSet { refresh() } }
    private var failure: String?

    init(settings: SettingsManager, curtain: CurtainController) {
        self.curtain = curtain
        panel = SettingsViewController(settings: settings)
        super.init()
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "PawsOff")
            if button.image == nil { button.title = "PawsOff" }
            button.image?.isTemplate = true
            button.target = self; button.action = #selector(togglePopover)
            button.toolTip = "PawsOff — Toggle Curtain: Ctrl+1"
        }
        popover.contentViewController = panel
        popover.behavior = .transient
        popover.animates = false
        panel.onDrop = { [weak self] in self?.dropFromMenu() }
        panel.onPermission = { [weak self] in
            self?.popover.performClose(nil)
            InputShield.requestAccessibilityPermission()
        }
        panel.onQuit = { [weak self] in self?.onQuit?() }
        refresh()
    }

    func setState(message: String?) {
        failure = message
        refresh()
    }
    func closePopover() { popover.performClose(nil) }
    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = item.button else { return }
        refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Do not activate PawsOff or replace the working app's key window.
    }
    private func dropFromMenu() {
        closePopover()
        DispatchQueue.main.async { [weak self] in self?.curtain.drop() }
    }
    private func refresh() {
        let message: String
        if curtain.isActive { message = "Guard active. Ctrl+1 or double Esc to dismiss." }
        else if curtain.isDraining { message = "Release all keys and mouse buttons…" }
        else if let failure { message = failure }
        else if !InputShield.permissionReady { message = "Grant Accessibility to guard inputs and drop curtain." }
        else if InputShield.secureInputEnabled { message = "Secure Event Input is on. Leave password field to drop curtain." }
        else if !shortcutReady { message = "Ready. The menu button and double Esc work." }
        else { message = "Ready. No lock, no password, no focus transfer." }
        let canDrop = !curtain.isActive && !curtain.isDraining && InputShield.permissionReady && !InputShield.secureInputEnabled
        panel.updateStatus(message, canDrop: canDrop,
                           showPermission: !InputShield.permissionReady)
        item.button?.appearsDisabled = false
        item.button?.toolTip = "PawsOff — " + message
    }
}

private final class SettingsViewController: NSViewController {
    private let settings: SettingsManager
    private let blur = NSSlider(value: 65, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let tint = NSSlider(value: 45, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let blurValue = NSTextField(labelWithString: "65%")
    private let tintValue = NSTextField(labelWithString: "45%")
    private let hudCheckbox = NSButton(checkboxWithTitle: "Show on-screen unlock card on drop", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "Ready")
    private let stack = NSStackView()
    private let drop = NSButton(title: "Drop Curtain Now", target: nil, action: nil)
    private let permission = NSButton(title: "Grant Accessibility…", target: nil, action: nil)
    var onDrop: (() -> Void)?
    var onPermission: (() -> Void)?
    var onQuit: (() -> Void)?

    init(settings: SettingsManager) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }
    override func loadView() {
        let background = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 334, height: 430))
        background.material = .popover; background.state = .active
        view = background
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 18)
        ])
        let title = NSTextField(labelWithString: "PawsOff")
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        stack.addArrangedSubview(title)
        let subtitle = NSTextField(labelWithString: "Quiet screen. Uninterrupted work.")
        subtitle.font = .systemFont(ofSize: 12); subtitle.textColor = .secondaryLabelColor
        stack.addArrangedSubview(subtitle)
        for (name, slider, value) in [("Blur", blur, blurValue), ("Tint (Darkness)", tint, tintValue)] {
            let line = NSStackView(views: [NSTextField(labelWithString: name), NSView(), value])
            line.orientation = .horizontal
            stack.addArrangedSubview(line)
            line.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            slider.isContinuous = true
            slider.target = self
            stack.addArrangedSubview(slider)
            slider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            slider.setAccessibilityLabel(name + " percentage")
            value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        }
        blur.action = #selector(blurChanged)
        tint.action = #selector(tintChanged)
        let cap = NSTextField(labelWithString: "100% tint = 82% black opacity. Never blackout.")
        cap.font = .systemFont(ofSize: 10.5); cap.textColor = .secondaryLabelColor
        stack.addArrangedSubview(cap)

        hudCheckbox.target = self
        hudCheckbox.action = #selector(hudToggled)
        hudCheckbox.font = .systemFont(ofSize: 12)
        stack.addArrangedSubview(hudCheckbox)

        let hudHint = NSTextField(labelWithString: "Uncheck for pure stealth curtain (experienced mode).")
        hudHint.font = .systemFont(ofSize: 10.5); hudHint.textColor = .secondaryLabelColor
        stack.addArrangedSubview(hudHint)

        let shortcut = NSTextField(labelWithString: "Toggle Curtain: Ctrl+1")
        shortcut.font = .systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(shortcut)
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 4
        stack.addArrangedSubview(status)
        status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        drop.bezelStyle = .rounded; drop.target = self; drop.action = #selector(dropPressed)
        stack.addArrangedSubview(drop)
        drop.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        permission.bezelStyle = .rounded; permission.target = self; permission.action = #selector(permissionPressed)
        stack.addArrangedSubview(permission)
        let quit = NSButton(title: "Quit PawsOff", target: self, action: #selector(quitPressed))
        quit.bezelStyle = .inline
        stack.addArrangedSubview(quit)
        updateValues()
        preferredContentSize = NSSize(width: 334, height: 480)
    }
    func updateStatus(_ text: String, canDrop: Bool, showPermission: Bool) {
        _ = view
        status.stringValue = text
        drop.isEnabled = canDrop
        permission.isHidden = !showPermission
        updateValues()
        view.layoutSubtreeIfNeeded()
        preferredContentSize = NSSize(width: 334, height: max(420, stack.fittingSize.height + 36))
    }
    private func updateValues() {
        blur.doubleValue = settings.appearance.blurPercent
        tint.doubleValue = settings.appearance.tintPercent
        blurValue.stringValue = "\(Int(blur.doubleValue.rounded()))%"
        tintValue.stringValue = "\(Int(tint.doubleValue.rounded()))%"
        hudCheckbox.state = settings.appearance.showHUD ? .on : .off
    }
    @objc private func blurChanged() { settings.setBlur(blur.doubleValue); updateValues() }
    @objc private func tintChanged() { settings.setTint(tint.doubleValue); updateValues() }
    @objc private func hudToggled() { settings.setShowHUD(hudCheckbox.state == .on) }
    @objc private func dropPressed() { onDrop?() }
    @objc private func permissionPressed() { onPermission?() }
    @objc private func quitPressed() { onQuit?() }
}
