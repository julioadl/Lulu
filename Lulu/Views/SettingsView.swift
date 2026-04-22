import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var ttsVM: TTSViewModel
    @AppStorage("listen.showTranslation") private var showTranslation = false
    @AppStorage("listen.scoringModel") private var scoringModelRawValue = SpeechRecognitionViewModel.ScoringModel.exact.rawValue
    
    var body: some View {
        Form {
            Section(header: Text("Playback")) {
                // Speed slider
                HStack {
                    Text("Speed \(String(format: "%.2f", ttsVM.rate))x")
                    Spacer()
                    Slider(value: $ttsVM.rate, in: 0.01...0.6, step: 0.01)
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

            Section(header: Text("Listen")) {
                Toggle("Show English Translation Panel", isOn: $showTranslation)
                Text("Uses Apple's on-device Translation API when available.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Scoring Model", selection: $scoringModelRawValue) {
                    ForEach(SpeechRecognitionViewModel.ScoringModel.allCases) { model in
                        Text(model.title).tag(model.rawValue)
                    }
                }
            }
            
            Section(header: Text("About")) {
                Text("Version 1.0")
                Text("All processing happens on your device. No data is ever sent to the internet.")
            }
        }
        .navigationTitle("Settings")
    }
}
