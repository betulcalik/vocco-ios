import SwiftUI

/// All bookmarked phrases, grouped by deck; tap to jump straight into practice.
struct SavedPhrasesView: View {
    @Environment(Store.self) private var store

    private var savedDeckSections: [(deck: Deck, indexes: [Int])] {
        Store.decks.compactMap { deck in
            let indexes = deck.phrases.indices.filter { store.bookmarks.contains("\(deck.id):\($0)") }
            return indexes.isEmpty ? nil : (deck, indexes)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if savedDeckSections.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 34))
                            .foregroundStyle(Brand.muted)
                        Text("Nothing saved yet")
                            .font(.vocco(17, .heavy))
                            .foregroundStyle(Brand.fg)
                        Text("Tap the bookmark icon while practicing a phrase — it lands here.")
                            .font(.vocco(13.5))
                            .foregroundStyle(Brand.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .padding(.horizontal, 24)
                } else {
                    ForEach(savedDeckSections, id: \.deck.id) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                Text(section.deck.emoji).font(.system(size: 15))
                                Text(section.deck.title)
                                    .font(.vocco(15, .heavy))
                                    .foregroundStyle(Brand.fg)
                            }
                            .padding(.horizontal, 4)
                            ForEach(section.indexes, id: \.self) { phraseIndex in
                                savedRow(section.deck, phraseIndex)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Brand.bg.ignoresSafeArea())
        .navigationTitle("Saved")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func savedRow(_ deck: Deck, _ phraseIndex: Int) -> some View {
        NavigationLink {
            PhrasePracticeView(deck: deck, startIndex: phraseIndex)
        } label: {
            HStack(spacing: 10) {
                Text(deck.phrases[phraseIndex].text)
                    .font(.vocco(14))
                    .foregroundStyle(Brand.fg)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.muted)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
            .shadow(color: Brand.fg.opacity(0.06), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(deck.phrases[phraseIndex].text)
    }
}
