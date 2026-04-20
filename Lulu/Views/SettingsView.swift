import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var ttsVM: TTSViewModel
    
    var body: some View {
        Form {
            Section("Playback") {
                // Speed slider
                HStack {
                    Text("Speed \(String(format: "%.1f", ttsVM.rate))x")
                    Spacer()
                    Slider(value: $ttsVM.rate, in: 0.1...0.6)
                }
                
                // Pitch slider
                HStack {
                    Text("Pitch")
                    Spacer()
                    Slider(value: $ttsVM.pitch, in: 0.8...1.2)
                }
                
                // Test Voice button
                Button(action: {
                    ttsVM.speak(sentence: Sentence(id: UUID(), text: "Bonjour, je m'appelle Lulu. Je vais t'aider à lire en français.", boundingBox: .zero, pageIndex: 0))
                }) {
                    Text("Test Voice")
                }
            }
            
            Section("About") {
                Text("Version 1.0")
                Text("All processing happens on your device. No data is ever sent to the internet.")
            }
        }
        .navigationTitle("Settings")
    }
}
