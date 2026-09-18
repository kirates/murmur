import AVFoundation
import Foundation
import Speech

enum TranscriberError: LocalizedError {
    case unavailable
    case unsupportedLocale(Locale)
    case noCompatibleFormat
    case notPrepared

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "On-device speech transcription is not available on this Mac."
        case .unsupportedLocale(let locale):
            return "No speech model available for \(locale.identifier)."
        case .noCompatibleFormat:
            return "Could not negotiate an audio format with the speech analyzer."
        case .notPrepared:
            return "Transcriber used before its model finished installing."
        }
    }
}

actor Transcriber {
    private let locale: Locale
    private var module: SpeechTranscriber?
    private var format: AVAudioFormat?
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var collector: Task<String, Never>?

    init(locale: Locale = Locale(identifier: "en-US")) {
        self.locale = locale
    }

    var audioFormat: AVAudioFormat? { format }

    /// Resolves the locale, installs the model if needed, and negotiates an audio
    /// format. Idempotent: later calls return immediately once prepared.
    func prepare(onProgress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        if module != nil, format != nil { return }

        guard SpeechTranscriber.isAvailable else { throw TranscriberError.unavailable }
        guard let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw TranscriberError.unsupportedLocale(locale)
        }

        let module = SpeechTranscriber(locale: resolved, preset: .transcription)

        try await AssetInventory.reserve(locale: resolved)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            let observation = request.progress.observe(\.fractionCompleted, options: [.initial, .new]) { progress, _ in
                onProgress(progress.fractionCompleted)
            }
            defer { observation.invalidate() }
            try await request.downloadAndInstall()
        }
        onProgress(1.0)

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw TranscriberError.noCompatibleFormat
        }

        self.module = module
        self.format = format
    }

    /// Opens a fresh analysis session and hands back the sink that audio buffers
    /// should be yielded into.
    func beginUtterance() async throws -> AsyncStream<AnalyzerInput>.Continuation {
        guard let module, let format else { throw TranscriberError.notPrepared }
        await discardUtterance()

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [module])
        try await analyzer.prepareToAnalyze(in: format)
        try await analyzer.start(inputSequence: stream)

        collector = Task {
            var text = AttributedString()
            do {
                for try await result in module.results where result.isFinal {
                    text.append(result.text)
                }
            } catch {
                return String(text.characters)
            }
            return String(text.characters)
        }

        self.analyzer = analyzer
        self.continuation = continuation
        return continuation
    }

    /// Closes the session and returns everything that was transcribed.
    func finishUtterance() async -> String {
        continuation?.finish()
        continuation = nil

        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        analyzer = nil

        let text = await collector?.value ?? ""
        collector = nil
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func discardUtterance() async {
        continuation?.finish()
        continuation = nil
        if let analyzer {
            await analyzer.cancelAndFinishNow()
        }
        analyzer = nil
        collector?.cancel()
        collector = nil
    }
}
