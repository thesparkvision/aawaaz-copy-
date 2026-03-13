# Aawaaz - Product Specification

## Overview

Aawaaz (आवाज़ — "voice" in Hindi) is a system-wide, real-time, fully local voice-to-text dictation app for macOS. It enables users to speak in any application and have their speech transcribed and inserted at the cursor — similar to WisprFlow, but with full privacy (no cloud dependency), multi-lingual support, and first-class Hindi-English (Hinglish) code-switching.

## Target Platform

- macOS on Apple Silicon (M1/M2/M3/M4)
- Intel Macs are explicitly out of scope
- iOS port is a future goal (shared SwiftUI views + AVAudioEngine code)
- Android is not planned

## Core Value Proposition

1. **Fully local** — All transcription happens on-device. No audio ever leaves the machine. Privacy by default.
2. **System-wide** — Works in any app (Slack, VS Code, browser, Notes, Terminal, etc.) using the most reliable available insertion path, with macOS Accessibility as the default starting point.
3. **Hinglish-native** — First-class support for Hindi-English code-switching (speaking Hindi mixed with English words mid-sentence).
4. **Fast** — Targets a competitive, WisprFlow-like experience for short phrases, with implementation details and latency trade-offs validated on real Apple Silicon hardware.
5. **Beautiful & minimal** — Small floating overlay + menu bar presence. Stays out of the way.

## Implementation Notes

- This specification defines product requirements and UX goals, not a mandate to use one specific macOS API everywhere.
- Where concrete implementation examples are given below (hotkeys, Accessibility insertion, streaming strategy), treat them as likely starting points that must still be validated against real app compatibility, permission behavior, and measured latency.
- If implementation evidence shows a named approach is insufficient, prefer changing the implementation approach over weakening the product outcome.

## User Experience

### Activation Flow

1. User presses a configurable global hotkey (examples: hold-to-talk or toggle-based shortcuts; the exact default should be chosen only after validating reliability and conflict rate on macOS)
2. A subtle audio cue confirms that recording has started
3. A small floating overlay appears near the cursor/focused text field, showing an animated recording indicator that reacts to the user's voice
4. User speaks naturally (in English, Hindi, or mixed Hinglish)
5. Interim transcription or other live feedback appears in the overlay while speech is being processed, as allowed by the chosen latency/accuracy strategy
6. On release of hotkey (or silence timeout), a stop cue plays, the transcription is cleaned up (filler removal, optional LLM processing), and the final text is inserted into the focused text field
7. An audio cue confirms successful insertion; overlay dismisses
8. If the user presses the undo hotkey or says "undo that," the last insertion is reverted

### Two Activation Modes

- **Hold-to-talk**: Hold the hotkey while speaking. Release to finish. Best for short dictation.
- **Toggle mode**: Press hotkey to start, press again to stop. Best for longer dictation.

### Menu Bar App

- Lives in macOS menu bar (no dock icon)
- Popover shows:
  - Current status (idle / listening / processing)
  - Selected model (turbo / large-v3 / custom)
  - Selected language mode (Auto / English / Hindi / Hinglish)
  - Productivity stats summary (words dictated today, streak)
  - Quick access to settings
- Runs as a background process (LSUIElement)

### Settings

- **Model selection**: Choose between downloaded models (turbo, large-v3, etc.) with size/speed/accuracy trade-off displayed
- **Model management**: Download, delete, and update models
- **Model updates**: Check for newer model versions (opt-in network call)
- **Language mode**: Auto-detect (default), force English, force Hindi, or Hinglish-optimized
- **Hotkey configuration**: Choose activation key and mode (hold vs. toggle)
- **LLM post-processing**: Off / Local (Qwen3 1.7B default, others available) / Remote (Claude API / OpenAI API)
- **LLM cleanup level**: Light (filler words only) / Medium (+ grammar) / Full (+ context-aware formatting)
- **Latency vs. accuracy**: Slider or presets (Fast/Balanced/Quality) that adjust chunk size and model
- **Text insertion method**: Auto / AX API / Keystroke simulation / Clipboard
- **Audio input**: Select microphone device
- **Personal dictionary**: Manage custom words, correction pairs, and imported names; import from macOS Contacts or CSV
- **Voice shortcuts**: Manage trigger phrase → expansion pairs; add, edit, delete, import, and export
- **Sound effects**: Toggle audio cues on or off
- **Whisper mode**: Toggle quiet-environment dictation mode on or off
- **Media pause**: Toggle auto-pause of playing media during dictation on or off
- **Per-app preferences**: Override the insertion method and tone category for individual apps
- **Productivity stats**: Toggle visibility in the menu bar popover; toggle weekly summary notification
- **Text cleanup**: Toggle filler word removal and self-correction detection; edit the filler word list

