import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status
            HStack {
                Circle()
                    .fill(appState.status.color)
                    .frame(width: 8, height: 8)
                Text(appState.status.rawValue)
                    .font(.headline)
                Spacer()
            }

            Divider()

            // Model
            HStack {
                Image(systemName: "cpu")
                    .foregroundStyle(.secondary)
                Text("Model:")
                    .foregroundStyle(.secondary)
                Text(appState.selectedModel.rawValue)
            }
            .font(.subheadline)

            // Language
            HStack {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                Text("Language:")
                    .foregroundStyle(.secondary)
                Text(appState.selectedLanguage.rawValue)
            }
            .font(.subheadline)

            // Last transcription preview
            if !appState.currentTranscription.isEmpty {
                Divider()
                Text(appState.currentTranscription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            // Pipeline error
            if let error = appState.pipelineError {
                Divider()
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Divider()

            // Listen / Stop
            Button {
                appState.toggleListening()
            } label: {
                if appState.pipeline.isListening {
                    Label("Stop Listening", systemImage: "stop.circle")
                } else {
                    Label("Start Listening", systemImage: "mic.circle")
                }
            }
            .disabled(appState.status == .processing)

            // Actions
            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Label("Settings…", systemImage: "gear")
            }
            .keyboardShortcut(",", modifiers: .command)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Aawaaz", systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding()
        .frame(width: 240)
    }
}
