# Murmur

Push-to-talk dictation for macOS, built on Apple's on-device `SpeechAnalyzer`.

Hold **right Option**, talk, release. The transcript is pasted into whatever app
has focus.

## Requirements

macOS 26 or later, Apple Silicon, Xcode 26 toolchain.

## Build and install

```sh
./Scripts/build-app.sh
cp -R .dist/Murmur.app /Applications/
open -a /Applications/Murmur.app
```

## Permissions

Two grants are needed on first run:

- **Microphone** — prompted automatically.
- **Accessibility** — System Settings ▸ Privacy & Security ▸ Accessibility, add
  `/Applications/Murmur.app`. Needed both to read the hotkey and to paste.

The menu bar item shows which grant is outstanding.

## Tests

```sh
swift test
```

Audio conversion and clipboard save/restore are covered. The hotkey tap and the
synthetic paste are verified by hand.
