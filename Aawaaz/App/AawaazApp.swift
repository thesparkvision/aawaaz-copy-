import SwiftUI

@main
struct AawaazApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    init() {
        // Schedule onboarding check after app is fully initialized
        let state = _appState.wrappedValue
        let delegate = _appDelegate.wrappedValue
        if state.showOnboarding {
            DispatchQueue.main.async {
                delegate.showOnboardingWindow(appState: state)
            }
        }
    }

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
