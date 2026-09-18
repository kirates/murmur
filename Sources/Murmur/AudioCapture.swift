import AVFoundation
import Foundation
import Speech

enum AudioCaptureError: LocalizedError {
    case noConverter(from: AVAudioFormat, to: AVAudioFormat)

    var errorDescription: String? {
        switch self {
        case .noConverter(let from, let to):
            return "Cannot convert microphone audio from \(from) to \(to)."
        }
    }
}

/// Pulls microphone audio off the input node, resamples it to whatever format the
/// speech analyzer negotiated, and yields it into an `AnalyzerInput` sink.
final class AudioCapture {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var running = false

    func start(outputFormat: AVAudioFormat,
               sink: AsyncStream<AnalyzerInput>.Continuation) throws {
        guard !running else { return }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioCaptureError.noConverter(from: inputFormat, to: outputFormat)
        }
        converter.primeMethod = .none
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            guard let converted = Self.convert(buffer, using: converter, to: outputFormat) else { return }
            sink.yield(AnalyzerInput(buffer: converted))
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.converter = nil
            throw error
        }
        running = true
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter?.reset()
        converter = nil
        running = false
    }

    static func convert(_ buffer: AVAudioPCMBuffer,
                        using converter: AVAudioConverter,
                        to outputFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return nil
        }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard error == nil, status != .error, output.frameLength > 0 else { return nil }
        return output
    }
}
