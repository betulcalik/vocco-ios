import Foundation

// MARK: - Content

struct Deck: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let emoji: String
    let phrases: [Phrase]
}

struct Phrase: Codable, Hashable {
    let text: String
    let ipa: String
    let translation: String
    let tip: String

    enum CodingKeys: String, CodingKey {
        case text = "t"
        case ipa
        case translation = "tr"
        case tip
    }
}

extension Bundle {
    static func loadDecks() -> [Deck] {
        guard let url = Bundle.main.url(forResource: "decks", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decks = try? JSONDecoder().decode([Deck].self, from: data) else { return [] }
        return decks
    }
}

// MARK: - Voices (ElevenLabs premade library IDs)

struct VoiceInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let desc: String

    static let all: [VoiceInfo] = [
        VoiceInfo(id: "EXAVITQu4vr4xnSDxMaL", name: "Aria",  desc: "warm · female"),
        VoiceInfo(id: "onwK4e9ZLuTAKqWW03F9", name: "Miles", desc: "deep · male"),
        VoiceInfo(id: "piTKgcLEGmPE4e6mEKli", name: "Priya", desc: "bright · female"),
        VoiceInfo(id: "29VdS4M9cTIaSanyjjIR", name: "Theo",  desc: "calm · male"),
    ]
}

// MARK: - Progress data

struct Attempt: Codable, Identifiable {
    var id = UUID()
    let deckId: String
    let phraseIdx: Int
    let score: Int
    let offWords: [String]
    let nailedWords: [String]
    let date: Date
}

struct Settings: Codable {
    var voiceId: String = VoiceInfo.all[0].id
    var dailyGoal: Int = 10
    var reminderOn: Bool = true
    var apiKey: String = ""   // shortcut: plain file storage; move to Keychain before App Store
}

struct Persisted: Codable {
    var settings = Settings()
    var attempts: [Attempt] = []
    var bookmarks: Set<String> = []
}

// MARK: - Scoring (local word alignment — no API tokens)

enum WordStatus { case nailed, off }

struct ScoredWord: Hashable, Identifiable {
    let word: String
    let status: WordStatus
    var id: String { word + "|" + (status == .nailed ? "n" : "o") }
}

struct ScoreResult {
    let score: Int
    let words: [ScoredWord]
    var nailedCount: Int { words.filter { $0.status == .nailed }.count }
    var offCount: Int { words.count - nailedCount }
    var offWords: [String] { words.filter { $0.status == .off }.map(\.word) }
    var nailedWords: [String] { words.filter { $0.status == .nailed }.map(\.word) }
}

enum Scorer {

    static func normalize(_ input: String) -> [String] {
        input.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .split { !$0.isLetter && !$0.isNumber && $0 != "'" }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// Needleman–Wunsch word alignment: equal=0, substitute=2, insert/delete=1.
    static func score(target: String, heard: String) -> ScoreResult {
        let targetWords = normalize(target)
        let heardWords = normalize(heard)
        let rowCount = targetWords.count
        let columnCount = heardWords.count
        guard rowCount > 0 else { return ScoreResult(score: 0, words: []) }

        var matrix = Array(repeating: Array(repeating: 0, count: columnCount + 1), count: rowCount + 1)
        for row in 0...rowCount { matrix[row][0] = row }
        for column in 0...columnCount { matrix[0][column] = column }
        for row in 1...rowCount {
            for column in 1...columnCount {
                let substitution = matrix[row - 1][column - 1]
                    + (targetWords[row - 1] == heardWords[column - 1] ? 0 : 2)
                matrix[row][column] = min(matrix[row - 1][column] + 1,
                                          matrix[row][column - 1] + 1,
                                          substitution)
            }
        }

        // Trace back from the corner, collecting target words in order.
        var scored: [ScoredWord] = []
        var row = rowCount
        var column = columnCount
        while row > 0 || column > 0 {
            if row > 0 && column > 0 {
                let substitutionCost = targetWords[row - 1] == heardWords[column - 1] ? 0 : 2
                if matrix[row][column] == matrix[row - 1][column - 1] + substitutionCost {
                    scored.append(ScoredWord(word: targetWords[row - 1],
                                             status: substitutionCost == 0 ? .nailed : .off))
                    row -= 1
                    column -= 1
                    continue
                }
            }
            if row > 0 && matrix[row][column] == matrix[row - 1][column] + 1 {
                scored.append(ScoredWord(word: targetWords[row - 1], status: .off))   // missing
                row -= 1
            } else if column > 0 {
                column -= 1                                                   // extra heard word: ignore
            } else {
                break
            }
        }

        let words = scored.reversed()
        let nailed = words.filter { $0.status == .nailed }.count
        let score = Int((Double(nailed) / Double(rowCount) * 100).rounded())
        return ScoreResult(score: score, words: Array(words))
    }
}
