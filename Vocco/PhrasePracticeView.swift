import SwiftUI

struct PhrasePracticeView: View {
    let deck: Deck

    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable { case ready, recording, scoring, result }

    @State private var phraseIndex = 0
    @State private var phase: Phase = .ready
    @State private var result: ScoreResult?
    @State private var deckComplete = false
    @State private var takeURL: URL?

    @State private var recorder = VoiceRecorder()
    @State private var player = TakePlayer()
    @State private var speaker = DeviceSpeaker()
    @State private var ttsCache: [String: Data] = [:]
    @State private var idealLoading = false
    @State private var slowMode = false
    @State private var alertMessage: String?

    private var phrase: Phrase {
        deck.phrases.indices.contains(phraseIndex)
            ? deck.phrases[phraseIndex]
            : Phrase(text: "", ipa: "", translation: "", tip: "")
    }
    private var bookmarkKey: String { "\(deck.id):\(phraseIndex)" }

    var body: some View {
        VStack(spacing: 14) {
            header
            if deckComplete {
                completeCard
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        PhraseCard(phrase: phrase)
                        if !phrase.text.isEmpty { hearRow }
                        switch phase {
                        case .ready:
                            TipBanner(text: phrase.tip)
                            MicButton(recording: false, elapsed: 0, action: startRecording)
                        case .recording:
                            MicButton(recording: true, elapsed: recorder.elapsed, action: finishRecording)
                        case .scoring:
                            scoringCard
                        case .result:
                            if let outcome = result {
                                ResultCard(outcome: outcome,
                                           phrase: phrase,
                                           hasTake: takeURL != nil,
                                           idealLoading: idealLoading,
                                           onPlayMine: playMine,
                                           onPlayIdeal: hearIdeal)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                        footerButtons
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(Brand.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .alert("Vocco",
               isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .onReceive(Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()) { _ in
            if phase == .recording,
               recorder.elapsed >= 11.85 || !recorder.isRecording {
                finishRecording()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button { dismiss() } label: { circleIcon("chevron.left") }
                .accessibilityLabel("Back")
            Spacer()
            VStack(spacing: 3) {
                Text(deck.title).font(.vocco(16, .heavy)).foregroundStyle(Brand.fg)
                Text("Phrase \(phraseIndex + 1) of \(deck.phrases.count)")
                    .font(.voccoMono(10.5)).kerning(1.2).foregroundStyle(Brand.muted)
            }
            Spacer()
            Button { store.toggleBookmark(bookmarkKey) } label: {
                circleIcon(store.bookmarks.contains(bookmarkKey) ? "bookmark.fill" : "bookmark")
            }
            .accessibilityLabel("Save phrase")
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    private func circleIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Brand.fg)
            .frame(width: 38, height: 38)
            .background(Circle().fill(Color.white))
            .shadow(color: Brand.fg.opacity(0.08), radius: 8, y: 3)
    }

    // MARK: Hear it + speed

    private var hearRow: some View {
        HStack(spacing: 10) {
            Button(action: hearIdeal) {
                HStack(spacing: 8) {
                    if idealLoading {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "waveform").font(.system(size: 15, weight: .bold))
                    }
                    Text(idealLoading ? "Loading…" : "Hear it")
                }
            }
            .buttonStyle(PillButtonStyle(expands: false))
            .disabled(idealLoading)
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                speedSegment(slow: true, icon: "tortoise.fill", label: "Slow")
                speedSegment(slow: false, icon: "hare.fill", label: "Normal")
            }
            .fixedSize()
            .padding(4)
            .background(Capsule().fill(Color.white))
            .shadow(color: Brand.fg.opacity(0.06), radius: 8, y: 3)
        }
    }

    private func speedSegment(slow: Bool, icon: String, label: String) -> some View {
        let selected = slowMode == slow
        return Button { slowMode = slow } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(label).font(.vocco(13, .semibold))
            }
            .foregroundStyle(selected ? Brand.fg : Brand.muted)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(Capsule().fill(selected ? Brand.lilac : Color.clear))
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) speed")
    }

    private var scoringCard: some View {
        HStack(spacing: 12) {
            ProgressView().tint(Brand.coral)
            Text("Scoring your take…")
                .font(.vocco(15, .semibold))
                .foregroundStyle(Brand.fg.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: Footer

    @ViewBuilder
    private var footerButtons: some View {
        if phase == .result {
            HStack(spacing: 10) {
                Button(action: startRecording) {
                    Text("Try again").frame(maxWidth: .infinity)
                }
                .buttonStyle(.voccoGhost)
                Button(action: nextPhrase) {
                    HStack(spacing: 4) {
                        Text("Next phrase")
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.voccoPill)
            }
        } else if phase != .recording {
            Button(action: nextPhrase) {
                HStack(spacing: 4) {
                    Text("Next phrase")
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                }
            }
            .buttonStyle(.voccoPill)
        }
    }

    private var completeCard: some View {
        VStack(spacing: 14) {
            Text("🎉").font(.system(size: 44))
            Text("Deck complete!")
                .font(.vocco(26, .heavy))
                .foregroundStyle(Brand.fg)
            Text("You practiced \(deck.phrases.count) phrases of \(deck.title).")
                .font(.voccoMono(12))
                .foregroundStyle(Brand.muted)
                .multilineTextAlignment(.center)
            Button("Back to home") { dismiss() }
                .buttonStyle(.voccoGhost)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .vCard(fill: Brand.lilac)
        .padding(.horizontal, 20)
        .padding(.top, 40)
    }

    // MARK: Actions

    private func startRecording() {
        player.stop()
        guard !deck.phrases.isEmpty else { return }
        do {
            try recorder.start()
            withAnimation(.spring(response: 0.35)) { phase = .recording }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func finishRecording() {
        guard phase == .recording else { return }
        do {
            let url = try recorder.stop()
            takeURL = url
            scoreTake(at: url)
        } catch {
            withAnimation(.spring(response: 0.3)) { phase = .ready }
            alertMessage = error.localizedDescription
        }
    }

    private func scoreTake(at url: URL) {
        guard !store.settings.apiKey.isEmpty else {
            alertMessage = VoccoError.noKey.errorDescription
            phase = .ready
            return
        }
        withAnimation(.spring(response: 0.3)) { phase = .scoring }
        let text = phrase.text
        let deckId = deck.id
        let index = phraseIndex
        Task { @MainActor in
            do {
                let heard = try await ElevenLabs(apiKey: store.settings.apiKey).transcribe(file: url)
                let outcome = Scorer.score(target: text, heard: heard)
                result = outcome
                store.record(Attempt(deckId: deckId, phraseIdx: index, score: outcome.score,
                                     offWords: outcome.offWords, nailedWords: outcome.nailedWords,
                                     date: Date()))
                withAnimation(.spring(response: 0.4)) { phase = .result }
            } catch {
                withAnimation(.spring(response: 0.3)) { phase = .ready }
                alertMessage = error.localizedDescription
            }
        }
    }

    private func hearIdeal() {
        guard !idealLoading, !phrase.text.isEmpty else { return }
        idealLoading = true
        let text = phrase.text
        let voiceId = store.settings.voiceId
        let useSlow = slowMode
        let rate: Float = slowMode ? 0.65 : 1.0
        Task { @MainActor in
            defer { idealLoading = false }
            do {
                if store.settings.apiKey.isEmpty {
                    speaker.say(text, slow: useSlow)
                    return
                }
                let cacheKey = "\(text)|\(voiceId)"
                if ttsCache[cacheKey] == nil {
                    ttsCache[cacheKey] = try await ElevenLabs(apiKey: store.settings.apiKey)
                        .tts(text: text, voiceId: voiceId)
                }
                if let audioData = ttsCache[cacheKey] {
                    player.play(data: audioData, rate: rate)
                }
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    private func playMine() {
        guard let url = takeURL else { return }
        player.play(url: url)
    }

    private func nextPhrase() {
        player.stop()
        if phraseIndex + 1 < deck.phrases.count {
            phraseIndex += 1
            phase = .ready
            result = nil
            takeURL = nil
        } else {
            withAnimation(.spring(response: 0.4)) { deckComplete = true }
        }
    }
}

// MARK: - Phrase card

private struct PhraseCard: View {
    let phrase: Phrase

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Say it")
            Text(phrase.text)
                .font(.vocco(24, .heavy))
                .foregroundStyle(Brand.fg)
                .fixedSize(horizontal: false, vertical: true)
            if !phrase.ipa.isEmpty {
                Text(phrase.ipa)
                    .font(.voccoMono(14))
                    .foregroundStyle(Brand.fg.opacity(0.55))
            }
            if !phrase.translation.isEmpty {
                Rectangle().fill(Brand.fg.opacity(0.08)).frame(height: 1)
                HStack(spacing: 8) {
                    Text("TR")
                        .font(.voccoMono(10, .bold))
                        .foregroundStyle(Brand.fg.opacity(0.6))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Brand.fg.opacity(0.08)))
                    Text(phrase.translation)
                        .font(.vocco(14))
                        .foregroundStyle(Brand.fg.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vCard()
    }
}

// MARK: - Tip banner (coach surface)

private struct TipBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            SectionLabel("Tip")
            Text(text)
                .font(.vocco(13.5))
                .foregroundStyle(Brand.fg.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Brand.lilac))
    }
}

// MARK: - Mic button

private struct MicButton: View {
    let recording: Bool
    let elapsed: TimeInterval
    let action: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Button(action: action) {
                ZStack {
                    Circle()
                        .stroke(Brand.coral.opacity(0.4),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.5, 7]))
                        .frame(width: 124, height: 124)
                    if recording {
                        Circle()
                            .fill(Brand.coral.opacity(0.16))
                            .frame(width: 142, height: 142)
                            .pulsing()
                    }
                    Circle()
                        .fill(Brand.coral)
                        .frame(width: 96, height: 96)
                        .shadow(color: Brand.coral.opacity(0.4), radius: 16, y: 6)
                    Image(systemName: recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recording ? "Stop recording" : "Record your voice")

            if recording {
                Text(String(format: "0:%02d", Int(elapsed)))
                    .font(.voccoMono(16, .semibold))
                    .foregroundStyle(Brand.coral)
                Text("Tap to stop")
                    .font(.voccoMono(11.5)).kerning(1.2).foregroundStyle(Brand.muted)
            } else {
                Text("Tap to record")
                    .font(.voccoMono(11.5)).kerning(1.2).foregroundStyle(Brand.muted)
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Result card

private struct ResultCard: View {
    let outcome: ScoreResult
    let phrase: Phrase
    let hasTake: Bool
    let idealLoading: Bool
    let onPlayMine: () -> Void
    let onPlayIdeal: () -> Void

    private var headline: String {
        switch outcome.score {
        case 90...: return "Native-like!"
        case 75...: return "Almost native!"
        case 50...: return "Getting there"
        default: return "Keep practicing"
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 18) {
                ScoreRing(progress: Double(outcome.score) / 100,
                          lineWidth: 9,
                          size: 92,
                          label: "\(outcome.score)",
                          labelSize: 24)
                VStack(alignment: .leading, spacing: 6) {
                    Text(headline)
                        .font(.vocco(20, .heavy))
                        .foregroundStyle(Brand.fg)
                    Text(outcome.offWords.isEmpty
                         ? "Every word on target. 🎯"
                         : (outcome.offCount == 1 ? "One word to polish:" : "\(outcome.offCount) words to polish:"))
                        .font(.vocco(13.5))
                        .foregroundStyle(Brand.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if let firstOff = outcome.offWords.first {
                HStack(spacing: 10) {
                    Text(firstOff).font(.voccoMono(15, .bold)).foregroundStyle(Brand.amberInk)
                    Text(phrase.tip)
                        .font(.vocco(13))
                        .foregroundStyle(Brand.fg.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Brand.amber.opacity(0.14)))
            }
            FlowLayout(spacing: 8) {
                ForEach(outcome.words) { scoredWord in
                    WordChip(scored: scoredWord)
                }
            }
            HStack(spacing: 8) {
                Circle().fill(Brand.teal).frame(width: 7, height: 7)
                Text("Nailed").font(.voccoMono(10.5)).foregroundStyle(Brand.muted)
                Circle().fill(Brand.amber).frame(width: 7, height: 7).padding(.leading, 6)
                Text("Off").font(.voccoMono(10.5)).foregroundStyle(Brand.muted)
                Spacer()
                Text("\(outcome.nailedCount) nailed · \(outcome.offCount) to polish")
                    .font(.voccoMono(10.5))
                    .foregroundStyle(Brand.fg.opacity(0.5))
            }
            HStack(spacing: 10) {
                Button(action: onPlayMine) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.wave.2.fill").font(.system(size: 14, weight: .semibold))
                        Text("Play mine")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.voccoGhost)
                .disabled(!hasTake)
                Button(action: onPlayIdeal) {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform").font(.system(size: 14, weight: .semibold))
                        Text("Play ideal")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.voccoGhost)
                .disabled(idealLoading)
            }
        }
        .vCard()
        .id(outcome.score)
    }
}
