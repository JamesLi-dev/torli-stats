import SwiftUI

@main
struct TorliStatsApp: App {
    @NSApplicationDelegateAdaptor(TorliAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
