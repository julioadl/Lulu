import SwiftUI
import AVFoundation

@MainActor
class TTSViewModel: ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking = false
    @Published var currentWordRange: NSRange? = nil  
    @Published var currentSentence: Sentence? = nil
    @Published var rate: Float = 0.4
    @Published var pitch: Float = 1.0
    
    private let synthesizer = AVSpeechSynthesizer()
    
    init() {
        synthesizer.delegate = self
    }
    
    func speak(sentence: Sentence) {
        guard !isSpeaking else { return }
        
        currentSentence = sentence
        isSpeaking = true
        
        let utterance = AVSpeechUtterance(string: sentence.text)
        utterance.voice = AVSpeechSynthesisVoice(language: "fr-FR")
        utterance.rate = rate
        utterance.pitchMultiplier = pitch
        
        synthesizer.speak(utterance)
    }
    
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        currentWordRange = nil
        currentSentence = nil
    }
    
    // Delegate methods — called by AVFoundation off the main thread; dispatch to main actor

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.currentWordRange = characterRange
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentWordRange = nil
            self.currentSentence = nil
        }
    }
}
