import SwiftUI

/// Floating overlay that shows recording status and transcription results.
///
/// Displayed as a non-activating NSPanel so the user's focus stays in whatever
/// app they're dictating into. Uses `OverlayState` for reactive updates —
/// amplitude changes drive the waveform animation without recreating the view.
struct OverlayView: View {
    @Bindable var state: OverlayState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch state.status {
            case .listening:
                listeningIndicator
            case .processing:
                processingIndicator
            case .idle:
                if !state.transcription.isEmpty {
                    transcriptionResult
                }
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
        .animation(.easeInOut(duration: 0.25), value: state.status)
    }

    // MARK: - Subviews

    private var listeningIndicator: some View {
        HStack(spacing: 10) {
            AudioWaveformView(amplitude: state.amplitude)
                .frame(width: 28, height: 20)
            Text("Listening…")
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(.primary)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    private var processingIndicator: some View {
        HStack(spacing: 10) {
            ProcessingWaveformView()
                .frame(width: 28, height: 20)
            Text("Processing…")
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
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
            Text(state.transcription)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

// MARK: - Audio Waveform (Listening State)

/// Mini equaliser with 5 vertical bars that react to audio amplitude.
///
/// Each bar has a slightly different response curve and phase offset so the
/// visualisation feels organic rather than mechanical.
struct AudioWaveformView: View {
    var amplitude: Float

    /// Per-bar scale multipliers and minimum heights for visual variety.
    private static let barProfiles: [(scale: Float, minFraction: CGFloat)] = [
        (0.6, 0.15),
        (0.85, 0.12),
        (1.0, 0.10),
        (0.75, 0.13),
        (0.5, 0.15),
    ]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                let profile = Self.barProfiles[index]
                let barAmplitude = CGFloat(min(Float(amplitude) * profile.scale, 1.0))
                let fraction = max(barAmplitude, profile.minFraction)

                RoundedRectangle(cornerRadius: 1.5)
                    .fill(barGradient)
                    .frame(width: 3)
                    .scaleEffect(y: fraction, anchor: .center)
                    .animation(
                        .interpolatingSpring(stiffness: 300, damping: 15),
                        value: fraction
                    )
            }
        }
    }

    private var barGradient: LinearGradient {
        LinearGradient(
            colors: [.red.opacity(0.9), .orange.opacity(0.8)],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}

// MARK: - Processing Waveform (Processing State)

/// Animated shimmer bars that indicate transcription is in progress.
///
/// The bars pulse in a staggered wave pattern, giving a "thinking" feel
/// while keeping the same visual footprint as the listening waveform.
struct ProcessingWaveformView: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.secondary.opacity(0.6))
                    .frame(width: 3)
                    .scaleEffect(
                        y: isAnimating ? scaleFactor(for: index) : 0.2,
                        anchor: .center
                    )
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.1),
                        value: isAnimating
                    )
            }
        }
        .onAppear { isAnimating = true }
    }

    /// Staggered peak heights so the wave rolls across the bars.
    private func scaleFactor(for index: Int) -> CGFloat {
        let factors: [CGFloat] = [0.4, 0.65, 0.85, 0.65, 0.4]
        return factors[index]
    }
}
