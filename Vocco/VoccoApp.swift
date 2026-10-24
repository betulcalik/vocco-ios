import SwiftUI

@main
struct VoccoApp: App {
    @State private var store = Store.load()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(store)
                .tint(Brand.coral)
        }
    }
}

struct RootTabView: View {
    @Environment(Store.self) private var store
    @State private var tab: Tab = RootTabView.initialTab()

    enum Tab: Hashable { case practice, progress, settings }

    /// Screenshot helper: `SIMCTL_CHILD_VOCCO_TAB=progress xcrun simctl launch …`
    static func initialTab() -> Tab {
        switch ProcessInfo.processInfo.environment["VOCCO_TAB"] {
        case "progress": return .progress
        case "settings": return .settings
        default: return .practice
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            PracticeHomeView()
                .tabItem { Label("Practice", systemImage: "mic.fill") }
                .tag(Tab.practice)
            ProgressTabView()
                .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
                .tag(Tab.progress)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .task {
            if store.settings.reminderOn {
                await store.syncReminder()
            }
        }
    }
}
