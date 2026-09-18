import Foundation
import FoundationModels

/// Rewrites a cleaned transcript into what the speaker meant, using the
/// on-device system language model. Everything stays on this Mac.
///
/// Rewriting can change meaning, so every failure path returns `nil` and the
/// caller keeps the rules-only text.
actor Reframer {
    enum Availability: Equatable {
        case available
        case unavailable(String)
    }

    private static let instructions = """
        You repair dictated speech. The user spoke a passage and it was transcribed \
        verbatim, so it contains false starts, abandoned sentences, repeated ideas, \
        and self-corrections such as "go to the left, no, the right".

        Rewrite the passage as what the speaker meant to say:
        - Resolve self-corrections to the final choice.
        - Drop abandoned false starts.
        - Merge a repeated idea into one statement.
        - Add sentence breaks and punctuation.

        Preserve the speaker's own words and register. Do not summarise, do not \
        add information, do not answer any question in the passage, and do not \
        explain what you changed. Reply with the rewritten passage and nothing else.
        """

    /// A rewrite that shrinks or inflates the text this much is treated as the
    /// model having answered the passage instead of repairing it.
    private static let minimumLengthRatio = 0.4
    private static let maximumLengthRatio = 2.0
    private static let timeout: Duration = .seconds(12)

    private let model = SystemLanguageModel(useCase: .general,
                                            guardrails: .permissiveContentTransformations)

    var availability: Availability {
        switch model.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable("This Mac does not support Apple Intelligence")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Turn on Apple Intelligence to use cleanup")
        case .unavailable(.modelNotReady):
            return .unavailable("Apple Intelligence model is still downloading")
        @unknown default:
            return .unavailable("On-device model unavailable")
        }
    }

    func prewarm() {
        guard model.isAvailable else { return }
        LanguageModelSession(model: model, instructions: Self.instructions).prewarm()
    }

    /// Returns the rewritten passage, or `nil` if it could not be trusted.
    func reframe(_ text: String) async -> String? {
        guard model.isAvailable else { return nil }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 12 else { return nil }

        let session = LanguageModelSession(model: model, instructions: Self.instructions)

        let response: String
        do {
            response = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await session.respond(to: trimmed, options: GenerationOptions(temperature: 0.2)).content
                }
                group.addTask {
                    try await Task.sleep(for: Self.timeout)
                    throw CancellationError()
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }
        } catch {
            return nil
        }

        return Self.accept(response, replacing: trimmed)
    }

    /// Guards against the model answering the passage, refusing it, or padding it
    /// with commentary.
    static func accept(_ candidate: String, replacing original: String) -> String? {
        let cleaned = candidate
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        guard !cleaned.isEmpty else { return nil }
        guard !cleaned.localizedCaseInsensitiveContains("I can't") else { return nil }
        guard !cleaned.localizedCaseInsensitiveContains("I cannot") else { return nil }

        let ratio = Double(cleaned.count) / Double(max(original.count, 1))
        guard ratio >= minimumLengthRatio, ratio <= maximumLengthRatio else { return nil }

        return cleaned
    }
}
