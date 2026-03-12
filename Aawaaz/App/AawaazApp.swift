import SwiftUI

@main
struct AawaazApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            Label {
                Text("Aawaaz")
            } icon: {
                Image(systemName: appState.menuBarIconName)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
