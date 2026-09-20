import Foundation

/// Manages the undocumented host-scoped preferences that AppKit reads when a
/// process creates a status item. This intentionally changes only spacing; it
/// does not inspect, hide, move, or otherwise manage third-party menu items.
enum MenuBarSpacingManager {
    private enum Key: String, CaseIterable {
        case itemSpacing = "NSStatusItemSpacing"
        case selectionPadding = "NSStatusItemSelectionPadding"
    }

    /// macOS currently uses 16 points for both values when no user override is
    /// present. Keeping the UI as an offset makes the system default the clear
    /// zero position and avoids exposing two confusing implementation values.
    static let defaultValue = 16
    static let supportedOffsets = -8...8

    enum SpacingError: LocalizedError {
        case synchronizeFailed
        case relaunchFailed

        var errorDescription: String? {
            switch self {
            case .synchronizeFailed: "Unable to save the menu bar spacing preference."
            case .relaunchFailed: "Unable to relaunch Torli Stats."
            }
        }
    }

    static func apply(offset: Int) throws {
        let value = max(0, defaultValue + offset)
        for key in Key.allCases {
            CFPreferencesSetValue(
                key.rawValue as CFString,
                value as CFPropertyList,
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
        }
        guard CFPreferencesSynchronize(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) else {
            throw SpacingError.synchronizeFailed
        }
    }

    static func restoreSystemDefault() throws {
        for key in Key.allCases {
            CFPreferencesSetValue(
                key.rawValue as CFString,
                nil,
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
        }
        guard CFPreferencesSynchronize(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) else {
            throw SpacingError.synchronizeFailed
        }
    }
}
