import AVFoundation
import Foundation

// MARK: - Errors

enum VoccoError: LocalizedError {
    case noKey
    case micDenied
    case api(String)
    case emptyTake

    var errorDescription: String? {
        switch self {
        case .noKey:
            return "ElevenLabs key not found on this device — reinstall the latest app build."
        case .micDenied:
            return "Microphone access is off — allow it in Settings → Vocco."
        case .api(let message):
            return message
        case .emptyTake:
            return "Recording too short — hold the mic a bit longer."
        }
    }
}

// MARK: - Audio session

enum AudioSession {
    static func activate() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default,
                                 options: [.defaultToSpeaker, .allowBluetoothHFP])
        try? session.setActive(true)
    }
}

// MARK: - Recorder

@Observable
final class VoiceRecorder {
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private(set) var elapsed: TimeInterval = 0

    /// Fired once when the 12 s cap is hit or the hardware stops on its own.
    var onAutoFinish: (() -> Void)?

    var takeURL: URL? { recorder?.url }
    var isRecording: Bool { recorder?.isRecording ?? false }

    func start() throws {
        AudioSession.activate()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vocco-take.m4a")
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let newRecorder = try AVAudioRecorder(url: url, settings: settings)
        guard newRecorder.record(forDuration: 12) else {
            print("[vocco] record() failed to start — mic permission or session issue")
            throw VoccoError.micDenied
        }
        recorder = newRecorder
        elapsed = 0
        print("[vocco] recording started")
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.elapsed = self.recorder?.currentTime ?? 0
                let hardwareStopped = self.recorder != nil && self.recorder?.isRecording == false
                if self.elapsed >= 11.9 || hardwareStopped {
                    self.autoFinish()
                }
            }
        }
    }

    private func autoFinish() {
        timer?.invalidate()
        timer = nil
        print("[vocco] auto finish at \(elapsed)s")
        onAutoFinish?()
    }

    /// Stops and returns the take URL, or throws when nothing usable was recorded.
    func stop() throws -> URL {
        timer?.invalidate()
        timer = nil
        let duration = elapsed
        let url = recorder?.url
        recorder?.stop()
        print("[vocco] stop: duration=\(String(format: "%.1f", duration))s")
        guard duration >= 0.4, let url, FileManager.default.fileExists(atPath: url.path) else {
            throw VoccoError.emptyTake
        }
        return url
    }
}

// MARK: - Player

final class TakePlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?

    func play(data: Data, rate: Float = 1.0) {
        AudioSession.activate()
        guard let audioPlayer = try? AVAudioPlayer(data: data) else { return }
        audioPlayer.enableRate = true
        audioPlayer.rate = rate
        audioPlayer.delegate = self
        player = audioPlayer
        audioPlayer.play()
    }

    func play(url: URL, rate: Float = 1.0) {
        AudioSession.activate()
        guard let audioPlayer = try? AVAudioPlayer(contentsOf: url) else { return }
        audioPlayer.enableRate = true
        audioPlayer.rate = rate
        audioPlayer.delegate = self
        player = audioPlayer
        audioPlayer.play()
    }

    func stop() {
        player?.stop()
        player = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in self?.player = nil }
    }
}

// MARK: - Device voice fallback (no API key)

final class DeviceSpeaker {
    private let synthesizer = AVSpeechSynthesizer()

    func say(_ text: String, slow: Bool) {
        AudioSession.activate()
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = slow ? 0.42 : 0.5
        synthesizer.speak(utterance)
    }
}

// MARK: - ElevenLabs (TTS + Scribe) — the only paid service, zero LLM tokens

struct ElevenLabs {
    let apiKey: String

    static func ttsURL(voiceId: String) -> URL {
        var components = URLComponents(url: URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)")!,
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "output_format", value: "mp3_44100_128")]
        return components.url!
    }

    /// Ideal pronunciation audio (mp3 data). Flash v2.5: cheapest per-character model.
    func tts(text: String, voiceId: String) async throws -> Data {
        var request = URLRequest(url: Self.ttsURL(voiceId: voiceId))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_flash_v2_5",
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.75, "style": 0.3, "use_speaker_boost": true],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw VoccoError.api(Self.failureMessage("Text-to-speech", data: data, response: response))
        }
        return data
    }

    /// Scribe speech-to-text for the learner's take.
    func transcribe(file: URL) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        let boundary = "vocco-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("model_id", "scribe_v1")
        field("language_code", "eng")
        let audio = try Data(contentsOf: file)
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"take.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw VoccoError.api(Self.failureMessage("Speech-to-text", data: data, response: response))
        }
        struct ScribeResponse: Decodable { let text: String }
        do {
            let decoded = try JSONDecoder().decode(ScribeResponse.self, from: data)
            print("[vocco] scribe heard: \(decoded.text)")
            return decoded.text
        } catch {
            throw VoccoError.api("Speech-to-text returned an unexpected response.")
        }
    }

    private static func failureMessage(_ operation: String, data: Data, response: URLResponse) -> String {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let detail = String(data: data.prefix(200), encoding: .utf8) ?? ""
        if status == 401 { return "\(operation) failed — check your API key." }
        return "\(operation) failed (\(status)). \(detail)"
    }
}
