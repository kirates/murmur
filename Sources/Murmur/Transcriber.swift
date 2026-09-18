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
    private var resolvedLocale: Locale?
    private var format: AVAudioFormat?
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var collector: Task<Void, Never>?
    private var segments: AsyncStream<String>.Continuation?

    /// How long to wait for the analyzer to flush after input closes.
    private static let finalizeTimeout: Duration = .seconds(10)

    init(locale: Locale = Locale(identifier: "en-US")) {
        self.locale = locale
    }

    var audioFormat: AVAudioFormat? { format }

    /// Resolves the locale, installs the model if needed, and negotiates an audio
    /// format. Idempotent: later calls return immediately once prepared.
    func prepare(onProgress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        if resolvedLocale != nil, format != nil { return }

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

        self.resolvedLocale = resolved
        self.format = format
    }

    /// A live dictation session: audio goes into `audio`, finalized text comes
    /// out of `segments` as the analyzer commits it.
    struct Session {
        let audio: AsyncStream<AnalyzerInput>.Continuation
        let segments: AsyncStream<String>
    }

    /// Opens a fresh analysis session.
    func beginUtterance() async throws -> Session {
        guard let resolvedLocale, let format else { throw TranscriberError.notPrepared }
        await discardUtterance()

        let module = SpeechTranscriber(locale: resolvedLocale, preset: .progressiveTranscription)
        // A latched session can run for hours. An unbounded buffer would grow
        // without limit if the analyzer ever fell behind the microphone; this
        // caps it at roughly twenty seconds of audio.
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(
            bufferingPolicy: .bufferingNewest(256))
        let (segmentStream, segmentContinuation) = AsyncStream<String>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [module])
        try await analyzer.prepareToAnalyze(in: format)
        try await analyzer.start(inputSequence: stream)

        collector = Task {
            defer { segmentContinuation.finish() }
            do {
                for try await result in module.results where result.isFinal {
                    let text = String(result.text.characters)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    segmentContinuation.yield(text)
                }
            } catch {
                return
            }
        }

        self.analyzer = analyzer
        self.continuation = continuation
        self.segments = segmentContinuation
        return Session(audio: continuation, segments: segmentStream)
    }

    /// Closes the session. The segment stream completes once the analyzer has
    /// flushed everything it was holding.
    func finishUtterance() async {
        continuation?.finish()
        continuation = nil

        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        analyzer = nil

        // A collector that never completes would strand the UI on
        // "Transcribing…" with no way back short of quitting.
        let collector = self.collector
        self.collector = nil
        if let collector {
            let guardTask = Task {
                try? await Task.sleep(for: Self.finalizeTimeout)
                collector.cancel()
            }
            await collector.value
            guardTask.cancel()
        }
        segments?.finish()
        segments = nil
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
        segments?.finish()
        segments = nil
    }
}
