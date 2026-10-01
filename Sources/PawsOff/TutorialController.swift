import AppKit

final class TutorialController: NSObject, NSWindowDelegate {
    static let shared = TutorialController()

    private var window: NSWindow?
    private var settings: SettingsManager?
    private let doNotShowCheckbox = NSButton(checkboxWithTitle: "Do not show this guide on launch", target: nil, action: nil)

    func show(settings: SettingsManager) {
        self.settings = settings
        if let existing = window {
            doNotShowCheckbox.state = settings.shouldShowTutorialOnLaunch ? .off : .on
            existing.orderFrontRegardless()
            existing.makeKey()
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "PawsOff — Quick Guide"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.center()
        win.delegate = self

        let background = NSVisualEffectView(frame: win.contentView!.bounds)
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.autoresizingMask = [.width, .height]
        win.contentView = background

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: background.bottomAnchor, constant: -24)
        ])

        // Header
        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.spacing = 10
        headerRow.alignment = .centerY

        let iconLabel = NSTextField(labelWithString: "🐾")
        iconLabel.font = .systemFont(ofSize: 32)
        headerRow.addArrangedSubview(iconLabel)

        let titleStack = NSStackView()
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2

        let title = NSTextField(labelWithString: "PawsOff Quick Guide")
        title.font = .systemFont(ofSize: 18, weight: .bold)
        title.textColor = .white
        titleStack.addArrangedSubview(title)

        let subtitle = NSTextField(labelWithString: "Cat-proof shield while your background AI work continues.")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .white.withAlphaComponent(0.7)
        titleStack.addArrangedSubview(subtitle)

        headerRow.addArrangedSubview(titleStack)
        stack.addArrangedSubview(headerRow)

        // Story Card
        let storyCard = NSView()
        storyCard.wantsLayer = true
        storyCard.layer?.cornerRadius = 10
        storyCard.layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.75).cgColor
        storyCard.layer?.borderWidth = 0.5
        storyCard.layer?.borderColor = NSColor(white: 1.0, alpha: 0.15).cgColor
        storyCard.translatesAutoresizingMaskIntoConstraints = false

        let storyStack = NSStackView()
        storyStack.orientation = .vertical
        storyStack.alignment = .leading
        storyStack.spacing = 6
        storyStack.translatesAutoresizingMaskIntoConstraints = false
        storyCard.addSubview(storyStack)

        NSLayoutConstraint.activate([
            storyStack.topAnchor.constraint(equalTo: storyCard.topAnchor, constant: 12),
            storyStack.bottomAnchor.constraint(equalTo: storyCard.bottomAnchor, constant: -12),
            storyStack.leadingAnchor.constraint(equalTo: storyCard.leadingAnchor, constant: 14),
            storyStack.trailingAnchor.constraint(equalTo: storyCard.trailingAnchor, constant: -14)
        ])

        let storyHeadline = NSTextField(labelWithString: "🐾  Cat-Proof While Your AI Work Continues")
        storyHeadline.font = .systemFont(ofSize: 13, weight: .bold)
        storyHeadline.textColor = NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.45, alpha: 1.0)
        storyStack.addArrangedSubview(storyHeadline)

        let storyBody = NSTextField(wrappingLabelWithString:
            "In the background, everything stays running exactly as is—your local AI models, terminal builds, and scripts never sleep.\n\n" +
            "Meanwhile, your keyboard, mouse, and screen are completely protected from wandering paws and curious coworkers.\n\n" +
            "Enjoy this completely free app—hack on it, add anything you like, and never worry when stepping away from your machine."
        )
        storyBody.font = .systemFont(ofSize: 11.5)
        storyBody.textColor = .white.withAlphaComponent(0.9)
        storyBody.lineBreakMode = .byWordWrapping
        storyStack.addArrangedSubview(storyBody)

        stack.addArrangedSubview(storyCard)
        storyCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // 3 Instructions
        let instructions = [
            ("1️⃣ Drop Curtain (Ctrl + 1)", "Tap Ctrl+1 or use the menu bar anytime you step away. Freeze physical input and dim screens instantly."),
            ("2️⃣ Swift Unlock (Ctrl + 1 or 2× Esc)", "Return and tap Ctrl+1 or double-tap Esc. Instant desktop return with 0ms focus delay or password prompts."),
            ("3️⃣ Coworker Passkey (Optional)", "Working in a shared office? Enable 'Require Passkey' in the menu. 3 wrong tries drops straight to macOS login.")
        ]

        for (stepTitle, stepDesc) in instructions {
            let row = NSStackView()
            row.orientation = .vertical
            row.alignment = .leading
            row.spacing = 2

            let stepLabel = NSTextField(labelWithString: stepTitle)
            stepLabel.font = .systemFont(ofSize: 12, weight: .semibold)
            stepLabel.textColor = .white
            row.addArrangedSubview(stepLabel)

            let descLabel = NSTextField(wrappingLabelWithString: stepDesc)
            descLabel.font = .systemFont(ofSize: 11)
            descLabel.textColor = .white.withAlphaComponent(0.75)
            row.addArrangedSubview(descLabel)

            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        // Bottom Controls
        let footerStack = NSStackView()
        footerStack.orientation = .vertical
        footerStack.alignment = .leading
        footerStack.spacing = 10

        doNotShowCheckbox.target = self
        doNotShowCheckbox.action = #selector(doNotShowToggled)
        doNotShowCheckbox.font = .systemFont(ofSize: 11)
        doNotShowCheckbox.state = settings.shouldShowTutorialOnLaunch ? .off : .on
        footerStack.addArrangedSubview(doNotShowCheckbox)

        let gotItButton = NSButton(title: "Protect My Screen", target: self, action: #selector(gotItPressed))
        gotItButton.bezelStyle = .rounded
        gotItButton.font = .systemFont(ofSize: 13, weight: .semibold)
        gotItButton.keyEquivalent = "\r"
        footerStack.addArrangedSubview(gotItButton)
        gotItButton.widthAnchor.constraint(equalTo: footerStack.widthAnchor).isActive = true
        gotItButton.heightAnchor.constraint(equalToConstant: 32).isActive = true

        stack.addArrangedSubview(footerStack)
        footerStack.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        self.window = win
        win.orderFrontRegardless()
        win.makeKey()
    }

    var onProtect: (() -> Void)?

    @objc private func doNotShowToggled() {
        let suppress = (doNotShowCheckbox.state == .on)
        settings?.setTutorialSuppressedOnLaunch(suppress)
    }

    @objc private func gotItPressed() {
        let suppress = (doNotShowCheckbox.state == .on)
        settings?.setTutorialSuppressedOnLaunch(suppress)
        window?.orderOut(nil)
        onProtect?()
    }

    func windowWillClose(_ notification: Notification) {
        let suppress = (doNotShowCheckbox.state == .on)
        settings?.setTutorialSuppressedOnLaunch(suppress)
    }
}
