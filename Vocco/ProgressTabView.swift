import SwiftUI
import Charts

struct ProgressTabView: View {
    @Environment(Store.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        Text("Progress")
                            .font(.vocco(30, .heavy))
                            .foregroundStyle(Brand.fg)
                        Spacer()
                        StreakPill(count: store.streak)
                    }
                    levelCard
                    streakCard
                    statsRow
                    accuracyCard
                    trickyCard
                }
                .padding(20)
            }
            .background(Brand.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Level

    private var levelCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Level \(store.level)")
                    .font(.vocco(24, .heavy))
                    .foregroundStyle(Brand.fg)
                Text("\(store.xp) XP total")
                    .font(.voccoMono(11))
                    .foregroundStyle(Brand.fg.opacity(0.62))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 7) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Brand.coral.opacity(0.15))
                        Capsule().fill(Brand.coral)
                            .frame(width: proxy.size.width * store.levelProgress)
                    }
                }
                .frame(width: 110, height: 8)
                Text("\(store.xpIntoLevel)/\(store.xpForNextLevel) XP · Lv \(store.level + 1)")
                    .font(.voccoMono(10))
                    .foregroundStyle(Brand.muted)
            }
        }
        .vCard(fill: Brand.lilac)
    }

    // MARK: Streak calendar

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Streak").font(.vocco(19, .heavy)).foregroundStyle(Brand.fg)
                SectionLabel("Last 8 weeks")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .top, spacing: 10) {
                ForEach(store.calendarDays, id: \.self) { week in
                    VStack(spacing: 6) {
                        ForEach(week) { day in
                            dayDot(day)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 14) {
                legendDot(Brand.amber, "Practiced")
                legendDot(Brand.fg.opacity(0.15), "Missed")
                HStack(spacing: 5) {
                    Circle().stroke(Brand.coral, lineWidth: 2).frame(width: 9, height: 9)
                    Text("Today").font(.voccoMono(10.5)).foregroundStyle(Brand.muted)
                }
                Spacer()
            }
        }
        .vCard()
    }

    private func dayDot(_ day: Store.CalendarDay) -> some View {
        Group {
            if day.isToday {
                Circle()
                    .stroke(Brand.coral, lineWidth: 2)
                    .frame(width: 11, height: 11)
                    .overlay {
                        if day.practiced {
                            Circle().fill(Brand.amber).frame(width: 5, height: 5)
                        }
                    }
            } else {
                Circle()
                    .fill(day.practiced ? Brand.amber : Brand.fg.opacity(0.10))
                    .frame(width: 9, height: 9)
            }
        }
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.voccoMono(10.5)).foregroundStyle(Brand.muted)
        }
    }

    // MARK: Stats

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatCard(value: "\(store.masteredKeys.count)", label: "Words mastered")
            StatCard(value: "\(store.bestStreak)", label: "Best streak")
            StatCard(value: "\(store.averageScore)%", label: "Avg accuracy")
        }
    }

    // MARK: Accuracy trend

    private var accuracyDelta: Int? {
        let weekly = store.weeklyAccuracy
        guard weekly.count >= 2, let first = weekly.first, let last = weekly.last else { return nil }
        let delta = Int(last.value - first.value)
        return delta > 0 ? delta : nil
    }

    private var accuracyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Accuracy").font(.vocco(19, .heavy)).foregroundStyle(Brand.fg)
                Spacer()
                if let delta = accuracyDelta {
                    HStack(spacing: 3) {
                        Image(systemName: "arrowtriangle.up.fill").font(.system(size: 8))
                        Text("+\(delta) in 8 weeks")
                    }
                    .font(.voccoMono(10, .semibold))
                    .foregroundStyle(Brand.tealInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Brand.teal.opacity(0.12)))
                }
            }
            Text("\(store.averageScore)%")
                .font(.vocco(34, .heavy))
                .foregroundStyle(Brand.fg)
            if store.weeklyAccuracy.count >= 2 {
                Chart(store.weeklyAccuracy) { point in
                    AreaMark(
                        x: .value("Week", point.label),
                        y: .value("Accuracy", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [Brand.teal.opacity(0.18), .clear],
                                                    startPoint: .top, endPoint: .bottom))
                    LineMark(
                        x: .value("Week", point.label),
                        y: .value("Accuracy", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Brand.teal)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { _ in
                        AxisGridLine().foregroundStyle(Brand.fg.opacity(0.06))
                        AxisValueLabel().font(.voccoMono(9)).foregroundStyle(Brand.muted)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: store.weeklyAccuracy.map(\.label)) { _ in
                        AxisValueLabel().font(.voccoMono(9)).foregroundStyle(Brand.muted)
                    }
                }
                .frame(height: 140)
            } else {
                Text("Practice a few phrases — your trend appears here.")
                    .font(.vocco(13.5))
                    .foregroundStyle(Brand.muted)
            }
        }
        .vCard()
    }

    // MARK: Tricky words

    private var trickyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Words to work on")
                .font(.vocco(19, .heavy))
                .foregroundStyle(Brand.fg)
            if store.trickyWords.isEmpty {
                Text("Words you miss twice will show up here with a mastery bar.")
                    .font(.vocco(13.5))
                    .foregroundStyle(Brand.muted)
            } else {
                ForEach(store.trickyWords, id: \.word) { item in
                    HStack(spacing: 12) {
                        Text(item.word)
                            .font(.voccoMono(14, .bold))
                            .foregroundStyle(Brand.fg)
                            .frame(width: 92, alignment: .leading)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Brand.fg.opacity(0.08))
                                Capsule()
                                    .fill(item.mastery > 0.5 ? Brand.teal : Brand.amber)
                                    .frame(width: proxy.size.width * item.mastery)
                            }
                        }
                        .frame(height: 6)
                        Text("\(Int(item.mastery * 100))%")
                            .font(.voccoMono(11))
                            .foregroundStyle(Brand.muted)
                            .frame(width: 36, alignment: .trailing)
                    }
                    .frame(height: 22)
                }
            }
        }
        .vCard()
    }
}

private struct StatCard: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.vocco(26, .heavy))
                .foregroundStyle(Brand.fg)
            SectionLabel(label)
        }
        .frame(maxWidth: .infinity)
        .vCard(padding: 16)
    }
}
