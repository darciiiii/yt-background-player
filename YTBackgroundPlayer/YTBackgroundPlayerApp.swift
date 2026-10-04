import SwiftUI

@main
struct YTBackgroundPlayerApp: App {
    @StateObject private var player = PlayerController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
        }
    }
}
