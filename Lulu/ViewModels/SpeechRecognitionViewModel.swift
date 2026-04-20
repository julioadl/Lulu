import SwiftUI
import Speech
import AVFoundation

@MainActor
class SpeechRecognitionViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var wordResults: [WordResult] = []
    @Published var permissionGranted = false

    struct WordResult: Identifiable {
        let id: UUID
        let word: String
        let correct: Bool
    }

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func requestPermission() async {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        let micGranted = await AVAudioApplication.requestRecordPermission()
        permissionGranted = (speechStatus == .authorized) && micGranted
    }

    func startRecording() {
        guard permissionGranted, let recognizer = speechRecognizer, recognizer.isAvailable else { return }
        guard !audioEngine.isRunning else { return }

        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try? audioEngine.start()
        isRecording = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    self.transcribedText = result.bestTranscription.formattedString
                }
            }
            if error != nil || result?.isFinal == true {
                Task { @MainActor in
                    self.stopRecording()
                }
            }
        }
    }

    func stopRecording() {
        guard audioEngine.isRunning else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
    }

    func evaluate(expected: String) {
        let expectedWords = normalizeString(expected).split(separator: " ").map(String.init)
        let transcribedWords = normalizeString(transcribedText).split(separator: " ").map(String.init)

        wordResults = expectedWords.enumerated().map { index, word in
            let correct = index < transcribedWords.count && transcribedWords[index] == word
            return WordResult(id: UUID(), word: word, correct: correct)
        }
    }

    private func normalizeString(_ string: String) -> String {
        string.lowercased().filter { !$0.isPunctuation && !$0.isMathSymbol }
    }
}
