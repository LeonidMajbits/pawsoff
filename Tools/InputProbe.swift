import AppKit
import Foundation

// Intentionally foregrounds THIS harmless test pad, never a working editor.
// Logs event COUNTS, not keycodes, characters, clipboard content, or window titles.
func emit(_ values: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]) else { return }
    FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
}
final class ProbeView: NSView {
    private let label = NSTextField(wrappingLabelWithString: "")
    private var counts: [String: Int] = [:]
    private var beat = 0
    private var timer: Timer?
    override var acceptsFirstResponder: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        label.frame = NSRect(x: 24, y: 24, width: frame.width - 48, height: frame.height - 48)
        label.autoresizingMask = [.width, .height]
        label.font = .monospacedSystemFont(ofSize: 16, weight: .medium)
        addSubview(label)
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        timer = t; RunLoop.main.add(t, forMode: .common)
        tick()
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    private func count(_ name: String) { counts[name, default: 0] += 1 }
    private func tick() {
        beat += 1
        label.stringValue = "PawsOff — harmless input probe\n\nFocus this window, then press Ctrl+1.\nNew keys/clicks/scroll should not increment counts while guarded.\n\nHeartbeat: \(beat)\n\(counts.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "   "))"
        emit(["uptime": ProcessInfo.processInfo.systemUptime, "heartbeat": beat,
              "keyWindow": window?.isKeyWindow ?? false, "active": NSApp.isActive, "counts": counts])
    }
    override func keyDown(with event: NSEvent) { count("keyDown") }
    override func keyUp(with event: NSEvent) { count("keyUp") }
    override func flagsChanged(with event: NSEvent) { count("flagsChanged") }
    override func mouseDown(with event: NSEvent) { count("leftDown") }
    override func mouseUp(with event: NSEvent) { count("leftUp") }
    override func mouseDragged(with event: NSEvent) { count("leftDrag") }
    override func rightMouseDown(with event: NSEvent) { count("rightDown") }
    override func rightMouseUp(with event: NSEvent) { count("rightUp") }
    override func rightMouseDragged(with event: NSEvent) { count("rightDrag") }
    override func otherMouseDown(with event: NSEvent) { count("otherDown") }
    override func otherMouseUp(with event: NSEvent) { count("otherUp") }
    override func otherMouseDragged(with event: NSEvent) { count("otherDrag") }
    override func scrollWheel(with event: NSEvent) { count("scroll") }
    override func magnify(with event: NSEvent) { count("magnify") }
    override func swipe(with event: NSEvent) { count("swipe") }
    override func rotate(with event: NSEvent) { count("rotate") }
    deinit { timer?.invalidate() }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 820, height: 380),
    styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
window.title = "PawsOff Input Probe — no document is edited"
let pad = ProbeView(frame: NSRect(origin: .zero, size: window.frame.size))
window.contentView = pad
let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "Explicit PawsOff verification")
window.makeKeyAndOrderFront(nil)
window.makeFirstResponder(pad)
app.activate(ignoringOtherApps: true)
// Stop from its launching Terminal with Ctrl+C after dismissing PawsOff.
withExtendedLifetime((window, activity)) { app.run() }
