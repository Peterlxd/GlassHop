import SwiftUI

@main
struct GlassHopApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .statusBar(hidden: true)
                .ignoresSafeArea()
        }
    }
}