## Transcription Engine

### Primary: whisper.cpp

- C/C++ Whisper implementation optimized for Apple Silicon
- Metal GPU acceleration for encoder
- Optional CoreML acceleration for Apple Neural Engine
- GGML quantized models (Q5_0 for best size/quality trade-off)
- No language parameter by default for best code-switching behavior

### Models (user-downloadable)

| Model | Download Size | RAM Usage | Speed (M2, 1min) | Hinglish Quality | Recommended For |
|-------|--------------|-----------|-------------------|------------------|-----------------|
| small | ~181 MB | ~1 GB | ~3s | Marginal | Low-RAM machines, quick notes |
| turbo | ~600 MB | ~2.5 GB | ~4s | Good | **Default — best trade-off** |
| large-v3 | ~1.1 GB | ~4 GB | ~8s (Metal) | Best | Quality mode, important dictation |
| indicwhisper* | TBD | TBD | TBD | Potentially best | Hinglish-optimized (if GGML conversion works) |

*IndicWhisper models from AI4Bharat, pending GGML format conversion and benchmarking.

### Voice Activity Detection (VAD)

- Silero VAD (~2 MB model)
- Runs on every 30ms audio frame
- Detects speech start/end boundaries
- Prevents Whisper hallucinations on silence
- Configurable speech padding (default: 300ms after speech ends)

### Streaming Architecture

The exact implementation can range from VAD-segmented final inference to more streaming-oriented interim inference. The chosen approach should be driven by measured latency and perceived UX quality, not by attachment to a single pipeline shape.

```
Microphone (AVAudioEngine, 16kHz mono)
    │
    ▼
Silero VAD (per 30ms frame)
    │
    ├── No speech → discard, continue
    │
    └── Speech detected → buffer audio
            │
            ├── Speech ongoing → continue buffering
            │                    (optionally run interim inference every N seconds)
            │
            └── Speech ended (+ padding) → send buffer to whisper.cpp
                    │
                    ▼
              whisper.cpp inference (Metal GPU)
                    │
                    ▼
              Raw transcription text
                    │
                    ▼
              Pre-LLM cleanup (filler words, self-corrections, dictionary, snippets)
                    │
                    ▼
              [Optional] LLM post-processing
                    │
                    ▼
              Insert text into focused app
```

### Latency Budget (turbo model, M2+)

This is a target envelope, not a guarantee. It should be validated early on representative Apple Silicon hardware. If the measured experience is not competitive enough, interim inference or other latency reductions should move earlier in the roadmap.

| Stage | Time |
|-------|------|
| VAD speech-end detection + padding | ~300ms |
| whisper.cpp inference (turbo, Metal) | ~2-4s for typical utterance |
| Pre-LLM cleanup (filler removal, corrections, dictionary) | ~0ms (negligible) |
| LLM cleanup (if enabled, local) | <1s – ~2s depending on model |
| Text insertion (AX API) | ~10ms |
| **Total without LLM** | **~2.5-4.5s** |
| **Total with local LLM** | **~3.5-6.5s** |

## LLM Post-Processing

### Purpose

- Remove filler words ("um", "uh", "so like", "basically")
- Fix grammar and punctuation
- Context-aware formatting (Markdown in code editors, casual in chat apps, formal in email)
- Handle Hinglish romanization preferences (user may prefer "kaise ho" vs "कैसे हो")

### Pre-LLM Cleanup

Even without an LLM enabled, the app performs basic text cleanup that runs instantly with zero additional latency:

