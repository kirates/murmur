import AVFoundation
import AppKit
import Foundation
import SwiftUI

@MainActor
final class DictationController: ObservableObject {
    enum State: Equatable {
        case installingModel(Double)
        case needsAccessibility
        case needsMicrophone
        case ready
        case recording
        case transcribing
        case failed(String)
    }

    @Published private(set) var state: State = .installingModel(0)

    private static let reframeDefaultsKey = "reframeEnabled"

    private let transcriber = Transcriber()
    private let capture = AudioCapture()
    private let hotkey = HotkeyMonitor()
    private let reframer = Reframer()

    @Published private(set) var reframeUnavailableReason: String?

    @Published var reframeEnabled: Bool = UserDefaults.standard.bool(forKey: DictationController.reframeDefaultsKey) {
        didSet {
            UserDefaults.standard.set(reframeEnabled, forKey: Self.reframeDefaultsKey)
            guard reframeEnabled else { return }
            Task { await reframer.prewarm() }
        }
    }

    var isRecording: Bool { state == .recording }

    var statusText: String {
        switch state {
        case .installingModel(let fraction):
            return "Downloading speech model… \(Int(fraction * 100))%"
        case .needsAccessibility:
            return "Needs Accessibility access"
        case .needsMicrophone:
            return "Needs microphone access"
        case .ready:
            return "Hold right ⌥ to dictate"
        case .recording:
            return "Listening…"
        case .transcribing:
            return "Transcribing…"
        case .failed(let message):
            return message
        }
    }

    var needsAccessibility: Bool { state == .needsAccessibility }

    func start() {
        hotkey.onPress = { [weak self] in self?.beginRecording() }
        hotkey.onRelease = { [weak self] in self?.endRecording() }

        Task { await bootstrap() }
    }

    func openAccessibilitySettings() {
        HotkeyMonitor.openAccessibilitySettings()
    }

    /// Re-runs the permission checks after the user has been to System Settings.
    func recheckPermissions() {
        Task { await bootstrap() }
    }

    private func bootstrap() async {
        guard await requestMicrophoneAccess() else {
            state = .needsMicrophone
            return
        }

        do {
            try await transcriber.prepare { [weak self] fraction in
                Task { @MainActor in
                    guard let self, case .installingModel = self.state else { return }
                    self.state = .installingModel(fraction)
                }
            }
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        switch await reframer.availability {
        case .available:
            reframeUnavailableReason = nil
            if reframeEnabled { await reframer.prewarm() }
        case .unavailable(let reason):
            reframeUnavailableReason = reason
        }

        guard HotkeyMonitor.hasAccessibilityPermission, hotkey.start() else {
            state = .needsAccessibility
            return
        }

        state = .ready
    }

    private func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    private func beginRecording() {
        guard state == .ready else { return }
        state = .recording

        Task {
            do {
                let sink = try await transcriber.beginUtterance()
                guard let format = await transcriber.audioFormat else {
                    throw TranscriberError.notPrepared
                }
                try capture.start(outputFormat: format, sink: sink)
            } catch {
                capture.stop()
                await transcriber.discardUtterance()
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func endRecording() {
        guard state == .recording else { return }
        state = .transcribing
        capture.stop()

        Task {
            let raw = await transcriber.finishUtterance()
            let text = await polish(raw)
            if !text.isEmpty {
                Inserter.insert(text)
            }
            if case .transcribing = state {
                state = .ready
            }
        }
    }

    /// Rules always run. The rewrite only runs when the user has asked for it and
    /// the model returned something trustworthy.
    private func polish(_ raw: String) async -> String {
        let cleaned = Cleaner.clean(raw)
        guard reframeEnabled, reframeUnavailableReason == nil else { return cleaned }
        return await reframer.reframe(cleaned) ?? cleaned
    }
}
