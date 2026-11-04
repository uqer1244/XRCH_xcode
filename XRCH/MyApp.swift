import SwiftUI

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-glass-preview") {
                GlassHandoffPreview()
            } else {
                ContentView()
            }
            #else
            ContentView()
            #endif
        }
    }
}
