import SwiftUI

@main
struct DotSyncApp: App {
    @State private var service = DotService()

    var body: some Scene {
        MenuBarExtra {
            MenuView(service: service)
        } label: {
            Image(systemName: service.health.symbol)
        }
        .menuBarExtraStyle(.window)
    }
}
