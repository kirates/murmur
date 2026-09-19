# Murmur

Push-to-talk dictation for macOS, built on Apple's on-device `SpeechAnalyzer`.

Hold **right Option**, talk, release. The transcript is pasted into whatever app
has focus.

Double-tap right Option to latch recording on for long passages, then tap once
more to stop. A latched session runs as long as you like.

## Live corrections

Off by default, behind **Live corrections** in the menu. With it on, a latched
session types the recognizer's running hypothesis as you speak and revises it
when later audio changes what an earlier word must have been — the text edits
itself in place rather than waiting for each sentence to commit.

Revision only ever reaches back over the uncommitted tail this app typed. The
moment you type or click anything, that text becomes yours and is never
backspaced over. Synthesized events are marked so the app does not mistake its
own typing for yours.

Live corrections and sentence rewriting do not combine: the rewrite takes
seconds, and by then you are still talking into the same tail. With live on,
only filler removal runs.

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
  `/Applications/Murmur.app`. Needed both to read the hotkey and to type.

The build is signed with an Apple Development identity. Ad-hoc signing does not
work here: TCC keys an ad-hoc signature on the binary hash, so every rebuild
silently voids both grants. If grants ever go stale anyway, clear them with
`tccutil reset Accessibility com.kirates.murmur` and re-add the app.

The menu bar item shows which grant is outstanding.

## Release build

```sh
./Scripts/package.sh
```

Produces `.dist/Murmur-<version>.zip`. The icon is generated from
`Scripts/make-icon.swift` at build time rather than checked in.

## Tests

```sh
swift test
```

Filler removal, gesture timing, audio conversion, and text chunking are
covered. The event tap, the synthetic paste, and the on-device model are
verified by hand: they need real permissions, a real keyboard, and real speech.

## How it fits together

| File | Does |
|---|---|
| `HotkeyMonitor` | Event tap on the modifier key, swallows it |
| `HotkeyGesture` | Pure state machine: hold, double-tap latch, tap to stop |
| `AudioCapture` | Mic tap, resampled to the analyzer's format |
| `Transcriber` | `SpeechAnalyzer` session, emits finalized segments |
| `Cleaner` | Regex disfluency removal, always on |
| `Reframer` | On-device rewrite, opt-in, distrusted by default |
| `LiveText` | Smallest edit from what is on screen to what is now believed |
| `InterruptionMonitor` | Notices the user typing or clicking; freezes revision |
| `Inserter` | Types the text as key events; never touches the clipboard |
| `DictationController` | Wires the above, owns permission state |
