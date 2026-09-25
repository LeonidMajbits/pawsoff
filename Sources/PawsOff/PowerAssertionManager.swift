import Foundation
import IOKit
import IOKit.pwr_mgt

final class PowerAssertionManager {
    private var assertions: [IOPMAssertionID] = []
    private var activity: NSObjectProtocol?

    func acquire() throws {
        precondition(Thread.isMainThread)
        guard assertions.isEmpty else { return }
        do {
            for type in [kIOPMAssertionTypePreventUserIdleSystemSleep,
                         kIOPMAssertionTypePreventUserIdleDisplaySleep] {
                var identifier: IOPMAssertionID = 0
                let status = IOPMAssertionCreateWithName(type as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    "PawsOff: curtain active; leave background work running" as CFString, &identifier)
                guard status == kIOReturnSuccess else {
                    throw PawsOffError.message("Could not hold the Mac awake (IOKit \(status)).")
                }
                assertions.append(identifier)
            }
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated],
                reason: "PawsOff input shield must remain responsive")
        } catch {
            release()
            throw error
        }
    }
    func release() {
        for assertion in assertions { IOPMAssertionRelease(assertion) }
        assertions.removeAll()
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }
    deinit { release() }
}
