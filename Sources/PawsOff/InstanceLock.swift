import Foundation
import Darwin

/// A per-user process lock also catches launches of the unbundled executable.
final class InstanceLock {
    private var descriptor: Int32 = -1
    init() throws {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/com.leonidmajbits.pawsoff", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        descriptor = open(directory.appendingPathComponent("instance.lock").path,
                          O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw PawsOffError.message("Cannot open the PawsOff instance lock.") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor); descriptor = -1
            throw PawsOffError.message("PawsOff is already running for this user.")
        }
    }
    deinit { if descriptor >= 0 { close(descriptor) } }
}
