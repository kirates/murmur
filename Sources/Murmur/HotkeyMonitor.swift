import AppKit
import CoreGraphics
import Foundation

/// Watches for a single modifier key held down, and swallows it so the key never
/// reaches the focused app.
final class HotkeyMonitor {
    static let rightOptionKeyCode: Int64 = 61

    private let keyCode: Int64
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var isDown = false

    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}

    init(keyCode: Int64 = HotkeyMonitor.rightOptionKeyCode) {
        self.keyCode = keyCode
    }

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.flagsChanged.rawValue),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
        isDown = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard type == .flagsChanged,
              event.getIntegerValueField(.keyboardEventKeycode) == keyCode else {
            return Unmanaged.passUnretained(event)
        }

        let pressed = event.flags.contains(.maskAlternate)
        guard pressed != isDown else { return nil }
        isDown = pressed

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            pressed ? self.onPress() : self.onRelease()
        }

        return nil
    }
}
