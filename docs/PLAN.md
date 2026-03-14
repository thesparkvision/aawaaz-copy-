# Aawaaz - Implementation Plan

## Tech Stack

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| Language | Swift | Native macOS, required for Accessibility API, AVAudioEngine, system integration. No bridging layers |
| UI Framework | SwiftUI + minimal AppKit | SwiftUI for all views (beginner-friendly, declarative). AppKit only for AXUIElement, CGEvent, NSEvent global monitors |
| Transcription | [whisper.cpp](https://github.com/ggml-org/whisper.cpp) | Best Apple Silicon optimization (Metal, CoreML, NEON). Consumed via precompiled XCFramework. GGML quantized models |
| VAD | [Silero VAD](https://github.com/snakers4/silero-vad) | Industry standard, ~2MB, language-agnostic. Run via ONNX Runtime Swift package or CoreML conversion |
| Audio | AVAudioEngine | Apple's native audio graph. ~5ms latency, 16kHz mono tap for transcription |
| Local LLM | [llama.cpp](https://github.com/ggerganov/llama.cpp) | Same ecosystem as whisper.cpp (same author, same model format, same patterns). Swift bindings available |
| Remote LLM | URLSession + Codable | Simple HTTP client for Claude/OpenAI API. No SDK dependency needed |
| Dictionary Store | SQLite (via swift-sqlite) or JSON file | Personal dictionary, productivity stats, snippet storage. SQLite preferred for queryability |
| Contacts | CNContactStore (Contacts framework) | Bulk-import first+last names for word boosting. Read-only, no write |
| Build | Xcode + Swift Package Manager | SPM for dependencies. whisper.cpp via precompiled XCFramework (v1.8.3), llama.cpp and ONNX Runtime via SPM |
| Min deployment | macOS 14 (Sonoma) | Ensures modern SwiftUI features, Metal 3, good AVAudioEngine APIs |

### Transcription Engine Landscape (Evaluated Alternatives)

whisper.cpp remains the best choice for Aawaaz. Below are alternatives evaluated and why they were not selected:

| Engine | Pros | Cons | Verdict |
|--------|------|------|---------|
| **whisper.cpp** (current) | Native C/Swift, Metal GPU, GGML models, huge community, proven XCFramework integration | Not the absolute fastest | **Keep** — best integration story for native macOS app |
| **Moonshine** | Smaller models (~26-61MB), compute scales with input length, GGML support | Non-commercial license, weaker multilingual/Hinglish, newer/less proven | **Watch** — revisit if license changes; could be a "fast mode" option later |
| **Faster-Whisper** | 4x faster than OpenAI Whisper, CTranslate2 backend | Python-based (CTranslate2), embedding Python in Swift app is complex | **Skip** — Python embedding defeats our native approach |
| **Parakeet TDT** | Ultra-low latency streaming (RTFx 3386), excellent for live captioning | NVIDIA-focused, Python/NeMo ecosystem, no native Swift path | **Skip** — wrong ecosystem for macOS-native app |
| **Sherpa-ONNX** | Streaming ASR + VAD + diarization, C API available | More complex integration, less proven for Hinglish | **Consider Phase 5** — potential unified ASR+VAD replacement |

### Local LLM Model Landscape (for Post-Processing)

The LLM landscape has shifted significantly toward ultra-small models that are ideal for text cleanup tasks. Updated recommendations:

| Model | Size (Q4_K_M) | RAM | Speed (M2+) | Cleanup Quality | Recommended For |
|-------|---------------|-----|-------------|----------------|-----------------|
| **Qwen 3 0.6B** | ~0.4 GB | ~1 GB | <0.5s | Good | **Default — ultra-fast, minimal footprint** |
| Qwen 3.5 0.8B | ~0.5 GB | ~1.2 GB | <0.5s | High | Better quality, still tiny |
| Gemma 3 1B | ~0.7 GB | ~1.5 GB | ~0.5s | High | Strong grammar/spelling cleanup |
| Llama 3.2 3B | ~1.8 GB | ~2.5 GB | ~1-2s | Very High | Balanced quality/speed |
| Phi-4-mini 3.8B | ~2.2 GB | ~3 GB | ~1-2s | Very High | Complex rephrasing, formal writing |

**Recommendation**: Default to **Qwen 3 0.6B (Q4_K_M)** — at ~0.4 GB it can coexist with any Whisper model even on 8GB machines, and sub-500ms inference makes post-processing nearly imperceptible. Offer Qwen 3.5 0.8B and Gemma 3 1B as quality upgrades. Keep Phi-4-mini/Llama 3.2 3B as "full quality" options for users with 16GB+ RAM.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    AawaazApp                        │
│                  (SwiftUI Entry)                    │
├──────────┬──────────┬──────────┬────────────────────┤
│ MenuBar  │ Overlay  │ Settings │   Onboarding       │
│  View    │  View    │  View    │     View            │
├──────────┴──────────┴──────────┴────────────────────┤
│                   AppState                          │
│            (ObservableObject)                       │
├─────────────────────────────────────────────────────┤
│              TranscriptionPipeline                  │
│    ┌───────────┐  ┌──────────┐  ┌───────────────┐  │
│    │  Audio    │→ │   VAD    │→ │   Whisper     │  │
│    │ Capture   │  │ Processor│  │   Manager     │  │
│    └───────────┘  └──────────┘  └───────┬───────┘  │
│                                         │          │
│                                         ▼          │
│                               ┌───────────────┐   │
│                               │ Post-Processor│   │
│                               │ (LLM optional)│   │
│                               └───────┬───────┘   │
│                                       │           │
│                                       ▼           │
│                              ┌────────────────┐   │
│                              │ Text Insertion │   │
│                              │  (AX / CGEvent)│   │
│                              └────────────────┘   │
├─────────────────────────────────────────────────────┤
│  HotkeyManager  │  ModelManager  │ PermissionsGuide│
└─────────────────────────────────────────────────────┘
```

### Key Design Principles

1. **Pipeline pattern**: Audio → VAD → Whisper → LLM → Insertion. Each stage is an independent, testable component.
2. **Observable state**: Single `AppState` object drives all UI reactively via SwiftUI's `@Observable` macro.
3. **Lazy loading**: Models are loaded only when needed, can be unloaded to free RAM.
4. **Async/await**: All heavy work (inference, model loading) runs on background tasks using Swift concurrency. UI never blocks.
5. **Protocol-oriented**: Key components (transcription engine, text inserter, LLM processor) are protocol-defined so implementations can be swapped.

### Implementation Guidance

- Treat concrete APIs named in this document as strong starting points, not irrevocable decisions. When implementation begins, verify them against the actual UX and compatibility requirements before locking them in.
- For system integration work (hotkeys, Accessibility insertion, event synthesis), prefer a short spike and test matrix over assuming the first plausible API will generalize across macOS apps.
- Benchmark early on target Apple Silicon hardware. If measured latency misses the UX bar, reprioritize the implementation plan rather than preserving phase order for its own sake.
- Choose one canonical runtime storage location for downloaded models and keep code, docs, onboarding, and local development conventions aligned around it.

## Project Structure

```
aawaaz/
├── docs/
│   ├── SPEC.md
│   └── PLAN.md
├── Aawaaz/
│   ├── Aawaaz.xcodeproj
│   ├── Package.swift                    # Local SPM package: whisper.cpp XCFramework binary target + other deps
│   ├── App/
│   │   ├── AawaazApp.swift              # @main, MenuBarExtra, app lifecycle
│   │   ├── AppState.swift               # @Observable central state
│   │   └── AppDelegate.swift            # NSApplicationDelegate for AppKit-level setup
│   ├── Views/
│   │   ├── MenuBarView.swift            # MenuBarExtra popover content
│   │   ├── OverlayView.swift            # Floating NSPanel with transcription text
│   │   ├── OverlayWindowController.swift # NSPanel creation and positioning
│   │   ├── SettingsView.swift           # Preferences window (tabbed)
│   │   ├── OnboardingView.swift         # First-launch permission guide
│   │   ├── ModelDownloadView.swift      # Model browser and download progress
│   │   ├── DictionarySettingsView.swift # Personal dictionary management UI (Phase 3.5)
│   │   ├── SnippetSettingsView.swift    # Voice snippets management UI (Phase 3.5)
│   │   ├── AppOverridesView.swift       # Per-app insertion method & category overrides (Phase 3.5/5)
│   │   └── StatsView.swift             # Productivity stats card for menu bar popover (Phase 5)
│   ├── Audio/
│   │   ├── AudioCaptureManager.swift    # AVAudioEngine setup, mic tap, 16kHz PCM buffer
│   │   ├── AudioDevice.swift            # Enumerate and select input devices
│   │   └── MediaController.swift        # Auto-pause/resume media playback (Phase 5)
│   ├── VAD/
│   │   ├── VADProcessor.swift           # Silero VAD wrapper, speech boundary detection
│   │   └── VADState.swift               # Speech start/end state machine
│   ├── Transcription/
│   │   ├── TranscriptionPipeline.swift  # Orchestrates VAD → Whisper → TextProcessing → LLM → Insertion
│   │   ├── WhisperManager.swift         # whisper.cpp Swift wrapper, model load/unload, inference
│   │   ├── WhisperConfiguration.swift   # Model params, language, beam size, etc.
│   │   └── TranscriptionResult.swift    # Structured result (text, language, confidence, timestamps)
│   ├── TextProcessing/                  # NEW — Pre-LLM text processing (Phase 3)
│   │   ├── TextProcessor.swift          # Orchestrates pre-LLM text cleaning pipeline
│   │   ├── FillerWordRemover.swift      # Regex-based filler word removal with word boundaries
│   │   ├── SelfCorrectionDetector.swift # Detects "actually no X" / "I mean X" patterns
│   │   └── SnippetExpander.swift        # Voice shortcut trigger → expansion replacement (Phase 3.5)
│   ├── PostProcessing/
│   │   ├── PostProcessor.swift          # Protocol: process(rawText, context) → cleanedText
│   │   ├── LocalLLMProcessor.swift      # llama.cpp-based cleanup
│   │   ├── RemoteLLMProcessor.swift     # Claude/OpenAI API cleanup
│   │   └── NoOpProcessor.swift          # Pass-through when disabled
│   ├── TextInsertion/
│   │   ├── TextInsertionManager.swift   # Orchestrator: try AX → fallback CGEvent → fallback clipboard
│   │   ├── AccessibilityManager.swift   # AXUIElement: find focused element, insert text
│   │   ├── KeystrokeSimulator.swift     # CGEventPost: simulate typing/paste
│   │   ├── InsertionContext.swift       # Context: app name, bundle ID, field type, appCategory
│   │   ├── ClipboardManager.swift       # NSPasteboard: copy and paste
│   │   └── InsertionHistory.swift       # Ring buffer of last N insertions for undo (Phase 4)
│   ├── Hotkey/
│   │   ├── HotkeyManager.swift          # Register/unregister global shortcuts
│   │   └── HotkeyConfiguration.swift    # Key + modifiers + mode (hold/toggle)
│   ├── Dictionary/                      # NEW — Personal dictionary & word boosting (Phase 3.5)
│   │   ├── DictionaryStore.swift        # SQLite/JSON store for custom words, corrections, contact names
│   │   ├── DictionaryEntry.swift        # Data model: correctSpelling, misspellings[], source, etc.
│   │   ├── AutoLearnManager.swift       # Detect user corrections post-insertion, suggest additions
│   │   ├── ContactsImporter.swift       # CNContactStore bulk import of first+last names
│   │   └── WordBooster.swift            # Build initial_prompt from dictionary for whisper.cpp
│   ├── Models/
│   │   ├── ModelManager.swift           # Download, verify, cache GGML models
│   │   ├── ModelCatalog.swift           # Available models with metadata (size, speed, languages)
│   │   ├── ModelDownloader.swift        # URLSession download with progress
│   │   └── ModelUpdateChecker.swift     # Check remote manifest for newer model versions (Phase 5)
│   ├── Stats/                           # NEW — Productivity tracking (Phase 5)
│   │   ├── StatsTracker.swift           # Track words, duration, WPM per session
│   │   └── StatsStore.swift             # SQLite persistence for cumulative stats
│   ├── Permissions/
│   │   └── PermissionsManager.swift     # Check/request microphone, accessibility permissions
│   └── SoundEffects/                    # NEW — Audio feedback (Phase 5)
│       ├── SoundEffectManager.swift     # Play start/stop/success/error sounds
│       └── Sounds/                      # Bundled .caf or .aiff audio files
│           ├── start_recording.caf
│           ├── stop_recording.caf
│           ├── text_inserted.caf
│           └── error.caf
├── Resources/
│   ├── Assets.xcassets                  # App icon, menu bar icon
│   └── silero_vad.onnx                  # Silero VAD model (or .mlmodel if CoreML converted)
├── Models/                              # Optional local dev fixtures only; runtime app models should live in Application Support
├── Tests/
│   ├── VADProcessorTests.swift
│   ├── WhisperManagerTests.swift
│   ├── TextInsertionTests.swift
│   ├── TranscriptionPipelineTests.swift
│   ├── FillerWordRemoverTests.swift     # NEW
│   ├── SelfCorrectionDetectorTests.swift # NEW
│   ├── SnippetExpanderTests.swift       # NEW
│   ├── DictionaryStoreTests.swift       # NEW
│   ├── WordBoosterTests.swift           # NEW
│   └── StatsTrackerTests.swift          # NEW
└── .gitignore
```

### Runtime Data Layout

```
~/Library/Application Support/Aawaaz/
├── Models/                              # Downloaded Whisper + LLM GGUF models
│   ├── ggml-large-v3-turbo-q5_0.bin
│   └── qwen3-0.6b-q4_k_m.gguf
├── Dictionary/
│   ├── dictionary.sqlite               # Personal dictionary (or dictionary.json)
│   └── contacts_cache.json             # Cached contact names for word boosting
├── Snippets/
│   └── snippets.json                   # Voice shortcut trigger → expansion pairs
├── Stats/
│   └── stats.sqlite                    # Productivity tracking data
└── Sounds/                             # (optional) User-supplied custom sounds
```

## Implementation Phases

---

### Phase 1: Foundation + Local Transcription MVP

**Goal**: Menu bar app → press hotkey → speak → see transcription in overlay → copied to clipboard.

**No AX API text insertion yet.** The user manually pastes. This lets us validate the transcription quality and UX before tackling the hardest system integration.

#### Step 1.1: Project Setup

- [x] Create Xcode project (macOS App, SwiftUI lifecycle)
- [x] Configure as menu bar app (LSUIElement in Info.plist)
- [x] Add whisper.cpp as XCFramework binary dependency (v1.8.3, via local SPM package)
- [x] Add ONNX Runtime Swift package (for Silero VAD)
- [x] Set up code signing with microphone entitlement
- [x] Set up .gitignore (Models/, .build/, etc.)

#### Step 1.2: Menu Bar + Basic UI

- [x] `AawaazApp.swift` — MenuBarExtra with a simple popover
- [x] `MenuBarView.swift` — Status indicator (idle/listening/processing), model name, quit button
- [x] `AppState.swift` — Observable state: status enum, current transcription text, selected model
- [x] Menu bar icon (microphone SF Symbol for now)

#### Step 1.3: Audio Capture

- [x] `AudioCaptureManager.swift` — AVAudioEngine with installTap on input node
- [x] Configure: 16kHz sample rate, mono, Float32 PCM format
- [x] Provide audio buffer callback (deliver `[Float]` samples)
- [x] Handle audio session setup and microphone permission request
- [x] `AudioDevice.swift` — List available input devices, handle device changes

#### Step 1.4: Voice Activity Detection

- [x] Bundle Silero VAD ONNX model in app resources
- [x] `VADProcessor.swift` — Load model, run inference on 30ms audio frames
- [x] `VADState.swift` — State machine: idle → speech_started → speech_ongoing → speech_ended
- [x] Configure speech padding (300ms default) and minimum speech duration (250ms)
- [x] Output: emits buffered audio segments when speech ends

#### Step 1.5: Whisper Integration

- [x] Confirm the canonical model storage path and keep all code/docs consistent with it (prefer `~/Library/Application Support/Aawaaz/Models/` for runtime downloads; use repo-local `Models/` only for development fixtures if intentionally needed)
- [x] `ModelManager.swift` — Check for models in ~/Library/Application Support/Aawaaz/Models/
- [x] `ModelCatalog.swift` — Hardcoded catalog of available models with download URLs (Hugging Face GGML repos)
- [x] `ModelDownloadView.swift` — Download model with progress bar (URLSession download task)
- [x] `WhisperManager.swift` — Load GGML model, run inference on audio buffer, return text
- [x] Configure: Metal acceleration enabled, no language forced (auto-detect), beam size 5
- [x] Handle model loading/unloading lifecycle

#### Step 1.6: Transcription Pipeline

- [x] `TranscriptionPipeline.swift` — Wire: AudioCapture → VAD → Whisper → output
- [x] On speech end: send audio buffer to WhisperManager, receive text
- [x] Publish transcription result to AppState
- [x] Copy result to clipboard automatically (NSPasteboard)
- [ ] Benchmark end-to-end latency on representative short and medium utterances; if VAD-segmented final inference does not meet the UX bar, pull interim/streaming work forward instead of deferring it to a later polish phase

#### Step 1.7: Overlay Window

- [x] `OverlayWindowController.swift` — NSPanel, floating, always-on-top, non-activating
- [x] `OverlayView.swift` — SwiftUI view showing: recording indicator (when listening), transcription text (when processing/done)
- [x] Position: near mouse cursor or near focused window
- [x] Auto-dismiss after a few seconds, or on next hotkey press
- [x] Animate: fade in/out, subtle slide

#### Step 1.8: Global Hotkey

- [x] Evaluate candidate hotkey mechanisms (`RegisterEventHotKey`, event taps, `NSEvent` monitors, or other native options) against system-wide reliability, modifier-only support, hold/release detection, permission behavior, and conflict rate
- [x] `HotkeyManager.swift` — Implement the most reliable validated option; do not assume `NSEvent` monitors are sufficient until tested
- [x] Choose the default shortcut only after testing conflict rate and ergonomics; do not assume a modifier-only shortcut (for example right Option) is viable across target apps
- [x] Hold mode: key down → start listening, key up → stop and process
- [x] Toggle mode: key down → toggle listening state
- [x] `HotkeyConfiguration.swift` — Persist chosen key + mode in UserDefaults

#### Step 1.9: Settings

- [x] `SettingsView.swift` — SwiftUI Settings scene
- [x] Tabs: General (hotkey, activation mode), Models (select/download), Audio (input device)
- [x] Language mode selector: Auto / English / Hindi
- [x] Latency preset: Fast (small model, short chunks) / Balanced (turbo) / Quality (large-v3)

#### Step 1.10: First Launch & Permissions

- [x] `PermissionsManager.swift` — Check microphone permission status
- [x] `OnboardingView.swift` — Welcome screen, request microphone permission, guide to download first model
- [x] Show permission status indicators

**Phase 1 deliverable**: A working menu bar app that listens on hotkey, transcribes via Whisper, shows result in an overlay, and copies to clipboard. User pastes manually.

---

### Phase 2: System-Wide Text Insertion

**Goal**: Transcribed text is directly inserted into the focused text field of any application.

#### Step 2.1: Permissions & Onboarding

- [x] Add Accessibility description to Info.plist
- [x] `PermissionsManager.swift` — Check `AXIsProcessTrusted()`, guide user to enable
- [x] Update `OnboardingView` to include an explicit Accessibility permission step with screenshot/instructions
- [x] Align onboarding copy and checks so the UI consistently refers to Accessibility vs. Input Monitoring where appropriate; do not claim one permission while validating another
- [x] Gate onboarding completion on the permissions Phase 2 actually depends on instead of allowing "Get Started" to bypass them permanently
- [x] Show persistent warning in menu bar if Accessibility is not granted

#### Step 2.2: Input & Activation Reliability

- [x] `AudioCaptureManager.swift` — Wire the selected input device UID from settings into the actual `AVAudioEngine` capture path instead of always using the system default input
- [x] `HotkeyManager.swift` — Replace the observer-only hotkey implementation with a suppressible mechanism (`RegisterEventHotKey`, event tap, or other validated approach) so the activation shortcut does not leak through to the frontmost app
- [x] Re-test hold and toggle activation after the hotkey change, including conflicts with common text-entry apps

#### Step 2.3: AX API Text Insertion

- [x] Build a compatibility matrix across representative targets: AppKit text fields, AppKit text views, SwiftUI text inputs, Electron apps, browsers/contenteditable, Terminal/code editors
- [x] Evaluate insertion strategies before locking one in: direct AX value mutation, selected-text replacement, keystroke simulation, paste-based fallback
- [x] `AccessibilityManager.swift`:
  - [x] Get frontmost app PID via `NSWorkspace.shared.frontmostApplication`
  - [x] Create AX element: `AXUIElementCreateApplication(pid)`
  - [x] Get focused element: query `kAXFocusedUIElementAttribute`
  - [x] Verify the focused element is actually editable/settable; do not assume `AXTextField`/`AXTextArea` coverage is sufficient for all supported apps
  - [x] Get current value and selection range where available
  - [x] Prefer the least-destructive insertion strategy that works for the current app/element; do not assume whole-value `kAXValueAttribute` replacement is universally correct
  - [x] Update cursor position to end of inserted text

#### Step 2.4: Fallback: Keystroke Simulation

- [x] `KeystrokeSimulator.swift`:
  - [x] Save current clipboard contents
  - [x] Copy transcription to clipboard
  - [x] Simulate Cmd+V via `CGEventPost`
  - [x] Restore original clipboard contents
  - [x] Add small delay between clipboard set and paste simulation (~50ms)

#### Step 2.5: Insertion Orchestration

- [x] `TextInsertionManager.swift`:
  - [x] Try AX API insertion first
  - [x] If AX API fails (element not found, not a text field, permission denied), fall back to keystroke simulation
  - [x] If keystroke simulation fails, fall back to clipboard-only with notification
  - [x] Log which method was used (for debugging)

#### Step 2.6: Context Detection

- [x] Detect the frontmost application name and bundle identifier
- [x] Detect the type of text field (single-line input, multi-line text area, code editor)
- [x] Pass this context to post-processing (Phase 3) for context-aware formatting
- [x] Store per-app preferences (e.g., always use keystroke simulation for app X)

#### Step 2.7: Settings & Verification

- [x] `SettingsView.swift` — Add a real shortcut recorder UI for editing `HotkeyConfiguration.keyCode` and `modifierFlags`, not just displaying the current shortcut
- [x] Add an automated test target to the Xcode project
- [x] Cover core Phase 1/2 integration risks with tests: VAD state transitions, Whisper integration seams, transcription pipeline orchestration, selected-model/device persistence, overlay teardown, and hold/toggle hotkey state management

**Phase 2 deliverable**: Transcription is automatically typed into whatever text field is focused, in any app.

---

### Phase 2.5: Activation & Feedback Refinements

**Goal**: Improve the default activation shortcut, make hold-to-talk the canonical default, and upgrade the listening/processing indicator to feel more alive.

#### Step 2.5.1: Default Hotkey Change

- [x] Change the default hotkey from Cmd+Shift+Space to **Fn** (Globe key) or **Right Ctrl** as primary candidates
  - [x] Evaluate Fn/Globe key: on Apple Silicon Macs this is the dictation key by default — test whether we can capture it reliably via event tap without conflicting with macOS Dictation (user may need to disable system dictation first). Document this trade-off
  - [x] Evaluate Right Ctrl: rarely used, no system conflicts, works well with event taps. Ergonomically accessible
  - [ ] Test both candidates across Safari, VS Code, Slack, Terminal, Notes — ensure no key leakage to the frontmost app
  - [x] Whichever wins, update `HotkeyConfiguration` default in code and onboarding copy
  - [x] Keep Cmd+Shift+Space as a documented alternative
  - [x] Existing users who already have a saved hotkey should not be affected (only changes the default for new installs)
- [x] Set **hold-to-talk** as the default activation mode (change `HotkeyMode` default from whatever it is now to `.hold`)
  - [x] Update onboarding to emphasise hold-to-talk: "Hold [key] to dictate, release to insert"
  - [x] Toggle mode remains available in Settings for longer dictation

#### Step 2.5.2: Listening & Processing Indicator Overhaul

- [x] Replace the current simple overlay indicator with a richer **voice bubble / waveform** visualization:
  - [x] **Listening state**: Show an animated waveform or speech bubble that reacts to audio input amplitude in real-time
    - [x] Feed RMS amplitude from `AudioCaptureManager` to the overlay (add a lightweight amplitude callback alongside the sample callback)
    - [x] SwiftUI animation: 3-5 vertical bars that scale with amplitude (like a mini equalizer), or a pulsing circular waveform ring
    - [x] The animation should feel organic and responsive — the user should see movement as they speak
  - [x] **Processing state**: Morph the waveform into a subtle processing animation (e.g., the bars compress into a rotating ring, or the bubble shows a shimmer/thinking pattern)
  - [x] **Result state**: Smooth transition to showing the transcribed text
- [x] Design options to explore (implementer should prototype 2-3 and pick the best feel):
  - [x] Option A: **Floating pill** — small rounded capsule near cursor with animated bars inside *(selected)*
  - [ ] Option B: **Voice bubble** — speech-bubble shape with waveform inside, tail pointing at the cursor/text field
  - [ ] Option C: **Minimal ring** — circular indicator near menu bar icon that pulses with speech amplitude
- [x] Update `OverlayView.swift` and `OverlayWindowController.swift` with the new visualization
- [x] Keep the overlay small and unobtrusive — it should not cover the text field being dictated into

#### Step 2.5.3: Fix Hindi-to-English Translation in Hinglish Mode

> **Bug**: When speaking Hinglish (Hindi mixed with English), Whisper sometimes *translates* Hindi words to English instead of transcribing them. For example, saying "mujhe ek meeting schedule karni hai" may output "I need to schedule a meeting" instead of preserving the Hindi words. This happens because: (1) `params.translate` is not explicitly set to `false`, and (2) Hinglish mode uses `language = nil` (auto-detect), which lets Whisper flip unpredictably between transcription and translation.

**Immediate fixes** (apply to `WhisperManager.swift`):

- [x] Explicitly set `params.translate = false` in `transcribe()` to force transcription mode (never translate)
- [x] For `.hinglish` language mode, change from `language = nil` to `language = "hi"` — this tells Whisper to expect Hindi, and it will naturally pick up English words embedded in Hindi speech without translating them. Auto-detect (`nil`) is unreliable for code-switching
- [x] For `.auto` mode, keep `language = nil` but still set `translate = false`

**initial_prompt biasing** (improves Hinglish output quality):

- [x] When language mode is `.hinglish`, set `params.initial_prompt` to a Romanized Hindi-English sample:
  ```
  "Yeh ek Hinglish example hai. Meeting schedule karna hai, please email bhej do."
  ```
  This primes Whisper to output code-switched text in the user's expected script (Roman/Latin for Hindi words mixed with English) instead of Devanagari or full translation
- [x] Add a user preference for Hinglish script output:
  - **Romanized** (default): "mujhe meeting schedule karni hai" — initial_prompt uses Roman script samples
  - **Devanagari**: "मुझे meeting schedule करनी है" — initial_prompt uses Devanagari samples
  - **Mixed**: Let Whisper decide per word — no script bias in prompt
- [x] Store preference in UserDefaults, add to Language section in Settings

**How WisprFlow handles this** (for reference — our approach parallels theirs):
- They use **custom fine-tuned Hinglish models** (we plan IndicWhisper in Phase 5)
- **Session-level language priority** — user sets 2-3 languages (we have language mode selector)
- **LLM post-processing** normalizes script inconsistencies (our Phase 3)
- **Learns from corrections** over time (our auto-learn in Phase 3.5)

**Long-term** (Phase 5): Evaluate fine-tuned models like [Whisper-Hindi2Hinglish](https://huggingface.co/Oriserve/Whisper-Hindi2Hinglish-Prime) converted to GGML, and IndicWhisper from AI4Bharat

---

### Phase 3: Text Processing & LLM Post-Processing

**Goal**: Clean up transcription before insertion — first with fast, deterministic text processing (filler words, self-corrections), then optionally with LLM for grammar and formatting. **Text is only inserted after all processing is complete** — the user sees the final, cleaned result.

#### Step 3.0: Pipeline Rearchitecture — Process-Then-Insert

> **Key design change**: Today the pipeline transcribes and inserts text in real-time as speech segments complete. With post-processing (text cleanup, LLM, dictionary correction, snippets), **insertion must be deferred until all processing stages have run**. The user should never see unprocessed text inserted and then corrected in-place — that would feel janky and cause editing conflicts.

- [x] Rearchitect `TranscriptionPipeline` to separate transcription from insertion:
  - [x] **During hold**: Continue transcribing speech segments via VAD → Whisper as today, accumulating raw text in memory. Show interim results in the overlay (raw transcription) so the user gets feedback that their speech is being captured.
  - [x] **On release (or toggle-off)**: Run the full post-processing chain on the accumulated text, then insert the final cleaned result.
  - [x] Post-processing chain order: Raw Whisper text → Dictionary correction → Filler word removal → Self-correction detection → Snippet expansion → LLM cleanup (if enabled) → Insert into app
- [x] Explore optimistic/pipelined approaches for lower latency:
  - [x] **Approach A — Process at end**: Simplest. Accumulate all raw segments, run full chain on release. Latency = processing time after release. Good baseline.
  - [ ] **Approach B — Incremental processing**: Run lightweight stages (filler removal, dictionary correction) on each segment as it completes. Defer only LLM to the end. Reduces perceived latency since LLM only needs to process pre-cleaned text.
  - [ ] **Approach C — Speculative LLM**: Start LLM processing on accumulated text periodically (e.g., every 5s of speech). On release, only re-process the delta. More complex but lowest latency for long dictation.
  - [x] **Recommendation**: Start with Approach A for correctness, benchmark, then move to B if latency is noticeable. C is only needed for very long dictation sessions.
- [x] Update overlay behavior:
  - [x] While speaking (hold): show raw interim transcription with waveform/bubble indicator
  - [x] On release: briefly show "Processing..." while post-processing runs
  - [x] After processing: show final text and insert it
- [x] The implementer should explore and benchmark these approaches to find the best UX trade-off. The guiding principle is: **the user's focused text field should only ever receive the fully-processed final text, never intermediate results**.

#### Step 3.1: Pre-LLM Text Processing Pipeline

These steps run **after** Whisper and **before** LLM. They are fast, deterministic, and work even when LLM is disabled.

- [ ] `TextProcessing/TextProcessor.swift` — Orchestrator that runs all pre-LLM text cleaning steps in sequence:
  ```swift
  class TextProcessor {
      func process(_ rawText: String, config: TextProcessingConfig) -> String
  }
  ```
- [ ] `TextProcessing/FillerWordRemover.swift`:
  - [ ] Default word list: "um", "uh", "like", "you know", "basically", "so", "I mean", "right", "actually", "literally"
  - [ ] Regex-based removal with word-boundary awareness (`\b` anchors) to avoid false positives (e.g., "I like dogs" keeps "like")
  - [ ] Handle multi-word fillers ("you know", "I mean") as phrase patterns
  - [ ] Configurable: users can add/remove filler words in Settings
  - [ ] Clean up double spaces and leading/trailing whitespace after removal
  - [ ] Unit tests: `FillerWordRemoverTests.swift` — test boundary cases, multi-word fillers, no false positives on legitimate usage
- [ ] `TextProcessing/SelfCorrectionDetector.swift`:
  - [ ] Detect correction patterns: "actually no [X]", "I mean [X]", "wait [X]", "sorry [X]", "no no [X]", "let me rephrase [X]", "scratch that [X]"
  - [ ] Regex patterns: `\b(actually no|I mean|wait|sorry|no no|let me rephrase|scratch that)\b[,]?\s*` — keep only text after the marker
  - [ ] Handle multiple corrections in a single utterance (scan left-to-right, keep rightmost correction per sentence)
  - [ ] When LLM is enabled, can delegate to LLM prompt instead (add instruction: "If the speaker corrects themselves, keep only the correction")
  - [ ] Unit tests: `SelfCorrectionDetectorTests.swift` — test each pattern, multiple corrections, edge cases
- [ ] Wire `TextProcessor` into `TranscriptionPipeline.swift`:
  - [ ] After `whisperManager.transcribe()` returns, run `textProcessor.process(rawText)` before passing to PostProcessor
  - [ ] Add `TextProcessingConfig` to `AppState` with toggle for filler removal and self-correction detection
- [ ] Settings integration:
  - [ ] Add "Text Cleanup" section to General Settings tab
  - [ ] Toggle: "Remove filler words" (default: on)
  - [ ] Toggle: "Detect self-corrections" (default: on)
  - [ ] Editable filler word list (advanced, expandable section)

#### Step 3.2: Post-Processor Protocol

- [ ] `PostProcessor.swift` — Protocol:
  ```swift
  protocol PostProcessor {
      func process(rawText: String, context: InsertionContext) async throws -> String
  }
  ```
- [ ] `InsertionContext` extension: add `appCategory` enum (see Step 3.7 for tone/context matching)
- [ ] `NoOpProcessor.swift` — Pass-through implementation (when disabled)

#### Step 3.3: Local LLM Integration

- [ ] Add llama.cpp as Swift Package dependency
- [ ] `LLMModelCatalog.swift` — Catalog of available LLM models:
  | Model | GGUF File | Size (Q4_K_M) | RAM | Speed (M2+) | Quality |
  |-------|-----------|---------------|-----|-------------|---------|
  | **Qwen 3 0.6B** | qwen3-0.6b-q4_k_m.gguf | ~0.4 GB | ~1 GB | <0.5s | Good — **default** |
  | Qwen 3.5 0.8B | qwen3.5-0.8b-q4_k_m.gguf | ~0.5 GB | ~1.2 GB | <0.5s | High |
  | Gemma 3 1B | gemma-3-1b-q4_k_m.gguf | ~0.7 GB | ~1.5 GB | ~0.5s | High |
  | Llama 3.2 3B | llama-3.2-3b-q4_k_m.gguf | ~1.8 GB | ~2.5 GB | ~1-2s | Very High |
  | Phi-4-mini 3.8B | phi-4-mini-q4_k_m.gguf | ~2.2 GB | ~3 GB | ~1-2s | Very High |
- [ ] `LocalLLMProcessor.swift`:
  - [ ] Load GGUF model (default: Qwen 3 0.6B Q4_K_M — ~0.4 GB, coexists with Whisper even on 8GB machines)
  - [ ] Construct prompt: system instruction + context + raw text → cleaned text
  - [ ] Run inference with low temperature (0.1-0.2 for cleanup tasks)
  - [ ] Parse output, extract cleaned text
  - [ ] Model lazy-load and unload support
  - [ ] Smart memory management: on 8GB machines, recommend Qwen 3 0.6B; on 16GB+, allow larger models
  - [ ] Benchmark Qwen 3 0.6B vs Gemma 3 1B vs Llama 3.2 3B on representative cleanup tasks

#### Step 3.4: Remote LLM Integration

- [ ] `RemoteLLMProcessor.swift`:
  - [ ] Support Claude API (Haiku for speed, Sonnet for quality)
  - [ ] Support OpenAI API (GPT-4o-mini)
  - [ ] API key stored in Keychain (not UserDefaults)
  - [ ] Construct same prompt as local, send via URLSession
  - [ ] Handle errors gracefully (fall back to raw text if API fails)

#### Step 3.5: LLM Prompt Engineering

- [ ] System prompt template:
  ```
  Clean up this dictated text. The speaker was using [app_name] ([app_category]).
  - Fix grammar and punctuation
  - Keep the original meaning and tone
  - Format appropriately for [context]: [category_specific_instructions]
  - If the text mixes Hindi and English, preserve the code-switching naturally
  - If the speaker corrects themselves (e.g., "actually no", "I mean"), keep only the correction
  - Do not add information that wasn't spoken
  Output only the cleaned text, nothing else.
  ```
- [ ] Cleanup level presets (Light / Medium / Full) adjust the prompt:
  - Light: grammar and punctuation only
  - Medium: + sentence structure, capitalization
  - Full: + context-aware formatting, tone adjustment

#### Step 3.6: Settings Integration

- [ ] Add Post-Processing tab to Settings
- [ ] Toggle: Off / Local / Remote
- [ ] Model selection (for local) — show size/speed/quality trade-offs from LLMModelCatalog
- [ ] LLM model download/delete UI (reuse pattern from ModelDownloadView)
- [ ] API key entry (for remote) with test button
- [ ] Cleanup level selector
- [ ] Preview: show raw vs. cleaned text for last transcription

#### Step 3.7: Script Preference (Hinglish-specific)

- [ ] Setting: Hindi portions in Devanagari vs. Romanized
- [ ] If Romanized preferred, add to LLM prompt: "Transliterate any Devanagari script to Roman/Latin script"
- [ ] If no LLM, implement basic Devanagari → Roman transliteration (or vice versa) as a simple post-processor

**Phase 3 deliverable**: Transcription is cleaned up by fast text processing (filler words, self-corrections) and optionally by a local or remote LLM (grammar, formatting). Works with or without LLM enabled.

---

### Phase 3.5: Dictionary, Word Boosting & Text Intelligence

**Goal**: Improve transcription accuracy via personal dictionary and word boosting, add voice shortcuts, and enable per-app tone/context matching.

#### Step 3.5.1: Personal Dictionary Store

- [ ] Create `Dictionary/` directory under Aawaaz/
- [ ] `Dictionary/DictionaryEntry.swift` — Data model:
  ```swift
  struct DictionaryEntry: Identifiable, Codable {
      let id: UUID
      var correctSpelling: String           // canonical form
      var misspellings: [String]            // known Whisper mis-transcriptions
      var isAutoLearned: Bool               // true if learned from user correction
      var lastUsed: Date?                   // for recency-based word boosting
      var useCount: Int                     // for frequency-based word boosting
      var source: EntrySource               // .manual, .autoLearned, .contactImport
  }
  enum EntrySource: String, Codable {
      case manual, autoLearned, contactImport
  }
  ```
- [ ] `Dictionary/DictionaryStore.swift`:
  - [ ] SQLite database at `~/Library/Application Support/Aawaaz/Dictionary/dictionary.sqlite`
  - [ ] CRUD operations: add, update, delete, search entries
  - [ ] Bulk import from CSV (format: `correctSpelling,misspelling1,misspelling2,...`)
  - [ ] Export to CSV for backup
  - [ ] Query: top N most-recently-used entries (for word boosting prompt)
  - [ ] Query: find entry by misspelling (for auto-correction after Whisper)
  - [ ] On-write notification for reactive UI updates
- [ ] `Views/DictionarySettingsView.swift`:
  - [ ] Searchable list of all dictionary entries
  - [ ] Add new entry: correct spelling + known misspellings (comma-separated)
  - [ ] Edit existing entry (inline or sheet)
  - [ ] Delete entry (swipe or button)
  - [ ] Import from CSV button (file picker)
  - [ ] Export to CSV button
  - [ ] Entry count and source breakdown (manual / auto-learned / contacts)
- [ ] Add "Dictionary" tab to SettingsView

#### Step 3.5.2: Contacts Import

- [ ] `Dictionary/ContactsImporter.swift`:
  - [ ] Request Contacts permission via `CNContactStore.requestAccess(for: .contacts)`
  - [ ] Fetch all contacts: `CNContactFetchRequest` with `givenName` and `familyName` keys
  - [ ] Create `DictionaryEntry` for each unique name (source: `.contactImport`)
  - [ ] Handle duplicates: skip if correctSpelling already exists
  - [ ] Add "Import Contacts" button in DictionarySettingsView
  - [ ] Show import progress and count
- [ ] Add `NSContactsUsageDescription` to Info.plist: "Aawaaz can import contact names to improve transcription accuracy for names."
- [ ] Make contacts import opt-in and clearly explained in UI

#### Step 3.5.3: Word Boosting via Whisper initial_prompt

- [ ] `Dictionary/WordBooster.swift`:
  - [ ] Query `DictionaryStore` for top N entries by recency + frequency (N = configurable, default 50, max ~200 due to 224-token initial_prompt limit)
  - [ ] Construct initial_prompt string: `"Vocabulary: [word1], [word2], [word3], ..."` — this primes Whisper to expect these words
  - [ ] Include contact names in the prompt (weighted by how recently they were transcribed)
  - [ ] Cache the prompt string and rebuild only when dictionary changes
  - [ ] Provide the prompt to `WhisperManager.transcribe()` as a new parameter
- [ ] Update `WhisperManager.swift`:
  - [ ] Add `initialPrompt: String?` parameter to `transcribe()` method
  - [ ] Set `params.initial_prompt` in whisper_full_params when provided:
    ```swift
    if let prompt = initialPrompt {
        prompt.withCString { cStr in
            params.initial_prompt = cStr
        }
    }
    ```
  - [ ] Benchmark: compare transcription accuracy with and without word boosting on a test set of names and jargon
- [ ] Update `TranscriptionPipeline.swift` to pass word booster prompt to WhisperManager

#### Step 3.5.4: Post-Whisper Dictionary Correction

- [ ] After Whisper returns text, scan for known misspellings in `DictionaryStore`
  - [ ] For each word in the transcription, check against `misspellings[]` of all entries
  - [ ] If found, replace with `correctSpelling`
  - [ ] Use case-insensitive matching, preserve original capitalization pattern
- [ ] Wire this as a step in `TextProcessor.process()` — runs after filler removal, before LLM

#### Step 3.5.5: Auto-Learn from User Corrections

- [ ] `Dictionary/AutoLearnManager.swift`:
  - [ ] Strategy 1 (AX-based): After text insertion, monitor `kAXValueAttribute` changes on the focused element for ~5 seconds. If user edits the just-inserted text, compare old vs. new to detect corrections
  - [ ] Strategy 2 (Clipboard-based): Compare clipboard content before and after paste-based insertion. If user does Cmd+Z and types something different, infer a correction
  - [ ] When a correction is detected:
    - [ ] Show a small notification: "Add '[corrected]' to dictionary? (Whisper heard '[original]')"
    - [ ] If user confirms, add entry with `source: .autoLearned`
  - [ ] Rate-limit suggestions to avoid being annoying (max 1 per minute)
  - [ ] Store pending suggestions for later review in DictionarySettingsView
- [ ] Add "Auto-learn corrections" toggle in Settings (default: on)

#### Step 3.5.6: Voice Shortcuts / Snippet Expansion

- [ ] `TextProcessing/SnippetExpander.swift`:
  - [ ] Data model:
    ```swift
    struct VoiceSnippet: Identifiable, Codable {
        let id: UUID
        var triggerPhrase: String      // e.g., "my email"
        var expansionText: String      // e.g., "user@example.com"
        var isEnabled: Bool
    }
    ```
  - [ ] Store snippets in `~/Library/Application Support/Aawaaz/Snippets/snippets.json`
  - [ ] After transcription (after filler removal, before LLM), check if entire transcribed text matches a trigger phrase
  - [ ] Fuzzy matching: use `String.localizedStandardContains()` or Levenshtein distance (threshold: 2 edits for short phrases)
  - [ ] If matched, replace entire transcription with expansion text
  - [ ] If partial match (trigger phrase is a prefix), replace just the prefix portion
- [ ] `Views/SnippetSettingsView.swift`:
  - [ ] List of snippets with trigger → expansion preview
  - [ ] Add/edit/delete snippets
  - [ ] Enable/disable toggle per snippet
  - [ ] Import/export JSON
  - [ ] Built-in examples: "my email", "my address", "zoom link", "my phone"
- [ ] Add "Snippets" tab to SettingsView

#### Step 3.5.7: Tone/Context Matching per App

- [ ] Extend `InsertionContext.swift` with `appCategory`:
  ```swift
  enum AppCategory: String, Codable, CaseIterable {
      case email, chat, document, code, terminal, browser, other
  }
  ```
- [ ] `InsertionContext.appCategory` — computed from bundle ID lookup:
  ```swift
  static let bundleIDToCategory: [String: AppCategory] = [
      "com.apple.mail": .email,
      "com.microsoft.Outlook": .email,
      "com.tinyspeck.slackmacgap": .chat,
      "com.apple.MobileSMS": .chat,
      "com.hnc.Discord": .chat,
      "com.electron.whatsapp": .chat,
      "com.microsoft.Word": .document,
      "com.apple.dt.Xcode": .code,
      "com.microsoft.VSCode": .code,
      "com.googlecode.iterm2": .terminal,
      "com.apple.Terminal": .terminal,
      "com.apple.Safari": .browser,
      "com.google.Chrome": .browser,
      // ... more known bundles
  ]
  ```
- [ ] Per-category LLM prompt instructions in `PostProcessor`:
  - `.email`: "Use formal tone, proper salutations, complete sentences"
  - `.chat`: "Use casual tone, contractions are fine, keep it brief"
  - `.code`: "Preserve technical terms exactly, format as code comments if applicable"
  - `.document`: "Use structured paragraphs, proper punctuation, professional tone"
  - `.terminal`: "Keep commands exact, do not alter technical content"
  - `.browser`: "Context-dependent — use the field type to infer (search bar vs. compose window)"
- [ ] `Views/AppOverridesView.swift`:
  - [ ] List of known apps with category assignments
  - [ ] Allow user to override category for any app
  - [ ] Per-app insertion method override (currently in code, add UI)
  - [ ] Store overrides in UserDefaults (key: `appCategory.{bundleID}`)
- [ ] Add "Per-App" tab to SettingsView

**Phase 3.5 deliverable**: Personal dictionary improves Whisper accuracy for names and jargon. Voice shortcuts expand trigger phrases into full text. Per-app tone matching adjusts LLM output style to the target application.

---

### Phase 4: Voice Commands & Undo

**Goal**: Detect and execute editing commands spoken by the user, enable undo of last dictation, and support highlight-and-voice-edit workflows.

#### Step 4.1: Pattern-Matched Commands

- [ ] Define command vocabulary:
  - "delete that" / "undo" → Cmd+Z
  - "undo that" → Trigger undo of last dictation (see Step 4.3)
  - "new line" / "enter" → Insert \n
  - "new paragraph" → Insert \n\n
  - "select all" → Cmd+A
  - "copy that" → Cmd+C
  - "paste" → Cmd+V
  - "tab" → Insert \t
  - "stop" → Deactivate dictation
- [ ] Command detection: check transcription against known phrases before insertion
- [ ] Execute via CGEvent keystroke simulation
- [ ] Visual feedback in overlay (show command name, not the spoken text)

#### Step 4.2: LLM-Interpreted Commands

- [ ] Enhanced LLM prompt that can return either text or a command
- [ ] JSON-structured output: `{"type": "text", "content": "..."}` or `{"type": "command", "action": "...", "params": {...}}`
- [ ] Command execution engine that maps LLM output to system actions
- [ ] Support complex commands: "make that bold" (Cmd+B), "move to the beginning" (Cmd+Up), etc.

#### Step 4.3: Undo Last Dictation

- [ ] `TextInsertion/InsertionHistory.swift`:
  - [ ] Ring buffer storing last N insertions (default N=10):
    ```swift
    struct InsertionRecord {
        let text: String
        let insertionMethod: InsertionContext.InsertionMethod
        let appBundleID: String?
        let previousValue: String?  // only if AX-based insertion captured it
        let timestamp: Date
    }
    ```
  - [ ] Append a record after every successful insertion in `TextInsertionManager`
- [ ] Undo logic in `TextInsertionManager`:
  - [ ] If last insertion was AX-based and `previousValue` is available: restore previous value via `kAXValueAttribute`
  - [ ] If last insertion was paste-based: simulate Cmd+Z via `CGEventPost`
  - [ ] If last insertion was clipboard-only: no-op (notify user it can't be undone)
- [ ] Hotkey for undo:
  - [ ] Register a secondary global hotkey (default: Cmd+Shift+Z, configurable in HotkeyConfiguration)
  - [ ] On trigger: call `TextInsertionManager.undoLastInsertion()`
  - [ ] Show overlay: "Undone: [truncated text]"
- [ ] Voice command integration:
  - [ ] "undo that" / "delete that" triggers undo (from Step 4.1 command vocabulary)
  - [ ] Must detect these before the transcription is inserted (check commands first)

#### Step 4.4: LLM Command Mode (Highlight + Voice Edit)

- [ ] Register a secondary hotkey for "command mode" (default: Cmd+Shift+D, configurable)
- [ ] On activation:
  - [ ] Read selected text from focused app via `kAXSelectedTextAttribute` (AccessibilityManager)
  - [ ] Show overlay: "Speak a command for the selected text..."
  - [ ] Start audio capture → VAD → Whisper transcription (reuse existing pipeline)
- [ ] After transcription:
  - [ ] Send to LLM with prompt:
    ```
    The user has selected the following text in [app_name]:
    ---
    [selected_text]
    ---
    The user's voice command is: "[transcribed_command]"
    Apply the command to the selected text and return only the result.
    Examples of commands: "make this a bullet list", "translate to Hindi",
    "summarize", "make more formal", "fix the grammar", "make shorter"
    ```
  - [ ] Replace the selection with LLM output via `kAXSelectedTextAttribute` or paste
  - [ ] Show overlay: "Applied: [command summary]"
- [ ] Fallback: if no text is selected, show overlay: "Select text first, then use this shortcut"
- [ ] Error handling: if AX can't read selection, show error and suggest using a compatible app
- [ ] This requires LLM to be enabled (local or remote) — show a helpful message if LLM is off

**Phase 4 deliverable**: Users can speak commands to control editing, undo last dictation via hotkey or voice, and apply voice-driven edits to selected text.

---

### Phase 5: Polish, UX Enhancements & Multi-Language Expansion

#### Step 5.1: Sound Effects

- [ ] Create `SoundEffects/` directory
- [ ] `SoundEffects/SoundEffectManager.swift`:
  - [ ] Load bundled audio files (`.caf` format, < 0.5s each)
  - [ ] 4 sound cues: `startRecording`, `stopRecording`, `textInserted`, `error`
  - [ ] Play via `NSSound` or `AVAudioPlayer` (NSSound is simpler for short cues)
  - [ ] Respect system "Play user interface sound effects" setting
  - [ ] Global toggle in Settings (default: on)
- [ ] Bundle 4 subtle audio files in `SoundEffects/Sounds/`:
  - [ ] `start_recording.caf` — soft click/ping
  - [ ] `stop_recording.caf` — soft descending tone
  - [ ] `text_inserted.caf` — gentle confirmation chime
  - [ ] `error.caf` — subtle alert tone
- [ ] Wire into pipeline:
  - [ ] `startListening()` → play start sound
  - [ ] `stopListening()` → play stop sound
  - [ ] Successful insertion → play success sound
  - [ ] Pipeline error → play error sound

#### Step 5.2: Auto-Pause Media

- [ ] `Audio/MediaController.swift`:
  - [ ] On dictation start: send system media pause key event via `CGEventPost` using `NX_KEYTYPE_PLAY` (IOKit HID event)
  - [ ] On dictation end + text inserted: send play key event to resume
  - [ ] Use `MRMediaRemoteGetNowPlayingInfo` to check if media is actually playing before pausing (avoid pausing already-paused media)
  - [ ] Track whether we paused (to avoid spurious resume)
- [ ] Toggle in Settings (default: off)
- [ ] Add to General Settings tab: "Pause media during dictation" toggle

#### Step 5.3: Whisper/Quiet Mode

- [ ] Add `whisperMode: Bool` toggle to `AppState`
- [ ] When enabled:
  - [ ] Apply gain multiplier (2x-4x) to audio buffer samples in `AudioCaptureManager.swift` before passing to VAD/Whisper
  - [ ] Lower VAD speech threshold from default to ~0.3 (configurable) in `VADProcessor`
  - [ ] Optionally apply a simple noise gate: zero out samples below a noise floor amplitude
  - [ ] Clamp amplified samples to [-1.0, 1.0] to prevent clipping
- [ ] Menu bar toggle: microphone icon changes to indicate quiet mode
- [ ] Settings: "Quiet mode" toggle with brief explanation

#### Step 5.4: Per-App Insertion Method Override (Settings UI)

- [ ] `Views/AppOverridesView.swift` (if not already created in Phase 3.5):
  - [ ] List of apps that have been used with Aawaaz (tracked from `InsertionContext` history)
  - [ ] For each app: dropdown to select insertion method: Auto / AX API / Clipboard Paste / Keystroke Simulation
  - [ ] Pre-populate known problematic apps:
    - Terminal.app → Clipboard Paste
    - iTerm2 → Clipboard Paste
    - Electron apps with known AX issues → Keystroke Simulation
  - [ ] "Reset to Auto" button per app
  - [ ] This surfaces the existing `TextInsertionManager.setPreferredMethod()` API as a user-facing setting

#### Step 5.5: Model Auto-Update Notifications

- [ ] `Models/ModelUpdateChecker.swift`:
  - [ ] On app launch (and optionally every 24h), fetch a remote JSON manifest from a hosted URL
  - [ ] Manifest format:
    ```json
    {
      "whisperModels": [
        { "name": "turbo", "version": "1.8.4", "url": "...", "checksum": "...", "size": 547000000 }
      ],
      "llmModels": [
        { "name": "qwen3-0.6b", "version": "1.0.1", "url": "...", "checksum": "...", "size": 400000000 }
      ]
    }
    ```
  - [ ] Compare against local `ModelCatalog` versions
  - [ ] If newer version available, show a non-intrusive `NSUserNotification` / `UNUserNotificationCenter` banner
  - [ ] Clicking notification opens Models tab in Settings
  - [ ] Never auto-download — user must initiate update
- [ ] Add "Check for model updates" button in Models Settings tab
- [ ] Privacy: the manifest fetch is the only network call in the app (besides model downloads and remote LLM if enabled). No telemetry, no user data sent.

#### Step 5.6: Productivity Stats

- [ ] Create `Stats/` directory
- [ ] `Stats/StatsTracker.swift`:
  - [ ] Track per-session: words dictated, audio duration (seconds), WPM (words / duration in minutes)
  - [ ] Track per-insertion: timestamp, word count, app used, insertion method
  - [ ] Observe `TranscriptionPipeline` events to capture data
- [ ] `Stats/StatsStore.swift`:
  - [ ] SQLite database at `~/Library/Application Support/Aawaaz/Stats/stats.sqlite`
  - [ ] Tables: `sessions` (id, start_time, end_time, word_count, duration_seconds, avg_wpm), `insertions` (id, session_id, timestamp, word_count, app_bundle_id)
  - [ ] Queries: total words all-time, total sessions, current daily streak, weekly/monthly aggregates
- [ ] `Views/StatsView.swift`:
  - [ ] Small stats card in menu bar popover (below status, above actions):
    - [ ] Today: X words, Y sessions
    - [ ] This week: X words, avg WPM
    - [ ] Streak: N days
    - [ ] All-time: X words, Y sessions
  - [ ] Compact design — 2-3 lines max in popover, expandable for full view
- [ ] Optional: weekly summary notification (local notification every Sunday with week's stats)
- [ ] Settings toggle: "Show stats in menu bar" (default: on)

#### Step 5.7: UX Polish

- [ ] Refined overlay design (glassmorphic, matches macOS aesthetic)
- [ ] Transcription history viewer (searchable, with timestamps)
- [ ] Audio waveform visualization during recording
- [ ] Menubar icon animation during recording/processing

#### Step 5.8: Performance Optimization

- [ ] Profile and optimize the VAD → Whisper pipeline
- [ ] Implement interim results (show partial transcription while still speaking)
- [ ] Pre-warm whisper.cpp model on app launch (optional, uses more RAM)
- [ ] Benchmark and optimize CoreML conversion for VAD
- [ ] Explore CoreML conversion for Whisper models (ANE acceleration)

#### Step 5.9: IndicWhisper Integration

- [ ] Convert AI4Bharat IndicWhisper models to GGML format
- [ ] Benchmark against vanilla Whisper turbo/large-v3 on Hinglish test set
- [ ] Add as downloadable model option if performance is better
- [ ] Document conversion process for community contributions

#### Step 5.10: Additional Languages

- [ ] Language-specific model recommendations in ModelCatalog
- [ ] Test and validate top 10 languages by user demand
- [ ] Community contribution pipeline for language-specific fine-tuned models

#### Step 5.11: Custom Fine-Tuning (Advanced)

- [ ] Document LoRA fine-tuning process for Hinglish
- [ ] Provide sample training data format
- [ ] MLX-based fine-tuning script that runs on Apple Silicon
- [ ] Model export to GGML format for use in Aawaaz

**Phase 5 deliverable**: A polished, feature-rich dictation app with sound feedback, productivity stats, quiet mode, media auto-pause, model updates, and strong multi-language support.

---

## New Feature Placement Rationale

| # | Feature | Phase | Rationale |
|---|---------|-------|-----------|
| — | Default hotkey change (Fn/Ctrl) + hold-to-talk default | 2.5 | Foundation-level change. Should land before new pipeline work. Low risk. |
| — | Listening/processing indicator overhaul (waveform/bubble) | 2.5 | UX feedback is core to the dictation experience. Improves all subsequent phases. |
| — | Pipeline rearchitecture (process-then-insert) | 3 (Step 3.0) | Prerequisite for all post-processing. Text must only be inserted after full chain completes. |
| 1 | Personal Dictionary with Auto-Learn | 3.5 | Depends on Whisper pipeline (Phase 1-2 ✅). Independent of LLM. Enables word boosting. |
| 2 | Word Boosting via initial_prompt | 3.5 | Depends on dictionary store. Modifies WhisperManager.transcribe() params. |
| 3 | Pre-LLM Filler Word Removal | 3 (Step 3.1) | Runs before LLM, works without LLM. Part of text processing pipeline. |
| 4 | Self-Correction Detection | 3 (Step 3.1) | Same pipeline stage as filler removal. Pre-LLM text processing. |
| 5 | Tone/Context Matching per App | 3.5 (Step 3.5.7) | Extends InsertionContext. Affects LLM prompts (Phase 3). |
| 6 | Voice Shortcuts / Snippet Expansion | 3.5 (Step 3.5.6) | Runs in text processing pipeline. Independent of LLM and voice commands. |
| 7 | Whisper/Quiet Mode | 5 (Step 5.3) | UX enhancement. Modifies audio pipeline gain. Low dependency. |
| 8 | Auto-Pause Media | 5 (Step 5.2) | UX polish. Independent of transcription pipeline. |
| 9 | Productivity Stats | 5 (Step 5.6) | Observes pipeline events. No impact on core flow. Polish feature. |
| 10 | Undo Last Dictation | 4 (Step 4.3) | Natural extension of voice commands ("undo that"). Requires insertion history. |
| 11 | LLM Command Mode (Highlight+Edit) | 4 (Step 4.4) | Enhancement to Phase 4 voice commands. Requires LLM (Phase 3). |
| 12 | Sound Effects | 5 (Step 5.1) | Pure UX polish. No dependencies. |
| 13 | Per-App Insertion Method Override | 5 (Step 5.4) | Settings UI for existing code. Low priority polish. |
| 14 | Model Auto-Update Notifications | 5 (Step 5.5) | Nice-to-have. Only network feature besides downloads/remote LLM. |
| — | Fix Hindi→English translation in Hinglish mode | 2.5 (Step 2.5.3) | Active bug. Whisper translates Hindi instead of transcribing. Quick params fix + initial_prompt biasing. |

---

## Technical Decisions & Trade-offs

### Why whisper.cpp over MLX Whisper?

| Factor | whisper.cpp | MLX Whisper |
|--------|------------|-------------|
| Language | C/C++ with Swift bindings | Python (mlx framework) |
| Integration | Native SPM package | Python subprocess or embedding |
| Performance | Metal + CoreML + NEON | MLX unified memory |
| Streaming | Built-in stream example | Manual implementation |
| Community | Massive (30k+ stars) | Smaller |
| Maintenance | Extremely active | Active but smaller scope |

**Decision**: whisper.cpp. Embedding Python in a Swift app adds massive complexity. whisper.cpp's Swift bindings make it a natural fit. Performance is comparable.

### Why llama.cpp over MLX LLM?

Same reasoning as above. Same developer ecosystem, same model format, same Swift integration patterns. Consistency reduces learning surface.

### Why ONNX Runtime for Silero VAD (not CoreML)?

| Factor | ONNX Runtime | CoreML |
|--------|-------------|--------|
| Setup | Add SPM package, load .onnx file | Convert model, handle .mlmodel compilation |
| Compatibility | Silero ships .onnx natively | Manual conversion (may have issues) |
| Performance | Fast enough (sub-ms per frame) | Slightly faster (ANE) but overkill for 2MB model |
| Debugging | Standard ONNX tooling | Apple-specific tooling |

**Decision**: Start with ONNX Runtime for simplicity. Migrate to CoreML later if needed for performance (unlikely — VAD is not the bottleneck).

### Why not use Apple's Speech Framework as a fallback?

- No code-switching support (single locale per recognizer)
- Less accurate than Whisper for non-English
- Could be offered as an ultra-low-latency option for English-only mode in the future
- Not worth the complexity of maintaining two transcription backends in MVP

### Hold-to-talk vs. Toggle: Default?

**Working hypothesis**: Default to **hold-to-talk** because it is more intuitive for short dictation and prevents the "forgot to turn it off" problem. Confirm the actual shortcut choice only after validating hotkey capture reliability and conflicts in real apps. Toggle mode should remain available in settings for longer dictation sessions.

### Audio chunk size for streaming

**Working hypothesis**: Start with VAD-based segmentation rather than fixed chunks. Speech boundaries are natural break points. This gives:
- Lower latency (process as soon as speech ends, don't wait for fixed interval)
- Better accuracy (Whisper gets complete utterances, not arbitrary cuts)
- More efficient (skip silence entirely)

Validate this against real UX expectations. If end-to-end latency still feels too slow, add interim inference or more streaming-oriented behavior earlier instead of treating it as Phase 5 polish.

For long continuous speech without pauses, impose a maximum segment duration of 15 seconds (process what we have and continue buffering).

## Dependencies

| Package | Source | Purpose | Phase |
|---------|--------|---------|-------|
| whisper.cpp | github.com/ggerganov/whisper.cpp | Transcription engine (XCFramework) | 1 ✅ |
| onnxruntime-swift | Microsoft | Silero VAD inference | 1 ✅ |
| llama.cpp | github.com/ggerganov/llama.cpp | Local LLM post-processing (GGUF models) | 3 |
| SQLite.swift (or GRDB) | github.com/groue/GRDB.swift | Dictionary store, stats DB, snippets persistence | 3.5 |
| Contacts framework | Apple (system) | CNContactStore for name import | 3.5 |
| MediaPlayer framework | Apple (system) | MRMediaRemoteGetNowPlayingInfo for auto-pause detection | 5 |
| IOKit | Apple (system) | NX_KEYTYPE_PLAY media key events | 5 |
| UserNotifications | Apple (system) | Model update notifications, weekly stats summary | 5 |

Six external dependencies total (whisper.cpp, onnxruntime-swift, llama.cpp, SQLite/GRDB). The rest are Apple system frameworks requiring no additional downloads.

## Risk Mitigation

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Hinglish accuracy insufficient | Medium | High | Test early (Phase 1). IndicWhisper models as fallback. LoRA fine-tuning as escape hatch |
| Whisper translates Hindi instead of transcribing | High | High | Set `params.translate = false` explicitly. For Hinglish mode, set language to `"hi"` instead of auto-detect. Use initial_prompt with Romanized Hindi samples to bias output script. LLM post-processing as safety net (Phase 3). Fine-tuned Hinglish models long-term (Phase 5) |
| AX API doesn't work in some apps | High | Medium | Keystroke simulation fallback. Per-app override settings (Phase 5.4 UI). Document known incompatible apps |
| whisper.cpp Swift bindings have issues | Low | High | Well-established bindings, SwiftUI example in repo. Fallback: use C API directly from Swift |
| LLM over-corrects transcription | Medium | Medium | Configurable cleanup levels. Show raw vs. cleaned text. Pre-LLM text processing handles basics without LLM |
| Memory pressure on 8GB machines | Medium | Medium | Default to Qwen 3 0.6B (~0.4 GB) + Whisper turbo (~2.5 GB) ≈ ~3 GB total. Smart model loading/unloading. Never load full Whisper + large LLM simultaneously on 8GB |
| initial_prompt word boosting has limited effect | Medium | Low | Word boosting is additive — worst case it has no effect. Post-Whisper dictionary correction provides a second chance to fix known misspellings |
| Auto-learn false positives (user edits unrelated to transcription) | Medium | Low | Require user confirmation before adding to dictionary. Rate-limit suggestions. Allow bulk review/delete of auto-learned entries |
| Contacts permission rejected by privacy-conscious users | Medium | Low | Contacts import is fully optional and clearly explained. Dictionary works without it. Word boosting falls back to manual entries only |
| SQLite/GRDB integration complexity | Low | Low | GRDB is well-maintained with excellent Swift concurrency support. JSON file fallback for dictionary if SQLite proves problematic |
| Sound effects feel annoying | Low | Medium | Default to on but prominent toggle in Settings. Keep sounds very short (<0.5s) and at system volume |
| Media auto-pause interferes with user workflow | Low | Medium | Default to off. Check if media is actually playing before pausing. Only resume if we were the ones who paused |
| LLM Command Mode (highlight+edit) requires complex AX interaction | Medium | Medium | Fallback to paste if AX selection reading fails. Require LLM to be enabled. Show helpful error messages for incompatible apps |
| Model update manifest hosting | Low | Medium | Start with a static JSON file on GitHub Pages or similar. No server infrastructure needed. Graceful failure if unreachable |
| Filler word removal false positives | Low | Medium | Word-boundary regex prevents "I like dogs" → "I dogs". Multi-word phrase matching handles "you know" as unit. Configurable word list lets users remove problematic entries |

## Development Environment Setup

```bash
# Prerequisites
# - macOS 14+ (Sonoma or later)
# - Xcode 15+ (with Swift 5.9+)
# - Apple Silicon Mac (M1 or later)

# Clone
git clone <repo-url> aawaaz
cd aawaaz

# Open in Xcode
open Aawaaz/Aawaaz.xcodeproj

# Or build from command line
xcodebuild -project Aawaaz/Aawaaz.xcodeproj -scheme Aawaaz -configuration Debug build

# Download a model for testing
mkdir -p ~/Library/Application\ Support/Aawaaz/Models
curl -L -o ~/Library/Application\ Support/Aawaaz/Models/ggml-base.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
```

## Learning Resources (Swift/SwiftUI for newcomers)

- whisper.cpp SwiftUI example: `whisper.cpp/examples/whisper.swiftui/` — a complete transcription app you can build on
- Apple's SwiftUI tutorials: developer.apple.com/tutorials/swiftui
- Hacking with Swift (free): hackingwithswift.com — practical SwiftUI guides
- MenuBarExtra documentation: developer.apple.com/documentation/swiftui/menubarextra
- AXUIElement reference: developer.apple.com/documentation/applicationservices/accessibility
