import AVFoundation
import XCTest
@testable import Murmur

final class AudioCaptureTests: XCTestCase {
    private func tone(format: AVAudioFormat, frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let channel = try XCTUnwrap(buffer.floatChannelData)
        for frame in 0..<Int(frames) {
            let value = Float(sin(2.0 * .pi * 440.0 * Double(frame) / format.sampleRate))
            for ch in 0..<Int(format.channelCount) {
                channel[ch][frame] = value
            }
        }
        return buffer
    }

    func testStreamingConversionPreservesTotalDuration() throws {
        let input = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
        let output = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let converter = try XCTUnwrap(AVAudioConverter(from: input, to: output))
        converter.primeMethod = .none

        let chunks = 10
        let framesPerChunk: AVAudioFrameCount = 4800
        var produced = 0
        for _ in 0..<chunks {
            let source = try tone(format: input, frames: framesPerChunk)
            let converted = try XCTUnwrap(AudioCapture.convert(source, using: converter, to: output))
            XCTAssertEqual(converted.format.sampleRate, 16000)
            produced += Int(converted.frameLength)
        }

        let expected = Int(framesPerChunk) * chunks / 3
        XCTAssertGreaterThan(produced, expected - Int(framesPerChunk))
        XCTAssertLessThanOrEqual(produced, expected)
    }

    func testDownmixesStereoToMono() throws {
        let input = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        let output = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let converter = try XCTUnwrap(AVAudioConverter(from: input, to: output))
        converter.primeMethod = .none

        let source = try tone(format: input, frames: 4410)
        let converted = try XCTUnwrap(AudioCapture.convert(source, using: converter, to: output))

        XCTAssertEqual(converted.format.channelCount, 1)
        XCTAssertGreaterThan(converted.frameLength, 0)
    }

    func testSilentInputStillProducesFrames() throws {
        let input = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
        let output = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let converter = try XCTUnwrap(AVAudioConverter(from: input, to: output))
        converter.primeMethod = .none

        let source = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: input, frameCapacity: 4800))
        source.frameLength = 4800

        let converted = try XCTUnwrap(AudioCapture.convert(source, using: converter, to: output))
        XCTAssertGreaterThan(converted.frameLength, 0)
    }
}
