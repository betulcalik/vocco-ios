import SwiftUI

struct PracticeHomeView: View {
    @Environment(Store.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    HStack {
                        Wordmark()
                        Spacer()
                        StreakPill(count: store.streak)
                    }
                    TodayMixCard(deck: store.todayDeck,
                                 done: store.todayAttemptCount,
                                 goal: store.settings.dailyGoal)
                    HStack {
                        SectionLabel("Decks")
                        Spacer()
                    }
                    decksRow
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Brand.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var decksRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(Store.decks) { deck in
                    NavigationLink(value: deck) {
                        DeckCard(deck: deck, mastered: store.masteredCount(in: deck))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
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

// MARK: - Deck card

struct DeckCard: View {
    let deck: Deck
    let mastered: Int

    private var ratio: Double {
        deck.phrases.isEmpty ? 0 : Double(mastered) / Double(deck.phrases.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(deck.emoji).font(.system(size: 32))
            Text(deck.title)
                .font(.vocco(19, .bold))
                .foregroundStyle(Brand.fg)
            Text("\(mastered) of \(deck.phrases.count) phrases")
                .font(.voccoMono(11.5))
                .foregroundStyle(Brand.muted)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Brand.fg.opacity(0.08))
                    Capsule().fill(Brand.teal).frame(width: proxy.size.width * ratio)
                }
            }
            .frame(height: 6)
        }
        .padding(18)
        .frame(width: 236, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white))
        .shadow(color: Brand.fg.opacity(0.07), radius: 12, y: 5)
    }
}
