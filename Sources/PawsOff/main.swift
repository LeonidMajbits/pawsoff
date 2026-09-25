import AppKit
import Darwin

let instanceLock: InstanceLock
do { instanceLock = try InstanceLock() }
catch {
    fputs("PawsOff: \(error.localizedDescription)\n", stderr)
    exit(1)
}
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = AppDelegate()
application.delegate = delegate
withExtendedLifetime((instanceLock, delegate)) { application.run() }
