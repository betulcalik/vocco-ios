import Foundation
import Observation
import UserNotifications

/// App state. Main-thread use (all mutations happen from UI or MainActor tasks).
@Observable
final class Store {

    static let decks: [Deck] = Bundle.loadDecks()

    // MARK: State

    private(set) var settings: Settings
    private(set) var attempts: [Attempt]
    private(set) var bookmarks: Set<String>
    private let fileURL: URL

    /// User's ElevenLabs key (BYOK) — lives only in the Keychain, never in the state file.
    private(set) var apiKey: String

    init(settings: Settings, attempts: [Attempt], bookmarks: Set<String>, fileURL: URL) {
        self.settings = settings
        self.attempts = attempts
        self.bookmarks = bookmarks
        self.fileURL = fileURL
        self.apiKey = Keychain.read() ?? ""
        if apiKey.isEmpty, let bundled = Self.bundledKey(), !bundled.isEmpty {
            Keychain.write(bundled)
            apiKey = bundled
        }
    }

    /// Dev-only seed: a git-ignored `Secret.key` bundled into personal builds.
    private static func bundledKey() -> String? {
        guard let url = Bundle.main.url(forResource: "Secret", withExtension: "key"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func load() -> Store {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let url = support.appendingPathComponent("vocco-state.json")
        if let data = try? Data(contentsOf: url),
           let persisted = try? JSONDecoder().decode(Persisted.self, from: data) {
            return Store(settings: persisted.settings,
                         attempts: persisted.attempts,
                         bookmarks: persisted.bookmarks,
                         fileURL: url)
        }
        return Store(settings: Settings(), attempts: [], bookmarks: [], fileURL: url)
    }

    private func persist() {
        let snapshot = Persisted(settings: settings, attempts: attempts, bookmarks: bookmarks)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: Mutations

    func record(_ attempt: Attempt) {
        attempts.append(attempt)
        persist()
    }

    func toggleBookmark(_ key: String) {
        if bookmarks.contains(key) { bookmarks.remove(key) } else { bookmarks.insert(key) }
        persist()
    }

    func selectVoice(_ voiceId: String) {
        settings.voiceId = voiceId
        persist()
    }

    func setDailyGoal(_ goal: Int) {
        settings.dailyGoal = goal
        persist()
    }

    func setReminder(_ on: Bool) {
        settings.reminderOn = on
        persist()
        Task { await syncReminder() }
    }

    func setAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKey = trimmed
        if trimmed.isEmpty {
            Keychain.delete()
        } else {
            Keychain.write(trimmed)
        }
    }

    // MARK: Reminder (daily 7 PM local)

    func syncReminder() async {
        let center = UNUserNotificationCenter.current()
        let identifier = "vocco.daily"
        guard settings.reminderOn else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }
        let content = UNMutableNotificationContent()
        content.title = "Vocco"
        content.body = "Time for your \(settings.dailyGoal) phrases — keep the streak alive! 🔥"
        content.sound = .default
        var components = DateComponents()
        components.hour = 19
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    // MARK: Derived

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func dayKey(_ date: Date) -> String { dayFormatter.string(from: date) }

    private var practicedDays: Set<String> { Set(attempts.map { Store.dayKey($0.date) }) }

    var todayAttemptCount: Int {
        attempts.filter { Calendar.current.isDateInToday($0.date) }.count
    }

    var streak: Int {
        let calendar = Calendar.current
        var day = Date()
        var count = 0
        if !practicedDays.contains(Store.dayKey(day)) {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = previous
        }
        while practicedDays.contains(Store.dayKey(day)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    var bestStreak: Int {
        let calendar = Calendar.current
        let sortedDays = practicedDays.sorted().compactMap { Store.dayFormatter.date(from: $0) }
        var best = 0
        var run = 0
        var previous: Date?
        for day in sortedDays {
            if let prior = previous, let next = calendar.date(byAdding: .day, value: 1, to: prior),
               calendar.isDate(day, inSameDayAs: next) {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return max(best, streak)
    }

    var averageScore: Int {
        guard !attempts.isEmpty else { return 0 }
        return attempts.map(\.score).reduce(0, +) / attempts.count
    }

    /// Keys "deckId:phraseIdx" whose best attempt reached mastery (≥ 85).
    var masteredKeys: Set<String> {
        var best: [String: Int] = [:]
        for attempt in attempts {
            let key = "\(attempt.deckId):\(attempt.phraseIdx)"
            best[key] = max(best[key] ?? 0, attempt.score)
        }
        return Set(best.filter { $0.value >= 85 }.keys)
    }

    func masteredCount(in deck: Deck) -> Int {
        deck.phrases.indices.filter { masteredKeys.contains("\(deck.id):\($0)") }.count
    }

    var todayDeck: Deck {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return Store.decks.isEmpty
            ? Deck(id: "empty", title: "Vocco", emoji: "🎙️", phrases: [])
            : Store.decks[dayOfYear % Store.decks.count]
    }

    // MARK: Calendar (8 week columns of 7 dots, oldest → today)

    struct CalendarDay: Identifiable, Hashable {
        let date: Date
        let practiced: Bool
        let isToday: Bool
        var id: Date { date }
    }

    var calendarDays: [[CalendarDay]] {
        let calendar = Calendar.current
        var weeks: [[CalendarDay]] = []
        for weekIndex in stride(from: 8, through: 1, by: -1) {
            var column: [CalendarDay] = []
            for dayIndex in 0..<7 {
                let offset = (weekIndex - 1) * 7 + (6 - dayIndex)
                guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
                column.append(CalendarDay(date: date,
                                          practiced: practicedDays.contains(Store.dayKey(date)),
                                          isToday: calendar.isDateInToday(date)))
            }
            weeks.append(column)
        }
        return weeks
    }

    // MARK: Weekly accuracy (8 buckets, oldest → newest)

    struct WeekPoint: Identifiable {
        let id: Int
        let label: String
        let value: Double
    }

    var weeklyAccuracy: [WeekPoint] {
        let calendar = Calendar.current
        var buckets = Array(repeating: [Int](), count: 8)
        for attempt in attempts {
            let daysAgo = calendar.dateComponents([.day],
                                                  from: calendar.startOfDay(for: attempt.date),
                                                  to: calendar.startOfDay(for: Date())).day ?? 0
            if daysAgo >= 0 && daysAgo < 56 {
                buckets[7 - daysAgo / 7].append(attempt.score)
            }
        }
        return buckets.enumerated().compactMap { index, scores in
            guard !scores.isEmpty else { return nil }
            let label = index == 7 ? "Now" : "W\(index + 1)"
            let value = Double(scores.reduce(0, +)) / Double(scores.count)
            return WeekPoint(id: index, label: label, value: value)
        }
    }

    /// Frequently missed words, weakest first, with mastery ratio (0–1).
    var trickyWords: [(word: String, mastery: Double)] {
        guard !attempts.isEmpty else { return [] }
        var misses: [String: Int] = [:]
        var hits: [String: Int] = [:]
        for attempt in attempts {
            for word in attempt.offWords { misses[word, default: 0] += 1 }
            for word in attempt.nailedWords { hits[word, default: 0] += 1 }
        }
        return misses
            .filter { $0.value >= 2 }
            .map { word, missCount in
                let hitCount = hits[word] ?? 0
                return (word, Double(hitCount) / Double(hitCount + missCount))
            }
            .sorted { $0.mastery < $1.mastery }
            .prefix(3)
            .map { $0 }
    }
}
