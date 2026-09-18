import Foundation

/// Turns raw key press and release events into recording commands.
///
/// Hold the key to dictate and release to stop. Tap it twice quickly to latch
/// recording on, then tap once more to stop. A short press cannot be told apart
/// from the first half of a double tap until the window expires, so recording
/// starts immediately and the decision to stop is deferred.
struct HotkeyGesture {
    enum Action: Equatable {
        case startRecording
        case stopRecording
        case none
    }

    enum Event: Equatable {
        case press(at: TimeInterval)
        case release(at: TimeInterval)
        case windowExpired(at: TimeInterval)
    }

    private enum State: Equatable {
        case idle
        case holding(since: TimeInterval)
        case awaitingSecondTap(since: TimeInterval)
        case latchArming
        case latched
        case latchStopping
    }

    /// A press shorter than this counts as a tap rather than a hold.
    static let tapThreshold: TimeInterval = 0.35
    /// How long to wait for the second tap of a double tap.
    static let doubleTapWindow: TimeInterval = 0.4

    private var state: State = .idle

    var isLatched: Bool {
        state == .latched || state == .latchArming || state == .latchStopping
    }

    /// Set when the caller must schedule a `windowExpired` event.
    private(set) var pendingWindowDeadline: TimeInterval?

    mutating func handle(_ event: Event) -> Action {
        pendingWindowDeadline = nil

        switch (state, event) {
        case (.idle, .press):
            guard case .press(let at) = event else { return .none }
            state = .holding(since: at)
            return .startRecording

        case (.holding(let since), .release(let at)):
            if at - since < Self.tapThreshold {
                state = .awaitingSecondTap(since: at)
                pendingWindowDeadline = at + Self.doubleTapWindow
                return .none
            }
            state = .idle
            return .stopRecording

        case (.awaitingSecondTap, .press):
            state = .latchArming
            return .none

        case (.awaitingSecondTap(let since), .windowExpired(let at)):
            guard at >= since + Self.doubleTapWindow else {
                pendingWindowDeadline = since + Self.doubleTapWindow
                return .none
            }
            state = .idle
            return .stopRecording

        case (.latchArming, .release):
            state = .latched
            return .none

        case (.latched, .press):
            state = .latchStopping
            return .none

        case (.latchStopping, .release):
            state = .idle
            return .stopRecording

        default:
            return .none
        }
    }

    /// Drops any latch or pending window, for when recording is aborted elsewhere.
    mutating func reset() {
        state = .idle
        pendingWindowDeadline = nil
    }
}
