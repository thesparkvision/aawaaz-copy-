import SwiftUI

/// Shared observable state that drives the overlay's SwiftUI views.
///
/// `OverlayWindowController` mutates this on the main thread; `OverlayView`
/// observes it for reactive updates (amplitude, status changes, transcription text).
@Observable
final class OverlayState {
    var status: TranscriptionStatus = .idle
    var transcription: String = ""

    /// Current audio input amplitude, normalised to 0–1.
    /// Updated at ~30 Hz while `status == .listening`.
    var amplitude: Float = 0
}
