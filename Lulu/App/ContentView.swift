import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var documentViewModel: DocumentViewModel
    @EnvironmentObject private var ttsViewModel: TTSViewModel
    
    var body: some View {
        TabView {
            NavigationStack {
                DocumentContainerView()
            }
                .tabItem {
                    Label("Read", systemImage: "book.fill")
                }
            
            NavigationStack {
                ListenRepeatView()
            }
                .tabItem {
                    Label("Listen", systemImage: "mic.circle.fill")
                }
            
            NavigationStack {
                SettingsView()
            }
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
    }
}

