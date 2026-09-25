import AppKit
import Foundation

// Compile/run as an ordinary command-line tool; never activate it.
let requested = CommandLine.arguments.dropFirst().first.flatMap(Double.init) ?? 120
let duration = min(3600, max(1, requested.isFinite ? requested : 120))
let deadline = ProcessInfo.processInfo.systemUptime + duration
var lastPID: pid_t = -1
func sample() {
    guard let app = NSWorkspace.shared.frontmostApplication else { return }
    guard app.processIdentifier != lastPID else { return }
    lastPID = app.processIdentifier
    let record: [String: Any] = ["uptime": ProcessInfo.processInfo.systemUptime,
        "frontmostPID": Int(lastPID), "bundleID": app.bundleIdentifier ?? "unbundled"]
    if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) {
        FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
    }
}
sample()
let timer = Timer(timeInterval: 0.1, repeats: true) { _ in sample() }
RunLoop.main.add(timer, forMode: .common)
while ProcessInfo.processInfo.systemUptime < deadline {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
}
timer.invalidate()
