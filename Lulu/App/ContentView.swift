import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var documentViewModel: DocumentViewModel
    @EnvironmentObject private var ttsViewModel: TTSViewModel
    
    var body: some View {
        TabView {
            DocumentContainerView()
                .tabItem {
                    Label("Read", systemImage: "book.fill")
                }
            
            ListenRepeatView()
                .tabItem {
                    Label("Listen", systemImage: "mic.circle.fill")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
    }
}