- **Filler word removal** — Common filler words and phrases (um, uh, like, you know, basically, so, I mean, right, actually, literally) are stripped automatically. The filler word list is configurable in settings, so users can add or remove entries.
- **Self-correction detection** — If the user says "Tuesday, actually no, Wednesday" or "send it to John, I mean Sarah," only the corrected version is kept. The app recognizes correction markers like "actually no," "I mean," "wait," "scratch that," and similar phrases, and discards the superseded text.

These steps run after Whisper and before the LLM (if enabled). They also apply when LLM post-processing is turned off, so every user benefits from cleaner output regardless of their LLM setting.

### Local LLM Options

| Model | Size (Q4) | RAM | Speed (M2+) | Quality | Recommended For |
|-------|-----------|-----|-------------|---------|-----------------|
| **Qwen3 1.7B** | ~1.1 GB | ~1.5 GB | ~1-2s | Good — strong multilingual and Hinglish support | **Primary — best balance of quality, speed, and multilingual** |
| Qwen3 0.6B | ~650 MB | ~800 MB | <1s | Decent — fast and lightweight | Light option for 8 GB machines or when speed matters most |
| Qwen3 4B | ~2.5 GB | ~3 GB | ~2-3s | Very good — handles complex restructuring and Hinglish well | Quality option for users with 16 GB+ RAM |

*Alternatives*: Phi-3.5-mini (3.8B), Llama 3.2 3B, and Gemma 2 2B remain available as downloadable options for users who have already downloaded them or prefer a different model family.

Qwen3 models support a non-thinking mode that skips chain-of-thought reasoning, reducing latency for simple cleanup tasks where deep reasoning is unnecessary.

### Tone Matching

The LLM adapts its cleanup style based on which app the user is typing in:

| App Category | Tone | Examples |
|-------------|------|----------|
| Email | Formal — proper sentences, professional salutations | Mail, Outlook |
| Chat | Casual — contractions, concise phrasing | Slack, iMessage, Discord, WhatsApp |
| Code editors | Technical — preserve terms exactly, minimal rephrasing | Xcode, VS Code |
| Documents | Structured — well-formed paragraphs, clear punctuation | Word, Pages, Google Docs |
| Terminal | Verbatim — do not alter commands or technical content | Terminal, iTerm2 |

The app automatically detects the category of the frontmost application. Users can override the detected category for any app in settings (see "Per-app preferences" under Settings).

### Command Mode

Users can select existing text in any app, press a secondary hotkey, and speak an instruction. The LLM transforms the selected text according to the spoken instruction and replaces the selection with the result.

Examples of voice instructions:

- "Make this a bullet list"
- "Translate to Hindi"
- "Summarize in two sentences"
- "Make more formal"
- "Fix the code"

Command mode is separate from regular dictation — it is an editing tool, not a transcription tool. It requires an LLM to be enabled (local or remote). If no text is selected, the app prompts the user to select text first.

### Remote LLM Options

- Claude API (Haiku for speed, Sonnet for quality)
- OpenAI API (GPT-4o-mini for speed)
- User provides their own API key in settings

### Memory Management

- LLM model is lazy-loaded (only when post-processing is enabled)
- Can be unloaded to free RAM
- Whisper and LLM can coexist on 16GB+ machines comfortably
- On 8GB machines, the light LLM option (Qwen3 0.6B at ~800 MB RAM) can coexist with Whisper turbo (~2.5 GB); for larger LLMs, recommend a smaller Whisper model or disabling LLM

## Text Insertion

### Primary: Accessibility API (AXUIElement)

Accessibility should be the default insertion path when it works well, but "system-wide" support should be interpreted as "use the most reliable insertion strategy per app," not "force one AX mutation path everywhere."

1. Get the frontmost application via `NSWorkspace.shared.frontmostApplication`
2. Get the AX application element via `AXUIElementCreateApplication(pid)`
3. Find the focused UI element via `kAXFocusedUIElementAttribute`
4. Verify the element is actually editable/settable for the current app
5. Get current value and selection range where available
6. Insert transcription at the cursor using the least-destructive strategy that works for that app/element (for example selected-text replacement, direct AX mutation, or a validated fallback)

### Fallback: Keystroke Simulation

