import AppKit
import SwiftUI

@main
struct MurmurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var controller = DictationController()

    var body: some Scene {
        MenuBarExtra {
            Text(controller.statusText)

            if controller.needsAccessibility {
                Button("Open Accessibility Settings…") {
                    controller.openAccessibilitySettings()
                }
                Button("Check Again") {
                    controller.recheckPermissions()
                }
            }

            Divider()

            if let reason = controller.reframeUnavailableReason {
                Text(reason)
            } else {
                Toggle("Clean up sentences", isOn: $controller.reframeEnabled)
            }

            Divider()

            Button("Quit Murmur") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(systemName: controller.isRecording ? "mic.fill" : "mic")
                .task { controller.start() }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
