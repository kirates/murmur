import Foundation

/// Deletes disfluencies from a dictated transcript. Every rule here only ever
/// removes tokens that carry no meaning, so the result can be pasted into a
/// shell command or a prompt without changing what was said.
enum Cleaner {
    /// Sounds that are never words.
    private static let fillers = [
        "um", "umm", "ummm", "uh", "uhh", "uhhh", "uhm", "er", "erm", "err",
        "ah", "ahh", "hmm", "hm", "mm", "mhm", "mmhmm",
    ]

    /// Openers that carry no content at the head of an utterance.
    private static let leadingMarkers = [
        "so", "okay", "ok", "alright", "all right", "well", "yeah", "yep", "right",
    ]

    /// Tags tacked onto the end while thinking.
    private static let trailingTags = [
        "right", "you know", "yeah", "okay", "ok",
    ]

    /// Words English legitimately doubles, exempt from stutter collapsing.
    private static let legitimateDoubles: Set<String> = ["had", "that"]

    static func clean(_ text: String) -> String {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return original }

        var result = original
        result = removeFillers(result)
        result = collapseStutters(result)
        result = removeLeadingMarkers(result)
        result = removeTrailingTags(result)
        result = tidy(result)

        return result.isEmpty ? original : result
    }

    private static func removeFillers(_ text: String) -> String {
        let alternatives = fillers.joined(separator: "|")
        let pattern = "(?i)(?<![\\p{L}'])(?:\(alternatives))(?![\\p{L}'])[,.]?"
        var out = replace(text, pattern: pattern, with: " ")
        out = replace(out, pattern: "(?i)(?<![\\p{L}'])you know(?![\\p{L}'])[,.]?", with: " ")
        return out
    }

    private static func collapseStutters(_ text: String) -> String {
        let pattern = "(?i)(?<![\\p{L}'])(\\p{L}+)(\\s+\\1)+(?![\\p{L}'])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        let source = text as NSString
        var out = ""
        var cursor = 0

        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let word = source.substring(with: match.range(at: 1))
            out += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            out += legitimateDoubles.contains(word.lowercased())
                ? source.substring(with: match.range)
                : word
            cursor = match.range.location + match.range.length
        }
        out += source.substring(from: cursor)
        return out
    }

    private static func removeLeadingMarkers(_ text: String) -> String {
        let alternatives = leadingMarkers.joined(separator: "|")
        let pattern = "(?i)^\\s*(?:(?:\(alternatives))\\b[,\\s]+)+"
        return replace(text, pattern: pattern, with: "")
    }

    private static func removeTrailingTags(_ text: String) -> String {
        let alternatives = trailingTags.joined(separator: "|")
        let pattern = "(?i)[,\\s]+(?:\(alternatives))\\s*([.?!]*)\\s*$"
        return replace(text, pattern: pattern, with: "$1")
    }

    private static func tidy(_ text: String) -> String {
        var out = replace(text, pattern: "\\s+", with: " ")
        out = replace(out, pattern: "\\s+([,.?!;:])", with: "$1")
        out = replace(out, pattern: "([,.?!;:])(?=[\\p{L}])", with: "$1 ")
        out = replace(out, pattern: "^[,.\\s]+", with: "")
        out = replace(out, pattern: "[,;:]+(\\s*[.?!]*)\\s*$", with: "$1")
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let first = out.first, first.isLowercase else { return out }
        return out.replacingCharacters(in: out.startIndex...out.startIndex, with: first.uppercased())
    }

    private static func replace(_ text: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
