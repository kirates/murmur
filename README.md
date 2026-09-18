# Murmur

Push-to-talk dictation for macOS, built on Apple's on-device `SpeechAnalyzer`.

Hold **right Option**, talk, release. The transcript is pasted into whatever app
has focus.

Double-tap right Option to latch recording on for long passages, then tap once
more to stop. A latched session runs as long as you like.

## Cleanup

Two passes run before the paste.

Filler removal always runs: `um`, `uh`, stutters, opening `so`/`okay`, trailing
`right?`. These rules only delete tokens that carry no meaning, so a dictated
shell command survives them.

Sentence rewriting is off by default, behind **Clean up sentences** in the menu.
It uses Apple's on-device model to resolve self-corrections, drop false starts,
and punctuate. It can change meaning, so leave it off for code and turn it on for
prose. If the model returns something suspicious — a refusal, an answer to your
passage, a wildly different length — the rules-only text is used instead.

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

The build is signed with an Apple Development identity. Ad-hoc signing does not
work here: TCC keys an ad-hoc signature on the binary hash, so every rebuild
silently voids both grants. If grants ever go stale anyway, clear them with
`tccutil reset Accessibility com.kirates.murmur` and re-add the app.

The menu bar item shows which grant is outstanding.

## Tests

```sh
swift test
```

Audio conversion and clipboard save/restore are covered. The hotkey tap and the
synthetic paste are verified by hand.
