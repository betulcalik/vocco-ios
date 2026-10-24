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
    @State private var tab: Tab = .practice

    enum Tab: Hashable { case practice, progress, settings }

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
