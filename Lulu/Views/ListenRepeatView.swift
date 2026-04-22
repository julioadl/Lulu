import SwiftUI
#if canImport(Translation)
import Translation
#endif

struct ListenRepeatView: View {
    private enum SentenceListeningMode: String, CaseIterable, Identifiable {
        case fullText
        case fullSentence
        case pauseOnRandomWord
        case highlightOnly
        case alternateSentences

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fullText:
                return "Full text"
            case .fullSentence:
                return "Full sentence"
            case .pauseOnRandomWord:
                return "Pause at random word"
            case .highlightOnly:
                return "Highlight only"
            case .alternateSentences:
                return "Alternate sentences"
            }
        }
    }

    @EnvironmentObject var docVM: DocumentViewModel
    @EnvironmentObject var ttsVM: TTSViewModel
    @AppStorage("listen.showTranslation") private var showTranslation = false
    @State private var sessionSentenceCount = 3
    @State private var currentSentenceIndex = 0
    @State private var translationPanelWidthRatio: CGFloat = 0.45
    @State private var dragStartTranslationRatio: CGFloat? = nil
    @State private var sentenceListeningModeRawValue = SentenceListeningMode.fullSentence.rawValue
    @State private var fullTextTimerIsRunning = false
    @State private var fullTextElapsedSeconds = 0
    @State private var fullTextTargetSeconds = 60
    @State private var isShowingTimerGoalEditor = false
    @State private var alternateAwaitingChildTurn = false
    @State private var alternatePendingSystemAdvance = false
    private let fullTextTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var targetSentences: [Sentence] {
        docVM.selectedSentences.sorted { lhs, rhs in
            if lhs.pageIndex != rhs.pageIndex {
                return lhs.pageIndex < rhs.pageIndex
            }
            if lhs.boundingBox.minY != rhs.boundingBox.minY {
                return lhs.boundingBox.minY < rhs.boundingBox.minY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
    }

    private var sentenceListeningMode: SentenceListeningMode {
        SentenceListeningMode(rawValue: sentenceListeningModeRawValue) ?? .fullSentence
    }

    private var practiceSentences: [String] {
        let allSentences = targetSentences.flatMap { splitSentences($0.text) }
        return allSentences
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var totalSentencesAvailable: Int {
        practiceSentences.count
    }

    private var currentSentenceText: String {
        guard practiceSentences.indices.contains(currentSentenceIndex) else {
            return ""
        }
        return practiceSentences[currentSentenceIndex]
    }

    private var activeExpectedText: String {
        switch sentenceListeningMode {
        case .fullText:
            return practiceSentences.joined(separator: "\n\n")
        default:
            return currentSentenceText
        }
    }

    private var activeRunSentenceCount: Int {
        let remaining = max(totalSentencesAvailable - currentSentenceIndex, 0)
        return min(sessionSentenceCount, remaining)
    }

    private var frenchWordCount: Int {
        activeExpectedText.split { $0.isWhitespace || $0.isNewline }.count
    }

    private var displayedUnitCount: Int {
        sentenceListeningMode == .fullText ? 1 : activeRunSentenceCount
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if targetSentences.isEmpty {
                        emptyState
                    } else {
                        controlsSection
                        readingPanelsSection
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
            }
        }
        .navigationTitle("Listen & Repeat")
        .onChange(of: docVM.selectedSentenceIDs) { _ in
            resetPracticeSession(resetCursor: true)
        }
        .onChange(of: sessionSentenceCount) { _ in
            alternateAwaitingChildTurn = false
            alternatePendingSystemAdvance = false
        }
        .onChange(of: sentenceListeningModeRawValue) { _ in
            alternateAwaitingChildTurn = false
            alternatePendingSystemAdvance = false
            if sentenceListeningMode != .fullText {
                fullTextTimerIsRunning = false
            }
            clearCurrentAttempt()
            if ttsVM.isSpeaking {
                ttsVM.stop()
            }
        }
        .onReceive(ttsVM.$isSpeaking.dropFirst()) { isSpeaking in
            if !isSpeaking && sentenceListeningMode == .alternateSentences && alternatePendingSystemAdvance {
                alternatePendingSystemAdvance = false
                let lastIndex = max(totalSentencesAvailable - 1, 0)
                if currentSentenceIndex < lastIndex {
                    currentSentenceIndex += 1
                    alternateAwaitingChildTurn = true
                    clearCurrentAttempt()
                }
            }
        }
        .onReceive(fullTextTimer) { _ in
            guard fullTextTimerIsRunning else { return }
            fullTextElapsedSeconds += 1
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Load a document first")
                .font(.title2.weight(.semibold))
            Text("Import a PDF or scan a worksheet in the Read tab.")
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sentenceListeningModeSelector
            if sentenceListeningMode != .fullText {
                sentencePracticeControls
            }
            if sentenceListeningMode == .fullText {
                fullTextTimerControls
            }

            HStack {
                Spacer()
                Button(action: {
                    handleListenButtonTapped()
                }) {
                    Label(listenButtonTitle, systemImage: listenButtonIcon)
                        .font(.headline)
                        .frame(minWidth: 190)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 18)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(activeExpectedText.isEmpty || (sentenceListeningMode == .alternateSentences && alternateAwaitingChildTurn))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Reading Speed", systemImage: "tortoise.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(String(format: "%.2f", ttsVM.rate))
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.secondary)
                }

                Slider(value: $ttsVM.rate, in: 0.01...0.6, step: 0.01)

                HStack(spacing: 8) {
                    speedPresetButton(0.01)
                    speedPresetButton(0.05)
                    speedPresetButton(0.10)
                    speedPresetButton(0.25)
                }
            }

        }
    }

    private var sentencePracticeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sentence \(min(currentSentenceIndex + 1, max(totalSentencesAvailable, 1))) of \(max(totalSentencesAvailable, 1))")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Stepper("Count: \(sessionSentenceCount)", value: $sessionSentenceCount, in: 1...max(totalSentencesAvailable, 1))
                    .labelsHidden()
                Text("Count: \(sessionSentenceCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                Button("Prev") {
                    currentSentenceIndex = max(currentSentenceIndex - 1, 0)
                    alternateAwaitingChildTurn = false
                    alternatePendingSystemAdvance = false
                    clearCurrentAttempt()
                }
                .buttonStyle(.bordered)
                .disabled(currentSentenceIndex == 0)

                Button("Next") {
                    currentSentenceIndex = min(currentSentenceIndex + 1, max(totalSentencesAvailable - 1, 0))
                    alternateAwaitingChildTurn = false
                    alternatePendingSystemAdvance = false
                    clearCurrentAttempt()
                }
                .buttonStyle(.bordered)
                .disabled(currentSentenceIndex >= max(totalSentencesAvailable - 1, 0))

                Button("Restart Run") {
                    alternateAwaitingChildTurn = false
                    alternatePendingSystemAdvance = false
                    clearCurrentAttempt()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var sentenceListeningModeSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Listening Mode")
                .font(.subheadline.weight(.semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(SentenceListeningMode.allCases) { mode in
                        Button {
                            sentenceListeningModeRawValue = mode.rawValue
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(mode.title, systemImage: icon(for: mode))
                                    .font(.caption.weight(.semibold))
                                Text(description(for: mode))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(10)
                            .frame(width: 170, alignment: .leading)
                            .background(mode.rawValue == sentenceListeningModeRawValue ? Color.blue.opacity(0.18) : Color.gray.opacity(0.09))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(mode.rawValue == sentenceListeningModeRawValue ? Color.blue : Color.clear, lineWidth: 1)
                            )
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if sentenceListeningMode == .alternateSentences {
                Text(alternateAwaitingChildTurn ? "Child turn: read aloud, then tap Listen to continue." : "System turn: tap Listen to read this sentence.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var readingPanelsSection: some View {
        if showTranslation {
            GeometryReader { geometry in
                let totalWidth = max(geometry.size.width, 1)
                let clampedRatio = max(0.25, min(0.65, translationPanelWidthRatio))
                let translationWidth = totalWidth * clampedRatio
                let frenchWidth = totalWidth - translationWidth - 12

                HStack(alignment: .top, spacing: 6) {
                    readingPanel
                        .frame(width: frenchWidth)

                    resizeHandle(totalWidth: totalWidth)

                    translationPanel
                        .frame(width: translationWidth)
                }
            }
            .frame(minHeight: 320)
        } else {
            readingPanel
        }
    }

    private var readingPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("French Text", systemImage: "book")
                .font(.headline)
            Text("\(displayedUnitCount) unit(s) • \(frenchWordCount) words")
                .font(.caption)
                .foregroundColor(.secondary)
            if showTranslation {
                ScrollView {
                    displayedFrenchTextView
                }
                .frame(minHeight: 280, alignment: .top)
            } else {
                displayedFrenchTextView
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(16)
    }

    @ViewBuilder
    private var translationPanel: some View {
#if canImport(Translation)
        if #available(iOS 26.4, *) {
            TranslationPanel(sourceText: activeExpectedText)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            unavailableTranslationCard
        }
#else
        unavailableTranslationCard
#endif
    }

    private var unavailableTranslationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("English Translation", systemImage: "globe")
                .font(.headline)
            Text("Translation is available on newer iOS versions with Apple's on-device Translation framework.")
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.gray.opacity(0.12))
        .cornerRadius(16)
    }

    @ViewBuilder
    private var displayedFrenchTextView: some View {
        if sentenceListeningMode == .fullText {
            fullTextReadingCard(content: highlightedTargetText())
        } else {
            sentenceFocusTextView
        }
    }

    private var sentenceFocusTextView: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(practiceSentences.enumerated()), id: \.offset) { index, sentence in
                    Group {
                        if index == currentSentenceIndex {
                            fullTextReadingCard(content: highlightedSentenceText(sentence))
                        } else {
                            Text(sentence)
                                .font(.system(size: 22, weight: .regular, design: .serif))
                                .lineSpacing(8)
                                .tracking(0.2)
                                .multilineTextAlignment(.leading)
                                .foregroundColor(.primary)
                                .opacity(0.25)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                        }
                    }
                    .id(index)
                }
            }
            .onChange(of: currentSentenceIndex) { newValue in
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo(currentSentenceIndex, anchor: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fullTextReadingCard(content: Text) -> some View {
        content
            .font(.system(size: 22, weight: .medium, design: .serif))
            .lineSpacing(8)
            .tracking(0.2)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.6))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(0.15), lineWidth: 1)
            )
            .cornerRadius(12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func speedPresetButton(_ value: Float) -> some View {
        Button(action: { ttsVM.rate = value }) {
            Text(String(format: "%.2f", value))
                .font(.caption.monospacedDigit())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(ttsVM.rate == value ? 0.35 : 0.12))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func resizeHandle(totalWidth: CGFloat) -> some View {
        ZStack {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 4)
                .frame(maxHeight: .infinity)
            Image(systemName: "arrow.left.and.right")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(4)
                .background(Color(.systemBackground))
                .clipShape(Circle())
                .shadow(radius: 1)
        }
        .frame(width: 12)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    if dragStartTranslationRatio == nil {
                        dragStartTranslationRatio = translationPanelWidthRatio
                    }
                    let start = dragStartTranslationRatio ?? translationPanelWidthRatio
                    let newRatio = start + (value.translation.width / totalWidth)
                    translationPanelWidthRatio = max(0.25, min(0.65, newRatio))
                }
                .onEnded { _ in
                    dragStartTranslationRatio = nil
                }
        )
    }

    private func highlightedTargetText() -> Text {
        guard ttsVM.isSpeaking, ttsVM.currentSpokenText == activeExpectedText else {
            return Text(activeExpectedText)
        }

        guard let range = ttsVM.currentWordRange,
              let swiftRange = Range(range, in: activeExpectedText) else {
            return Text(activeExpectedText)
        }

        let prefix = String(activeExpectedText[..<swiftRange.lowerBound])
        let highlighted = String(activeExpectedText[swiftRange])
        let suffix = String(activeExpectedText[swiftRange.upperBound...])

        return Text(prefix)
        + Text(highlighted).bold().foregroundColor(.orange)
        + Text(suffix)
    }

    private func highlightedSentenceText(_ sentence: String) -> Text {
        guard ttsVM.isSpeaking,
              sentence == currentSentenceText,
              ttsVM.currentSpokenText == currentSentenceText else {
            return Text(sentence)
        }

        guard let range = ttsVM.currentWordRange,
              let swiftRange = Range(range, in: sentence) else {
            return Text(sentence)
        }

        let prefix = String(sentence[..<swiftRange.lowerBound])
        let highlighted = String(sentence[swiftRange])
        let suffix = String(sentence[swiftRange.upperBound...])

        return Text(prefix)
        + Text(highlighted).bold().foregroundColor(.orange)
        + Text(suffix)
    }

    private func resetPracticeSession(resetCursor: Bool) {
        if resetCursor {
            currentSentenceIndex = 0
        } else {
            currentSentenceIndex = min(currentSentenceIndex, max(totalSentencesAvailable - 1, 0))
        }
        sessionSentenceCount = min(max(sessionSentenceCount, 1), max(totalSentencesAvailable, 1))
        alternateAwaitingChildTurn = false
        alternatePendingSystemAdvance = false
        clearCurrentAttempt()
        resetFullTextTimer()
        if ttsVM.isSpeaking {
            ttsVM.stop()
        }
    }

    private func clearCurrentAttempt() {
        // Recording/scoring is temporarily disabled.
    }

    private var fullTextTimerControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Timed Reading", systemImage: "timer")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(timerStatusText)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(fullTextElapsedSeconds > fullTextTargetSeconds ? .red : .green)
            }

            HStack(spacing: 10) {
                Button("Goal \(formattedDuration(fullTextTargetSeconds))") {
                    isShowingTimerGoalEditor = true
                }
                .buttonStyle(.bordered)
                .disabled(fullTextTimerIsRunning)

                Button(fullTextTimerIsRunning ? "Stop Timer" : "Start Timer") {
                    fullTextTimerIsRunning.toggle()
                }
                .buttonStyle(.bordered)
                .disabled(fullTextTargetSeconds == 0 && !fullTextTimerIsRunning)

                Button("Reset") {
                    resetFullTextTimer()
                }
                .buttonStyle(.bordered)
            }

            ProgressView(
                value: min(Double(fullTextElapsedSeconds), Double(fullTextTargetSeconds)),
                total: max(Double(fullTextTargetSeconds), 1)
            )
            .tint(fullTextElapsedSeconds > fullTextTargetSeconds ? .red : .green)
        }
        .padding(12)
        .background(Color.purple.opacity(0.08))
        .cornerRadius(12)
        .sheet(isPresented: $isShowingTimerGoalEditor) {
            NavigationStack {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Picker("Minutes", selection: fullTextGoalMinutesBinding) {
                            ForEach(0...30, id: \.self) { minute in
                                Text("\(minute) m").tag(minute)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)

                        Picker("Seconds", selection: fullTextGoalSecondStepBinding) {
                            ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { seconds in
                                Text(String(format: "%02d s", seconds)).tag(seconds)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: 180)
                }
                .navigationTitle("Set Goal Time")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            isShowingTimerGoalEditor = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var timerStatusText: String {
        let elapsed = formattedDuration(fullTextElapsedSeconds)
        if fullTextElapsedSeconds <= fullTextTargetSeconds {
            let remaining = formattedDuration(fullTextTargetSeconds - fullTextElapsedSeconds)
            return "\(elapsed) elapsed • \(remaining) left"
        }
        let overtime = formattedDuration(fullTextElapsedSeconds - fullTextTargetSeconds)
        return "\(elapsed) elapsed • +\(overtime)"
    }

    private func resetFullTextTimer() {
        fullTextTimerIsRunning = false
        fullTextElapsedSeconds = 0
    }

    private var fullTextGoalMinutesBinding: Binding<Int> {
        Binding(
            get: { fullTextTargetSeconds / 60 },
            set: { newMinutes in
                let clampedMinutes = min(max(newMinutes, 0), 30)
                let seconds = fullTextTargetSeconds % 60
                fullTextTargetSeconds = (clampedMinutes * 60) + seconds
            }
        )
    }

    private var fullTextGoalSecondStepBinding: Binding<Int> {
        Binding(
            get: { ((fullTextTargetSeconds % 60) / 5) * 5 },
            set: { newSeconds in
                let clampedSeconds = min(max(newSeconds, 0), 55)
                let steppedSeconds = (clampedSeconds / 5) * 5
                let minutes = fullTextTargetSeconds / 60
                fullTextTargetSeconds = (minutes * 60) + steppedSeconds
            }
        )
    }

    private func icon(for mode: SentenceListeningMode) -> String {
        switch mode {
        case .fullText:
            return "text.alignleft"
        case .fullSentence:
            return "speaker.wave.2.fill"
        case .pauseOnRandomWord:
            return "pause.circle.fill"
        case .highlightOnly:
            return "highlighter"
        case .alternateSentences:
            return "arrow.left.arrow.right.circle.fill"
        }
    }

    private func description(for mode: SentenceListeningMode) -> String {
        switch mode {
        case .fullText:
            return "Read and score the entire selected text."
        case .fullSentence:
            return "System reads the whole sentence."
        case .pauseOnRandomWord:
            return "System pauses at a random word."
        case .highlightOnly:
            return "Silent highlighting guides the child."
        case .alternateSentences:
            return "System sentence, then child sentence."
        }
    }

    private func formattedDuration(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var listenButtonTitle: String {
        if ttsVM.isPaused {
            return "Resume"
        }
        if sentenceListeningMode == .alternateSentences && alternateAwaitingChildTurn {
            return "Continue"
        }
        return ttsVM.isSpeaking ? "Stop" : "Listen"
    }

    private var listenButtonIcon: String {
        if ttsVM.isPaused {
            return "play.fill"
        }
        if sentenceListeningMode == .alternateSentences && alternateAwaitingChildTurn {
            return "arrow.right.circle.fill"
        }
        return ttsVM.isSpeaking ? "stop.fill" : "speaker.wave.3.fill"
    }

    private func handleListenButtonTapped() {
        if sentenceListeningMode == .alternateSentences && alternateAwaitingChildTurn {
            let lastIndex = max(totalSentencesAvailable - 1, 0)
            guard currentSentenceIndex < lastIndex else { return }
            currentSentenceIndex += 1
            alternateAwaitingChildTurn = false
        }

        if ttsVM.isPaused {
            ttsVM.resume()
            return
        }

        if ttsVM.isSpeaking {
            alternatePendingSystemAdvance = false
            ttsVM.stop()
            return
        }

        let text = activeExpectedText
        guard !text.isEmpty else { return }

        switch sentenceListeningMode {
        case .fullText:
            ttsVM.speak(text: text)
        case .fullSentence:
            ttsVM.speak(text: text)
        case .pauseOnRandomWord:
            ttsVM.speakWithPauseAtRandomWord(text: text)
        case .highlightOnly:
            ttsVM.followHighlightedWordsOnly(text: text)
        case .alternateSentences:
            alternatePendingSystemAdvance = true
            ttsVM.speak(text: text)
        }
    }

    private func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        let separators = CharacterSet(charactersIn: ".!?")

        for scalar in text.unicodeScalars {
            current.unicodeScalars.append(scalar)
            if separators.contains(scalar) {
                let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty {
                    sentences.append(sentence)
                }
                current = ""
            }
        }

        let trailing = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trailing.isEmpty {
            sentences.append(trailing)
        }

        return sentences
    }
}

#if canImport(Translation)
@available(iOS 26.4, *)
private struct TranslationPanel: View {
    let sourceText: String

    @State private var translatedText = ""
    @State private var isTranslating = false
    @State private var errorMessage: String? = nil
    @State private var lastTranslatedSource = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("English Translation", systemImage: "globe")
                .font(.headline)

            if isTranslating {
                ProgressView("Translating…")
            } else if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.secondary)
            } else if translatedText.isEmpty {
                Text("Translation will appear here.")
                    .foregroundColor(.secondary)
            } else {
                Text(translatedText)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(16)
        .translationTask(
            source: Locale.Language(identifier: "fr"),
            target: Locale.Language(identifier: "en"),
            preferredStrategy: .highFidelity
        ) { session in
            let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                translatedText = ""
                errorMessage = nil
                lastTranslatedSource = ""
                return
            }
            guard trimmed != lastTranslatedSource else {
                return
            }

            isTranslating = true
            do {
                let response = try await session.translate(trimmed)
                translatedText = response.targetText
                errorMessage = nil
                lastTranslatedSource = trimmed
            } catch {
                errorMessage = "Translation unavailable right now. Please try again."
            }
            isTranslating = false
        }
    }
}
#endif
