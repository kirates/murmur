import AppKit
import CoreGraphics
import Foundation

/// Puts text into the focused app by borrowing the pasteboard, synthesizing a
/// paste, and putting back what was there before.
enum Inserter {
    static let restoreDelay: TimeInterval = 0.6
    private static let commandVKeyCode: CGKeyCode = 9

    static func insert(_ text: String, restoreDelay: TimeInterval = Inserter.restoreDelay) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        let saved = snapshot(of: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        paste()

        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
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
