import SwiftUI

struct ListenRepeatView: View {
    @EnvironmentObject var docVM: DocumentViewModel
    @EnvironmentObject var ttsVM: TTSViewModel
    @StateObject private var speechVM = SpeechRecognitionViewModel()
    @State private var currentIndex = 0
    
    // Compute allSentences from the pages in the document model
    private var allSentences: [Sentence] {
        docVM.pages.flatMap { $0.sentences }
    }
    
    var body: some View {
        VStack {
            if allSentences.isEmpty {
                Text("Load a document first")
                    .font(.title2)
                    .padding()
            } else {
                // Current sentence text in large rounded card
                Text(allSentences[currentIndex].text)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(16)
                
                // Progress text
                Text("Sentence \(currentIndex + 1) of \(allSentences.count)")
                    .font(.caption)
                    .padding()
                
                // Navigation buttons
                HStack {
                    Button(action: {
                        withAnimation {
                            currentIndex = max(currentIndex - 1, 0)
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .imageScale(.large)
                            .frame(width: 50, height: 50)
                    }
                    .disabled(currentIndex == 0)
                    
                    Button(action: {
                        withAnimation {
                            currentIndex = min(currentIndex + 1, allSentences.count - 1)
                        }
                    }) {
                        Image(systemName: "chevron.right")
                            .imageScale(.large)
                            .frame(width: 50, height: 50)
                    }
                    .disabled(currentIndex == allSentences.count - 1)
                }
                
                // Buttons to listen and record
                HStack(spacing: 20) {
                    Button(action: {
                        ttsVM.speak(sentence: allSentences[currentIndex])
                    }) {
                        Image(systemName: "speaker.wave.3.fill")
                            .imageScale(.large)
                            .frame(width: 50, height: 50)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(16)
                    }
                    
                    Button(action: {
                        if speechVM.isRecording {
                            speechVM.stopRecording()
                        } else {
                            speechVM.startRecording()
                        }
                    }) {
                        Image(systemName: "mic.fill")
                            .imageScale(.large)
                            .frame(width: 50, height: 50)
                            .background(speechVM.isRecording ? Color.red : Color.blue.opacity(0.2))
                            .cornerRadius(16)
                    }
                }
                
                // Display word results if available
                if !speechVM.wordResults.isEmpty {
                    WordResultsView(results: speechVM.wordResults)
                        .padding()
                }
            }
        }
        .onChange(of: currentIndex) { _ in
            resetSpeechVMState()
        }
        .task {
            await speechVM.requestPermission()
        }
        .onReceive(speechVM.$isRecording.dropFirst()) { isRecording in
            if !isRecording && !speechVM.transcribedText.isEmpty {
                speechVM.evaluate(expected: allSentences[currentIndex].text)
            }
        }
    }
    
    private func resetSpeechVMState() {
        speechVM.transcribedText = ""
        speechVM.wordResults = []
    }
}
