import SwiftUI

/// Floating overlay that shows recording status and transcription results.
///
/// Displayed as a non-activating NSPanel so the user's focus stays in whatever
/// app they're dictating into.
struct OverlayView: View {
    let status: TranscriptionStatus
    let transcription: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if status == .listening {
                listeningIndicator
            } else if status == .processing {
                processingIndicator
            } else if !transcription.isEmpty {
                transcriptionResult
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .frame(minWidth: 180, maxWidth: 320)
    }

    // MARK: - Subviews

    private var listeningIndicator: some View {
        HStack(spacing: 8) {
            PulsingDot(color: .red)
            Text("Listening…")
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(.primary)
        }
    }

    private var processingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Processing…")
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var transcriptionResult: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                Text("Copied to clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(transcription)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Pulsing Dot Animation

/// Animated dot that pulses to indicate active recording.
struct PulsingDot: View {
    let color: Color
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.7 : 1.0)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}
