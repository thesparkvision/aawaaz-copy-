import SwiftUI

@main
struct AawaazApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            Image(systemName: appState.menuBarIconName)
                .symbolRenderingMode(.monochrome)
                .onAppear {
                    if appState.showOnboarding {
                        openWindow(id: "onboarding")
                    }
                }
        }
        .menuBarExtraStyle(.window)

        Window("Welcome to Aawaaz", id: "onboarding") {
            OnboardingView()
                .environment(appState)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate()
                }
                .onDisappear {
                    NSApp.setActivationPolicy(.accessory)
                }
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
