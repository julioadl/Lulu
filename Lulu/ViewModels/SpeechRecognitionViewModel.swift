import SwiftUI
import Speech
import AVFoundation

@MainActor
class SpeechRecognitionViewModel: ObservableObject {
    enum ScoringModel: String, CaseIterable, Identifiable {
        case exact
        case tolerant

        var id: String { rawValue }

        var title: String {
            switch self {
            case .exact:
                return "Exact"
            case .tolerant:
                return "Tolerant"
            }
        }
    }

    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var wordResults: [WordResult] = []
    @Published var permissionGranted = false
    @Published var errorMessage: String? = nil

    struct WordResult: Identifiable {
        let id: UUID
        let word: String
        let correct: Bool
    }

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasInstalledTap = false

    func requestPermission() async {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        let micGranted = await requestMicrophonePermission()
        permissionGranted = (speechStatus == .authorized) && micGranted
    }

    func startRecording() {
        guard permissionGranted, let recognizer = speechRecognizer, recognizer.isAvailable else { return }
        guard !audioEngine.isRunning else { return }
        errorMessage = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Could not activate microphone: \(error.localizedDescription)"
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            errorMessage = "Microphone format is invalid. Please reconnect audio input and try again."
            return
        }

        if hasInstalledTap {
            inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        hasInstalledTap = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            if hasInstalledTap {
                inputNode.removeTap(onBus: 0)
                hasInstalledTap = false
            }
            errorMessage = "Could not start recording: \(error.localizedDescription)"
            return
        }
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
                    if let error {
                        self.errorMessage = error.localizedDescription
                    }
                    self.stopRecording()
                }
            }
        }
    }

    func stopRecording() {
        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        try? audioSession.setCategory(.playback, mode: .default, options: [.duckOthers])
        isRecording = false
    }

    func evaluate(expected: String, model: ScoringModel = .exact) {
        let expectedWords = normalizeString(expected).split(separator: " ").map(String.init)
        let transcribedWords = normalizeString(transcribedText).split(separator: " ").map(String.init)

        switch model {
        case .exact:
            wordResults = expectedWords.enumerated().map { index, word in
                let correct = index < transcribedWords.count && transcribedWords[index] == word
                return WordResult(id: UUID(), word: word, correct: correct)
            }
        case .tolerant:
            let matchedIndices = lcsMatchedExpectedIndices(expectedWords: expectedWords, transcribedWords: transcribedWords)
            wordResults = expectedWords.enumerated().map { index, word in
                WordResult(id: UUID(), word: word, correct: matchedIndices.contains(index))
            }
        }
    }

    private func normalizeString(_ string: String) -> String {
        let normalized = String(
            string.lowercased().map { character in
                if character.isLetter || character.isNumber || character.isWhitespace {
                    return character
                }
                return " "
            }
        )

        return normalized
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func lcsMatchedExpectedIndices(expectedWords: [String], transcribedWords: [String]) -> Set<Int> {
        guard !expectedWords.isEmpty, !transcribedWords.isEmpty else {
            return []
        }

        let m = expectedWords.count
        let n = transcribedWords.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 1...m {
            for j in 1...n {
                if expectedWords[i - 1] == transcribedWords[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        var matchedIndices: Set<Int> = []
        var i = m
        var j = n

        while i > 0 && j > 0 {
            if expectedWords[i - 1] == transcribedWords[j - 1] {
                matchedIndices.insert(i - 1)
                i -= 1
                j -= 1
            } else if dp[i - 1][j] >= dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        return matchedIndices
    }
}
