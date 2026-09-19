import Foundation

/// Works out the smallest edit that turns text already on screen into the text
/// the recognizer now believes was said.
enum LiveText {
    struct Edit: Equatable {
        /// Backspaces to send before typing. Counted in characters, because one
        /// backspace deletes one grapheme cluster.
        let backspaces: Int
        let insertion: String

        var isEmpty: Bool { backspaces == 0 && insertion.isEmpty }
    }

    static func edit(from current: String, to target: String) -> Edit {
        var shared = 0
        var currentIndex = current.startIndex
        var targetIndex = target.startIndex

        while currentIndex < current.endIndex,
              targetIndex < target.endIndex,
              current[currentIndex] == target[targetIndex] {
            shared += 1
            currentIndex = current.index(after: currentIndex)
            targetIndex = target.index(after: targetIndex)
        }

        return Edit(backspaces: current.count - shared,
                    insertion: String(target[targetIndex...]))
    }
}
