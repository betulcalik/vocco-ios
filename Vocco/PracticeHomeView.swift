import SwiftUI

struct PracticeHomeView: View {
    @Environment(Store.self) private var store
    @State private var path: [Deck] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 20) {
                    HStack(spacing: 8) {
                        Wordmark()
                        Spacer()
                        LevelPill(level: store.level)
                        StreakPill(count: store.streak)
                    }
                    TodayMixCard(deck: store.todayDeck,
                                 done: store.todayAttemptCount,
                                 goal: store.settings.dailyGoal)
                    if let resumeDeck = store.lastPracticedDeck {
                        ContinueCard(deck: resumeDeck,
                                     startIndex: store.nextPhraseIndex(in: resumeDeck))
                    }
                    if !store.bookmarks.isEmpty {
                        savedRow
                    }
                    HStack {
                        SectionLabel("Decks")
                        Spacer()
                        SectionLabel("\(store.masteredKeys.count) mastered")
                    }
                    deckGrid
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Brand.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                // Screenshot helper: `SIMCTL_CHILD_VOCCO_DECK=travel xcrun simctl launch …`
                if path.isEmpty, let deckId = ProcessInfo.processInfo.environment["VOCCO_DECK"],
                   let deck = Store.decks.first(where: { $0.id == deckId }) {
                    path = [deck]
                }
            }
        }
    }

    // MARK: Saved phrases entry

    private var savedRow: some View {
        NavigationLink {
            SavedPhrasesView()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Brand.coral)
                Text("Saved phrases")
                    .font(.vocco(15, .bold))
                    .foregroundStyle(Brand.fg)
                Spacer()
                Text("\(store.bookmarks.count)")
                    .font(.voccoMono(12))
                    .foregroundStyle(Brand.muted)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.muted)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white))
            .shadow(color: Brand.fg.opacity(0.07), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open saved phrases")
    }

    // MARK: Deck grid

    private var deckGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                  spacing: 12) {
            ForEach(Store.decks) { deck in
                NavigationLink(value: deck) {
                    DeckCard(deck: deck, mastered: store.masteredCount(in: deck))
                }
                .buttonStyle(.plain)
            }
        }
        .navigationDestination(for: Deck.self) { deck in
            PhrasePracticeView(deck: deck)
        }
    }
}

// MARK: - Today's Mix (coach surface — lilac)

struct TodayMixCard: View {
    let deck: Deck
    let done: Int
    let goal: Int

    var body: some View {
        NavigationLink(value: deck) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    SectionLabel("Today's Mix")
                    HStack(spacing: 8) {
                        Text(deck.emoji).font(.system(size: 24))
                        Text(deck.title)
                            .font(.vocco(21, .heavy))
                            .foregroundStyle(Brand.fg)
                    }
                    Text("\(done) of \(goal) phrases today")
                        .font(.voccoMono(12.5))
                        .foregroundStyle(Brand.fg.opacity(0.62))
                }
                Spacer(minLength: 12)
                ScoreRing(progress: goal > 0 ? Double(done) / Double(goal) : 0,
                          lineWidth: 7,
                          size: 62,
                          label: "\(min(done, goal))/\(goal)",
                          labelSize: 14)
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Brand.lilac))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Practice today's mix")
    }
}

// MARK: - Continue card

private struct ContinueCard: View {
    let deck: Deck
    let startIndex: Int

    var body: some View {
        NavigationLink {
            PhrasePracticeView(deck: deck, startIndex: startIndex)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    SectionLabel("Continue")
                    HStack(spacing: 6) {
                        Text(deck.emoji).font(.system(size: 17))
                        Text(deck.title)
                            .font(.vocco(16, .heavy))
                            .foregroundStyle(Brand.fg)
                    }
                    Text("Phrase \(startIndex + 1) of \(deck.phrases.count)")
                        .font(.voccoMono(11))
                        .foregroundStyle(Brand.muted)
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Brand.coral)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white))
            .shadow(color: Brand.fg.opacity(0.07), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Continue \(deck.title)")
    }
}

// MARK: - Deck card

struct DeckCard: View {
    let deck: Deck
    let mastered: Int

    private var ratio: Double {
        deck.phrases.isEmpty ? 0 : Double(mastered) / Double(deck.phrases.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(deck.emoji).font(.system(size: 28))
                Spacer()
                if ratio >= 1 {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Brand.teal)
                }
            }
            Text(deck.title)
                .font(.vocco(16, .bold))
                .foregroundStyle(Brand.fg)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text("\(mastered) of \(deck.phrases.count) phrases")
                .font(.voccoMono(10.5))
                .foregroundStyle(Brand.muted)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Brand.fg.opacity(0.08))
                    Capsule().fill(Brand.teal).frame(width: proxy.size.width * ratio)
                }
            }
            .frame(height: 6)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white))
        .shadow(color: Brand.fg.opacity(0.07), radius: 12, y: 5)
    }
}
