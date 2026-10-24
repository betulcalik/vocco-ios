# Vocco — Pronunciation Coach 🎙️

An iOS app that helps English learners perfect pronunciation: hear an ideal native voice
(ElevenLabs TTS), record yourself, and get instant word-by-word scoring (ElevenLabs Scribe STT).
Zero LLM usage — scoring runs locally with word-level alignment.

## Setup (BYOK — bring your own key)

1. Create a free key at [elevenlabs.io](https://elevenlabs.io) (Profile → API Keys).
   Grant only: **Text to Speech** + **Speech to Text**.
2. `cp Vocco/Secret.key.example Vocco/Secret.key` and paste your key into it.
   `Secret.key` is git-ignored — it is embedded into the app bundle at build time and
   moved into the iOS Keychain on first launch.

## Build

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Vocco.xcodeproj -scheme Vocco \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Or generate the project and open `Vocco.xcodeproj` in Xcode (iOS 17+, Swift 5 mode).

## Stack

SwiftUI (iOS 17, `@Observable`) · Swift Charts · AVFoundation · ElevenLabs
(`eleven_flash_v2_5` TTS + `scribe_v1` STT) · local Needleman–Wunsch word-alignment scoring.

## Security notes

- Never commit `Vocco/Secret.key` (git-ignored by default).
- Keys in app bundles can be extracted from the binary — fine for personal builds;
  use a backend proxy before shipping publicly.
- Rotate your key at ElevenLabs if it ever leaks.
