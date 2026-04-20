import SwiftUI

@main
struct LuluApp: App {
    @StateObject private var documentViewModel = DocumentViewModel()
    @StateObject private var ttsViewModel = TTSViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(documentViewModel)
                .environmentObject(ttsViewModel)
        }
    }
}
