import AppKit
import CoreGraphics
import Foundation

/// Types text into the focused app by synthesizing key events that carry the
/// characters directly.
///
/// The clipboard is never touched. Borrowing and restoring it loses whatever the
/// user copies mid-dictation and races the paste it is trying to serve.
@MainActor
enum Inserter {
    /// Characters per synthesized event. Long strings are split because the
    /// event payload is bounded and very large payloads are dropped silently.
    static let chunkSize = 16
    /// Pause between chunks, so the focused app's input handling keeps up.
    static let chunkDelay: Duration = .milliseconds(6)

    /// Stamped on every event we synthesize, so InterruptionMonitor can tell our
    /// own typing apart from the user's.
    nonisolated static let eventMarker: Int64 = 0x4D75726D7572

    private static let deleteKeyCode: CGKeyCode = 51

    static func insert(_ text: String) async {
        guard !text.isEmpty else { return }

        let source = CGEventSource(stateID: .combinedSessionState)
        for chunk in chunks(of: text) {
            type(chunk, source: source)
            try? await Task.sleep(for: chunkDelay)
        }
    }

    /// Applies a revision: deletes what is no longer believed, types the rest.
    static func apply(_ edit: LiveText.Edit) async {
        guard !edit.isEmpty else { return }

        let source = CGEventSource(stateID: .combinedSessionState)
        for _ in 0..<edit.backspaces {
            press(Self.deleteKeyCode, source: source)
            try? await Task.sleep(for: chunkDelay)
        }
        await insert(edit.insertion)
    }

    private static func press(_ keyCode: CGKeyCode, source: CGEventSource?) {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        for event in [down, up] {
            event.setIntegerValueField(.eventSourceUserData, value: eventMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    nonisolated static func chunks(of text: String, size: Int = 16) -> [String] {
        guard size > 0 else { return [text] }
        var out: [String] = []
        var current = ""
        // Split on unicode scalars rather than characters so an emoji or a
        // combining sequence is never cut in half.
        for character in text {
            current.append(character)
            if current.unicodeScalars.count >= size {
                out.append(current)
                current = ""
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    private static func type(_ text: String, source: CGEventSource?) {
        var utf16 = Array(text.utf16)
        guard !utf16.isEmpty else { return }

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            return
        }

        down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)

        for event in [down, up] {
            event.setIntegerValueField(.eventSourceUserData, value: eventMarker)
            event.post(tap: .cghidEventTap)
        }
    }
}
