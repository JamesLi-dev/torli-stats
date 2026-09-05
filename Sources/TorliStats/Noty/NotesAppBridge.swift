import Foundation

/// SwiftUI's app-delegate adaptor does not guarantee that `NSApp.delegate`
/// remains the concrete Torli delegate while edge panels are inactive. Keep an
/// explicit weak bridge so Deck button actions always reach the host app.
final class NotesAppBridge {
    static let shared = NotesAppBridge()
    weak var delegate: TorliAppDelegate?

    private init() {}
}
