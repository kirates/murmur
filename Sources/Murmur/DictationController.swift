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
    private var gesture = HotkeyGesture()
    private var windowTimer: DispatchWorkItem?
    private var segmentTask: Task<Void, Never>?
    private var buffered: [String] = []
    private var streaming = false
    /// Serialises polishing and pasting so segments land in the order spoken.
    private var insertionChain: Task<Void, Never>?

    @Published private(set) var reframeUnavailableReason: String?

    @Published var reframeEnabled: Bool = UserDefaults.standard.bool(forKey: DictationController.reframeDefaultsKey) {
        didSet {
            UserDefaults.standard.set(reframeEnabled, forKey: Self.reframeDefaultsKey)
            guard reframeEnabled else { return }
            Task { await reframer.prewarm() }
        }
    }

    var isRecording: Bool { state == .recording }
    var isLatched: Bool { gesture.isLatched }

    var statusText: String {
        switch state {
        case .installingModel(let fraction):
            return "Downloading speech model… \(Int(fraction * 100))%"
        case .needsAccessibility:
            return "Needs Accessibility access"
        case .needsMicrophone:
            return "Needs microphone access"
        case .ready:
            return "Hold right ⌥ to dictate, double-tap to latch"
        case .recording:
            return gesture.isLatched ? "Listening — tap right ⌥ to stop" : "Listening…"
        case .transcribing:
            return "Transcribing…"
        case .failed(let message):
            return message
        }
    }

    var needsAccessibility: Bool { state == .needsAccessibility }

    var needsMicrophone: Bool { state == .needsMicrophone }

    func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }

    func start() {
        hotkey.onPress = { [weak self] in
            self?.apply(.press(at: ProcessInfo.processInfo.systemUptime))
        }
        hotkey.onRelease = { [weak self] in
            self?.apply(.release(at: ProcessInfo.processInfo.systemUptime))
        }

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

    private func apply(_ event: HotkeyGesture.Event) {
        let action = gesture.handle(event)
        scheduleWindowTimer()

        switch action {
        case .startRecording: beginRecording()
        case .stopRecording: endRecording()
        case .none: break
        }

        // The latch engages part way through a recording that began as a hold.
        // Everything buffered so far is flushed, and later segments go straight
        // out as the analyzer commits them.
        if gesture.isLatched, !streaming, state == .recording {
            streaming = true
            flushBuffer()
        }
    }

    private func scheduleWindowTimer() {
        windowTimer?.cancel()
        windowTimer = nil

        guard let deadline = gesture.pendingWindowDeadline else { return }
        let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)

        let work = DispatchWorkItem { [weak self] in
            self?.apply(.windowExpired(at: ProcessInfo.processInfo.systemUptime))
        }
        windowTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func beginRecording() {
        guard state == .ready else { return }
        state = .recording

        buffered = []
        streaming = false

        Task {
            do {
                let session = try await transcriber.beginUtterance()
                guard let format = await transcriber.audioFormat else {
                    throw TranscriberError.notPrepared
                }
                segmentTask = Task { [weak self] in
                    for await segment in session.segments {
                        await self?.receive(segment)  // hop to the main actor
                    }
                }
                try capture.start(outputFormat: format, sink: session.audio)
            } catch {
                capture.stop()
                segmentTask?.cancel()
                segmentTask = nil
                await transcriber.discardUtterance()
                gesture.reset()
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func endRecording() {
        guard state == .recording else { return }
        state = .transcribing
        capture.stop()

        Task {
            await transcriber.finishUtterance()
            await segmentTask?.value
            segmentTask = nil

            flushBuffer()
            streaming = false
            await insertionChain?.value
            insertionChain = nil

            if case .transcribing = state {
                state = .ready
            }
        }
    }

    /// A finalized segment arrived. In a latched session it is pasted straight
    /// away; otherwise it waits for the end of the utterance so the rewrite can
    /// see the whole passage.
    private func receive(_ segment: String) {
        guard streaming else {
            buffered.append(segment)
            return
        }
        enqueue(segment, trailingSpace: true)
    }

    private func flushBuffer() {
        let pending = buffered.joined(separator: " ")
        buffered = []
        guard !pending.isEmpty else { return }
        enqueue(pending, trailingSpace: streaming)
    }

    private func enqueue(_ raw: String, trailingSpace: Bool) {
        let previous = insertionChain
        insertionChain = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            let text = await self.polish(raw)
            guard !text.isEmpty else { return }
            Inserter.insert(trailingSpace ? text + " " : text)
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
