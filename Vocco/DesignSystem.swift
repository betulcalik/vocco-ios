import SwiftUI

// MARK: - Brand tokens (from OpenDesign brand-spec.md)

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

enum Brand {
    static let bg = Color(hex: 0xFAF6EF)        // warm ivory
    static let fg = Color(hex: 0x1E2640)        // ink indigo
    static let muted = Color(hex: 0x1E2640).opacity(0.55)
    static let coral = Color(hex: 0xFF5C49)     // signature: speaking actions
    static let coralWarm = Color(hex: 0xFF8A5C)
    static let teal = Color(hex: 0x17B8A6)      // nailed
    static let tealInk = Color(hex: 0x0B7F73)
    static let amber = Color(hex: 0xFFB020)     // off-target
    static let amberInk = Color(hex: 0x9C6B00)
    static let lilac = Color(hex: 0xEFEBFF)     // coach surfaces
}

extension Font {
    static func vocco(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func voccoMono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Buttons

struct PillButtonStyle: ButtonStyle {
    var tint: Color = Brand.coral
    var prominent = true
    var expands = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.vocco(17, .bold))
            .foregroundStyle(prominent ? Color.white : Brand.fg)
            .padding(.horizontal, 20)
            .frame(minHeight: 52)
            .frame(maxWidth: expands ? .infinity : nil)
            .background {
                if prominent {
                    Capsule().fill(tint).shadow(color: tint.opacity(0.35), radius: 10, y: 4)
                } else {
                    Capsule().fill(Color.white).shadow(color: Brand.fg.opacity(0.06), radius: 8, y: 3)
                }
            }
            .overlay {
                if !prominent {
                    Capsule().strokeBorder(Brand.fg.opacity(0.10), lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var voccoPill: PillButtonStyle { .init() }
    static var voccoGhost: PillButtonStyle { .init(prominent: false) }
}

// MARK: - Cards & labels

struct CardModifier: ViewModifier {
    var fill: Color = .white
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(fill))
            .shadow(color: Brand.fg.opacity(0.07), radius: 12, y: 5)
    }
}

extension View {
    func vCard(fill: Color = .white, padding: CGFloat = 18) -> some View {
        modifier(CardModifier(fill: fill, padding: padding))
    }
}

struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.voccoMono(11, .semibold))
            .kerning(1.4)
            .foregroundStyle(Brand.muted)
    }
}

// MARK: - Score ring

struct ScoreRing: View {
    let progress: Double
    var lineWidth: CGFloat = 8
    var size: CGFloat = 64
    var label: String = ""
    var labelSize: CGFloat = 14
    var tint: Color = Brand.coral

    @State private var animated = false

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: animated ? progress : 0)
                .stroke(AngularGradient(colors: [tint, Brand.coralWarm], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if !label.isEmpty {
                Text(label)
                    .font(.vocco(labelSize, .heavy))
                    .foregroundStyle(Brand.fg)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            animated = false
            withAnimation(.easeOut(duration: 0.9)) { animated = true }
        }
    }
}

// MARK: - Wordmark (V + dotted o + cc + dotted o)

private struct DottedO: View {
    var body: some View {
        Circle()
            .stroke(Brand.fg, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, dash: [0.1, 5.2]))
            .frame(width: 14, height: 14)
            .alignmentGuide(.firstTextBaseline) { dimensions in dimensions[.bottom] - 4 }
    }
}

struct Wordmark: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("V").font(.vocco(24, .heavy))
            DottedO()
            Text("cc").font(.vocco(24, .heavy))
            DottedO()
        }
        .foregroundStyle(Brand.fg)
    }
}

struct StreakPill: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Brand.amber)
            Text("\(count)")
                .font(.vocco(15, .bold))
                .foregroundStyle(Brand.fg)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.white))
        .shadow(color: Brand.fg.opacity(0.08), radius: 8, y: 3)
    }
}

struct LevelPill: View {
    let level: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "star.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Brand.coral)
            Text("Lv \(level)")
                .font(.vocco(13, .bold))
                .foregroundStyle(Brand.fg)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.white))
        .shadow(color: Brand.fg.opacity(0.08), radius: 8, y: 3)
    }
}

// MARK: - Word chips

struct WordChip: View {
    let scored: ScoredWord

    var body: some View {
        Text(scored.word)
            .font(.vocco(15, .bold))
            .foregroundStyle(scored.status == .nailed ? Brand.tealInk : Brand.amberInk)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(scored.status == .nailed
                                       ? Brand.teal.opacity(0.14)
                                       : Brand.amber.opacity(0.18)))
    }
}

// MARK: - Flow layout (word chips wrap)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX > 0 && cursorX + size.width > maxWidth {
                cursorX = 0
                cursorY += rowHeight + spacing
                rowHeight = 0
            }
            cursorX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: cursorY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var cursorX = bounds.minX
        var cursorY = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX > bounds.minX && cursorX + size.width > bounds.maxX {
                cursorX = bounds.minX
                cursorY += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: cursorX, y: cursorY), anchor: .topLeading,
                          proposal: ProposedViewSize(size))
            cursorX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Pulse (recording rings)

struct Pulse: ViewModifier {
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pulsing ? 1.14 : 0.94)
            .opacity(pulsing ? 0.15 : 0.5)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}

extension View {
    func pulsing() -> some View { modifier(Pulse()) }
}
