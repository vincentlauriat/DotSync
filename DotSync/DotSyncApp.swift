import Sparkle
import SwiftUI

@main
struct DotSyncApp: App {
    @State private var service = DotService()
    // Starts Sparkle: daily check against SUFeedURL (Info.plist)
    private let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var body: some Scene {
        MenuBarExtra {
            MenuView(service: service, updater: updater.updater)
        } label: {
            Image(systemName: service.health.symbol)
        }
        .menuBarExtraStyle(.window)
    }
}
