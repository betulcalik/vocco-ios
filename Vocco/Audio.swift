import AVFoundation
import Foundation

// MARK: - Errors

enum VoccoError: LocalizedError {
    case noKey
    case api(String)
    case emptyTake

    var errorDescription: String? {
        switch self {
        case .noKey:
            return "Add your ElevenLabs API key in Settings to score your speech."
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
        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.record(forDuration: 12)
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.elapsed = self.recorder?.currentTime ?? 0
            }
        }
    }

    /// Stops and returns the take URL, or nil when nothing usable was recorded.
    func stop() throws -> URL {
        timer?.invalidate()
        timer = nil
        let duration = elapsed
        let url = recorder?.url
        recorder?.stop()
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

    /// Ideal pronunciation audio (mp3 data). eleven_flash: cheapest per-character model.
    func tts(text: String, voiceId: String) async throws -> Data {
        var request = URLRequest(url: Self.ttsURL(voiceId: voiceId))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_flash",
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
            return try JSONDecoder().decode(ScribeResponse.self, from: data).text
        } catch {
            throw VoccoError.api("Speech-to-text returned an unexpected response.")
        }
    }

    private static func failureMessage(_ operation: String, data: Data, response: URLResponse) -> String {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let detail = String(data: data.prefix(200), encoding: .utf8) ?? ""
        if status == 401 { return "\(operation) failed — check your API key in Settings." }
        return "\(operation) failed (\(status)). \(detail)"
    }
}
