import SwiftUI

struct SettingsView: View {
    @Environment(Store.self) private var store

    @State private var previewingVoiceId: String?
    @State private var previewCache: [String: Data] = [:]

    private static let voiceTints: [Color] = [Brand.coral, Brand.fg, Brand.teal, Brand.amber]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Text("Settings")
                        .font(.vocco(30, .heavy))
                        .foregroundStyle(Brand.fg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    voiceCard
                    goalCard
                    reminderCard
                    aboutCard
                }
                .padding(20)
            }
            .background(Brand.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Coach voice

    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Coach voice")
            ForEach(Array(VoiceInfo.all.enumerated()), id: \.element.id) { index, voice in
                voiceRow(voice, tint: Self.voiceTints[index % Self.voiceTints.count])
            }
        }
        .vCard()
    }

    private func voiceRow(_ voice: VoiceInfo, tint: Color) -> some View {
        let selected = store.settings.voiceId == voice.id
        return Button {
            store.selectVoice(voice.id)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint).frame(width: 40, height: 40)
                    Text(voice.name.prefix(1))
                        .font(.vocco(15, .heavy))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(voice.name).font(.vocco(15, .bold)).foregroundStyle(Brand.fg)
                    Text(voice.desc).font(.voccoMono(11.5)).foregroundStyle(Brand.muted)
                }
                Spacer()
                Button {
                    previewVoice(voice)
                } label: {
                    Group {
                        if previewingVoiceId == voice.id {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "speaker.wave.2.fill").font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .foregroundStyle(Brand.fg)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Brand.lilac))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Preview \(voice.name)")
                ZStack {
                    Circle().strokeBorder(Brand.fg.opacity(0.2), lineWidth: 1.5).frame(width: 20, height: 20)
                    if selected {
                        Circle().fill(Brand.coral).frame(width: 10, height: 10)
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(selected ? Brand.lilac : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose voice \(voice.name)")
    }

    private func previewVoice(_ voice: VoiceInfo) {
        guard previewingVoiceId == nil else { return }
        previewingVoiceId = voice.id
        let sample = "Hi, I'm \(voice.name). Let's practice your pronunciation."
        Task { @MainActor in
            defer { previewingVoiceId = nil }
            if store.apiKey.isEmpty {
                speakerFallback.say(sample, slow: false)
                return
            }
            do {
                if previewCache[voice.id] == nil {
                    previewCache[voice.id] = try await ElevenLabs(apiKey: store.apiKey)
                        .tts(text: sample, voiceId: voice.id)
                }
                if let audioData = previewCache[voice.id] {
                    previewPlayer.play(data: audioData)
                }
            } catch {
                previewingVoiceId = nil
            }
        }
    }

    @State private var previewPlayer = TakePlayer()
    @State private var speakerFallback = DeviceSpeaker()

    // MARK: Daily goal

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Daily goal")
            Picker("Daily goal", selection: Binding(get: { store.settings.dailyGoal },
                                                    set: { store.setDailyGoal($0) })) {
                Text("5").tag(5)
                Text("10").tag(10)
                Text("20").tag(20)
            }
            .pickerStyle(.segmented)
            Text("\(store.settings.dailyGoal) phrases · about \(minutesPerDay) minutes a day")
                .font(.voccoMono(10.5))
                .foregroundStyle(Brand.muted)
        }
        .vCard()
    }

    private var minutesPerDay: Int {
        switch store.settings.dailyGoal {
        case 5: return 3
        case 10: return 6
        default: return 12
        }
    }

    // MARK: Reminders

    private var reminderCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Practice reminder").font(.vocco(15, .bold)).foregroundStyle(Brand.fg)
                Text("Every day, 7:00 PM").font(.voccoMono(11.5)).foregroundStyle(Brand.muted)
            }
            Spacer()
            Toggle("Practice reminder", isOn: Binding(get: { store.settings.reminderOn },
                                                      set: { store.setReminder($0) }))
                .labelsHidden()
                .tint(Brand.coral)
        }
        .vCard()
    }

    // MARK: About

    private var aboutCard: some View {
        VStack(spacing: 6) {
            Text("Vocco 0.1.0").font(.voccoMono(11)).foregroundStyle(Brand.muted)
            Text("Voices & transcription by ElevenLabs").font(.voccoMono(11)).foregroundStyle(Brand.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}
