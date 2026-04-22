import SwiftUI
import AVFoundation

@MainActor
class TTSViewModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking = false
    @Published var isPaused = false
    @Published var currentWordRange: NSRange? = nil
    @Published var currentSentence: Sentence? = nil
    @Published var currentSpokenText: String = ""
    @Published var rate: Float = 0.4
    @Published var pitch: Float = 1.0
    
    private let synthesizer = AVSpeechSynthesizer()
    private var pauseTargetWordRange: NSRange? = nil
    private var shouldPauseAtTargetWord = false
    private var highlightTask: Task<Void, Never>?
    
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    func speak(sentence: Sentence) {
        guard !isSpeaking else { return }
        highlightTask?.cancel()
        isPaused = false
        pauseTargetWordRange = nil
        shouldPauseAtTargetWord = false
        currentSentence = sentence
        currentSpokenText = sentence.text
        isSpeaking = true

        speakText(sentence.text)
    }

    func speak(text: String) {
        guard !isSpeaking else { return }
        highlightTask?.cancel()
        isPaused = false
        pauseTargetWordRange = nil
        shouldPauseAtTargetWord = false

        currentSentence = nil
        currentSpokenText = text
        isSpeaking = true

        speakText(text)
    }

    func speakWithPauseAtRandomWord(text: String) {
        guard !isSpeaking else { return }
        highlightTask?.cancel()
        isPaused = false
        currentSentence = nil
        currentSpokenText = text
        isSpeaking = true

        if let randomRange = randomWordRange(in: text) {
            pauseTargetWordRange = randomRange
            shouldPauseAtTargetWord = true
            currentWordRange = randomRange
        } else {
            pauseTargetWordRange = nil
            shouldPauseAtTargetWord = false
            currentWordRange = nil
        }

        speakText(text)
    }

    func followHighlightedWordsOnly(text: String, interval: UInt64 = 450_000_000) {
        guard !isSpeaking else { return }
        highlightTask?.cancel()

        currentSentence = nil
        currentSpokenText = text
        currentWordRange = nil
        isPaused = false
        pauseTargetWordRange = nil
        shouldPauseAtTargetWord = false
        isSpeaking = true

        let ranges = wordRanges(in: text)
        highlightTask = Task { @MainActor in
            if ranges.isEmpty {
                self.isSpeaking = false
                self.currentSpokenText = ""
                return
            }
            for range in ranges {
                if Task.isCancelled { break }
                self.currentWordRange = range
                try? await Task.sleep(nanoseconds: interval)
            }
            if !Task.isCancelled {
                self.isSpeaking = false
                self.currentWordRange = nil
                self.currentSpokenText = ""
            }
        }
    }

    func resume() {
        if isPaused {
            synthesizer.continueSpeaking()
            isPaused = false
            pauseTargetWordRange = nil
        } else if highlightTask != nil {
            // Highlight-only mode does not have pause state. Resume is no-op.
        }
    }
    
    func stop() {
        highlightTask?.cancel()
        highlightTask = nil
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        pauseTargetWordRange = nil
        shouldPauseAtTargetWord = false
        currentWordRange = nil
        currentSentence = nil
        currentSpokenText = ""
    }
    
    // Delegate methods — called by AVFoundation off the main thread; dispatch to main actor

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.currentWordRange = characterRange
            if self.shouldPauseAtTargetWord,
               let target = self.pauseTargetWordRange,
               NSEqualRanges(characterRange, target) {
                self.shouldPauseAtTargetWord = false
                self.isPaused = true
                self.synthesizer.pauseSpeaking(at: .immediate)
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.highlightTask = nil
            self.isSpeaking = false
            self.isPaused = false
            self.pauseTargetWordRange = nil
            self.shouldPauseAtTargetWord = false
            self.currentWordRange = nil
            self.currentSentence = nil
            self.currentSpokenText = ""
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.highlightTask = nil
            self.isSpeaking = false
            self.isPaused = false
            self.pauseTargetWordRange = nil
            self.shouldPauseAtTargetWord = false
            self.currentWordRange = nil
            self.currentSentence = nil
            self.currentSpokenText = ""
        }
    }

    private func speakText(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "fr-FR")
        utterance.rate = rate
        utterance.pitchMultiplier = pitch

        synthesizer.speak(utterance)
    }

    private func wordRanges(in text: String) -> [NSRange] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var ranges: [NSRange] = []
        nsText.enumerateSubstrings(in: fullRange, options: [.byWords, .substringNotRequired]) { _, range, _, _ in
            ranges.append(range)
        }
        return ranges
    }

    private func randomWordRange(in text: String) -> NSRange? {
        wordRanges(in: text).randomElement()
    }
}
