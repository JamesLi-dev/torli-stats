import AppKit

/// Restarts user-installed, menu-bar-style apps after a global status-item
/// spacing update. macOS does not expose a public API that identifies every
/// third-party status item, so this deliberately targets only standalone
/// accessory apps in /Applications. System agents, extensions, helpers, and
/// foreground work apps are excluded rather than being terminated blindly.
enum MenuBarApplicationRelauncher {
    private struct Candidate {
        let application: NSRunningApplication
        let bundleURL: URL
    }

    static func relaunchMenuBarServicesAndEligibleApplications(excluding processID: pid_t) {
        relaunchSystemMenuBarServices()

        let candidates = NSWorkspace.shared.runningApplications.compactMap { app -> Candidate? in
            guard app.processIdentifier != processID,
                  !app.isTerminated,
                  app.activationPolicy == .accessory,
                  let bundleURL = app.bundleURL,
                  bundleURL.deletingLastPathComponent().path == "/Applications" else {
                return nil
            }
            return Candidate(application: app, bundleURL: bundleURL)
        }

        guard !candidates.isEmpty else { return }

        // terminate() is graceful: an app can present its own save prompt or
        // decline the request. We never force-kill a process that stays open.
        for candidate in candidates {
            candidate.application.terminate()
        }

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline,
              candidates.contains(where: { !$0.application.isTerminated }) {
            RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.05)))
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = false
        configuration.promptsUserIfNeeded = false

        for candidate in candidates where candidate.application.isTerminated {
            NSWorkspace.shared.openApplication(at: candidate.bundleURL, configuration: configuration) { _, _ in }
        }
    }

    /// Apple owns the windows that host most system menu extras. Restart their
    /// per-user LaunchAgents so they rebuild the bar using the new preference.
    /// `kickstart` preserves launchd ownership, unlike terminating and opening
    /// these system apps directly.
    private static func relaunchSystemMenuBarServices() {
        let userID = getuid()
        for label in ["com.apple.SystemUIServer.agent", "com.apple.controlcenter"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["kickstart", "-k", "gui/\(userID)/\(label)"]
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                // A service may be unavailable on a particular macOS release;
                // user-installed status apps can still be refreshed below.
                continue
            }
        }
    }
}