For apps that don't properly expose usable AX text elements (some Electron apps, games, terminals, or custom editors), paste-based or synthesized-keystroke fallback may be more reliable than direct AX mutation:
1. Copy transcription to clipboard
2. Simulate Cmd+V keystroke via `CGEventPost`

### Fallback: Clipboard Only

If both methods fail, copy to clipboard and show a notification.

### Permissions Required

- **Microphone**: Requested via standard macOS permission dialog
- **Accessibility**: User must manually enable in System Settings > Privacy & Security > Accessibility
- App should guide user through this on first launch with clear instructions

## Voice Commands (Future Phase)

### Pattern-Matched Commands (Phase 4a)

Detect keywords in transcription and execute actions instead of inserting text:

| Command | Action |
|---------|--------|
| "delete that" / "undo that" | Undo last dictation insertion |
| "new line" / "next line" | Insert newline |
| "new paragraph" | Insert double newline |
| "select all" | Cmd+A |
| "copy that" | Cmd+C |
| "period" / "comma" / "question mark" | Insert punctuation |
| "stop dictation" | Deactivate |

### LLM-Interpreted Commands (Phase 4b)

Pass transcription through LLM with instruction to detect commands:
- "Move that paragraph up"
- "Change the email to john@example.com"
- "Make the last sentence more formal"
- "Read that back to me" (future: TTS integration)

## Undo

Users can undo the last dictation insertion using a configurable hotkey or by speaking "undo that" / "delete that" during the next dictation.

- Works across all insertion methods (Accessibility API, paste, clipboard)
- A brief overlay confirms what was undone
- Supports undoing the most recent insertion; earlier insertions follow the target app's native undo behavior

## Multi-Language Support

### Independent Languages

Whisper turbo/large-v3 supports 99 languages. Users select their language in settings, or use auto-detect mode. No special work needed beyond exposing the language selector.

### Code-Switching Pairs

| Priority | Pair | Approach |
|----------|------|----------|
| P0 | Hindi-English (Hinglish) | Whisper auto-detect + IndicWhisper fine-tuned models |
| P1 | Tamil-English | IndicWhisper models |
| P1 | Punjabi-English | IndicWhisper models (limited) |
| P2 | Spanish-English | Whisper auto-detect (works reasonably well) |
| P2 | French-English | Whisper auto-detect |
| P3 | Other Indian languages | AI4Bharat ecosystem |
| P3 | Other pairs | Custom fine-tuning (LoRA on Whisper) |

### Hinglish-Specific Considerations

- Whisper may output Devanagari script for Hindi portions — user should be able to configure preference (Devanagari vs. romanized)
- LLM post-processing can handle script normalization
- Common Hinglish patterns: English technical terms in Hindi sentences, Hindi colloquialisms in English sentences
- Test with representative speakers — Hinglish varies significantly by region and speaker

## Personal Dictionary

Users can build a personal dictionary of custom words, names, technical terms, and acronyms to improve transcription accuracy and control how specific words are rendered.

### Custom Words and Correction Pairs

- Add entries for words Whisper frequently gets wrong — names, brand names, jargon, acronyms
- Define correction pairs: "When Whisper hears X, replace with Y" (e.g., "Erik" → "Eric," "Kubernetees" → "Kubernetes")
- Dictionary entries serve double duty: they bias Whisper toward recognizing the words during transcription *and* fix remaining errors in a post-transcription replacement pass

### Auto-Learning

When a user corrects a transcription after insertion (for example, fixing a misspelled name), the app detects the edit and offers to remember the correction. Confirmed corrections are added to the dictionary automatically so the same mistake is not repeated.

- Suggestions are non-intrusive and rate-limited to avoid being annoying
- Auto-learned entries can be reviewed, edited, or deleted in settings

### Contacts Import

Users can import first and last names from their macOS Contacts with a single click to pre-populate the dictionary. This helps Whisper recognize the names of friends, colleagues, and clients without manual entry. Contacts access is optional, clearly explained, and read-only — no contact data is modified.

### CSV Bulk Import

For teams or domain-specific vocabularies (medical terms, legal jargon, product names), users can import a CSV file of words and correction pairs. Entries can also be exported to CSV for backup or sharing.

### How It Works

