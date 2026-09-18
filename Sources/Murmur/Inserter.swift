import AppKit
import CoreGraphics
import Foundation

/// Puts text into the focused app by borrowing the pasteboard, synthesizing a
/// paste, and putting back what was there before.
@MainActor
enum Inserter {
    static let restoreDelay: TimeInterval = 0.6
    private static let commandVKeyCode: CGKeyCode = 9

    /// Identifies the most recent insert, so a restore scheduled by an earlier
    /// one does not wipe out text a later one just pasted.
    private static var generation = 0
    /// The user's own clipboard, captured once at the head of a burst. Later
    /// inserts must not snapshot the text we ourselves pasted.
    private static var pendingRestore: [[NSPasteboard.PasteboardType: Data]]?

    static func insert(_ text: String, restoreDelay: TimeInterval? = nil) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        if pendingRestore == nil {
            pendingRestore = snapshot(of: pasteboard)
        }

        generation += 1
        let mine = generation

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        paste()

        DispatchQueue.main.asyncAfter(deadline: .now() + (restoreDelay ?? Self.restoreDelay)) {
            guard generation == mine, let saved = pendingRestore else { return }
            pendingRestore = nil
            restore(saved, to: pasteboard)
        }
    }

    static func snapshot(of pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    contents[type] = data
                }
            }
            return contents
        }
    }

    static func restore(_ snapshot: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }

        let items = snapshot.map { contents -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in contents {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }

    private static func paste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: commandVKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: commandVKeyCode, keyDown: false) else {
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
