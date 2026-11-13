import AppKit
import Darwin

/// An OS-owned lock, not a PID file: crashes release it automatically. Keep the
/// file in place so competing launches always lock the same inode.
final class ApplicationInstanceLock {
    private var descriptor: Int32 = -1

    func acquire(at url: URL) throws -> Bool {
        precondition(descriptor == -1)
        let fd = Darwin.open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw posixError(errno) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            Darwin.close(fd)
            if code == EWOULDBLOCK { return false }
            throw posixError(code)
        }
        descriptor = fd
        return true
    }

    deinit {
        if descriptor >= 0 { Darwin.close(descriptor) }
    }

    private func posixError(_ code: Int32) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }
}

/// Installed before SwiftUI creates settings, collectors, or Notes storage.
/// Builds sharing a bundle ID also share the lock, including Community and Pro.
final class SingleInstanceController {
    private let identifier: String
    private let instanceLock = ApplicationInstanceLock()
    private let center = DistributedNotificationCenter.default()
    private var observer: NSObjectProtocol?
    private var pendingActivation = false
    private var activationHandler: (() -> Void)?

    init(identifier: String) {
        self.identifier = identifier
        // Subscribe before acquiring the lock, including while the first app
        // is still starting. Reopen requests are buffered until its UI is ready.
        observer = center.addObserver(
            forName: activationNotification,
            object: String(getuid()),
            queue: .main
        ) { [weak self] _ in
            self?.requestActivation()
        }
    }

    func start() throws -> Bool {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent(identifier, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard try instanceLock.acquire(at: directory.appendingPathComponent("instance.lock")) else {
            activateExistingApplication()
            return false
        }

        // Versions predating this lock can still be running after an upgrade.
        // A new guarded launch cannot finish launching without owning the lock,
        // so this check does not reject another contender that is still starting.
        if let existing = existingApplication {
            existing.activate(options: [])
            postActivation()
            return false
        }
        return true
    }

    func requestActivation() {
        guard let activationHandler else {
            pendingActivation = true
            return
        }
        activationHandler()
    }

    func whenReady(activate: @escaping () -> Void) {
        activationHandler = activate
        if pendingActivation {
            pendingActivation = false
            activate()
        }
    }

    private var activationNotification: Notification.Name {
        Notification.Name(identifier + ".activateExistingInstance")
    }

    private var existingApplication: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
                && !$0.isTerminated && $0.isFinishedLaunching
        }
    }

    private func activateExistingApplication() {
        existingApplication?.activate(options: [])
        postActivation()
    }

    private func postActivation() {
        center.postNotificationName(
            activationNotification, object: String(getuid()),
            userInfo: nil, deliverImmediately: true
        )
    }

    deinit {
        if let observer { center.removeObserver(observer) }
    }
}