Dictionary entries improve recognition accuracy by biasing Whisper toward expected vocabulary during transcription. The same entries are then used for post-transcription replacement, providing two chances to get the right word. All dictionary data is stored locally.

## Voice Shortcuts

Users can define trigger phrases that expand into saved text snippets when spoken. This turns short, memorable phrases into fully expanded content.

### Use Cases

- Say "my email" → inserts full email address
- Say "my phone" → inserts phone number
- Say "zoom link" → inserts personal meeting URL
- Say "thanks reply" → inserts a template response
- Say "copyright header" → inserts a code comment block

### Behavior

- Fuzzy matching accommodates slight pronunciation variations so shortcuts trigger reliably
- Shortcuts are checked after Whisper transcription; if a match is found, the trigger phrase is replaced with the expansion text before any further processing
- If only part of the transcription matches a trigger phrase, just that part is expanded

### Management

Shortcuts are managed in settings: add, edit, delete, enable/disable individual shortcuts, and import or export the full list as a file for backup or sharing across machines.

## Sound & Feedback

Subtle audio cues confirm key moments in the dictation workflow:

| Event | Sound |
|-------|-------|
| Dictation starts (recording begins) | Soft click / ping |
| Dictation stops (recording ends) | Soft descending tone |
| Text successfully inserted | Gentle confirmation chime |
| Error (insertion failed, model not loaded, etc.) | Subtle alert tone |

All sounds are very short (<0.5 seconds) and unobtrusive. They can be toggled off entirely in settings. When disabled, the overlay animation alone provides visual feedback.

## Whisper Mode

A mode designed for dictating quietly in shared spaces — offices, libraries, coffee shops — where speaking at full volume is impractical.

When enabled, the app boosts microphone sensitivity and lowers the speech detection threshold so it can pick up soft-spoken words that would otherwise be ignored. Whisper mode is toggled from the menu bar or in settings.

## Media Pause

Optionally, the app can auto-pause playing media (Spotify, Apple Music, YouTube, podcasts, etc.) when dictation starts, and resume playback when dictation ends and text has been inserted.

- Off by default; toggled in settings
- Only resumes media that the app itself paused — it will not start playback if nothing was playing
- Avoids background audio bleeding into the microphone and degrading transcription quality

## Productivity Stats

The app tracks dictation activity to help users see the value of voice input over time:

- **Words dictated** — total and per-day count
- **Sessions** — number of dictation sessions
- **Speaking speed** — average words per minute
- **Daily streak** — consecutive days with at least one dictation
- **Time saved** — estimated time saved compared to typing (based on average typing speed)

A compact stats summary is displayed in the menu bar popover. An optional weekly summary notification highlights the past week's activity. Stats tracking and the weekly notification can each be toggled independently in settings.

All stats are stored locally and never transmitted.

## Non-Functional Requirements

### Performance

- App launch to ready: < 3 seconds (model pre-loaded)
- Hotkey to listening: < 100ms
- End-of-speech to text inserted: < 5 seconds (turbo, no LLM)
- Idle CPU usage: < 1% (VAD only runs during active listening)
- Idle RAM: ~50-100 MB (app only, models loaded on demand or kept resident per user preference)

### Reliability

- Graceful handling of model loading failures
- Fallback text insertion methods
- Crash recovery (save last transcription)
- Audio device hot-swap support (e.g., switching headsets)

### Privacy

- Zero network calls in default configuration (no telemetry, no cloud)
- Model update checks are the only network call beyond model downloads and remote LLM, and they are opt-in
- Remote LLM is opt-in only with clear indication
- No audio stored to disk (unless user explicitly enables transcription history)
- Dictionary data, voice shortcuts, and productivity stats are stored locally only
- No telemetry, no analytics, no crash reporting in the default configuration
- Optional: encrypted local transcription history

### Accessibility

- VoiceOver compatible settings UI
- High contrast overlay option
- Configurable overlay size and position

## Out of Scope (for now)

- Speaker diarization (who said what)
- Audio file transcription (only live microphone)
- Real-time translation (LLM command mode can translate selected text on demand, but the app does not perform live streaming translation)
- Text-to-speech
- Windows/Linux support
- Collaboration/sharing features
- Built-in fine-tuning UI
