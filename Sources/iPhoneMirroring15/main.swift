import AppKit
import SwiftUI

@main
struct iPhoneMirroring15App: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .background(.clear)
                .overlay(WindowChrome().frame(width: 0, height: 0))
        }
        .defaultSize(width: 360, height: 672)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {}
            CommandMenu("Connection") {
                Button("Connect to iPhone…") {
                    NotificationCenter.default.post(name: .connectRequested, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

extension Notification.Name {
    static let connectRequested = Notification.Name("connectRequested")
}

struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ChromeView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class ChromeView: NSView {
        private var configured = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !configured, let window else { return }
            configured = true
            window.alphaValue = 0
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.acceptsMouseMovedEvents = true
            window.contentView?.wantsLayer = true
            window.contentView?.layer?.cornerRadius = 18
            window.contentView?.layer?.cornerCurve = .continuous
            window.contentView?.layer?.masksToBounds = true
            DispatchQueue.main.async {
                window.styleMask = [
                    .borderless, .resizable, .closable, .miniaturizable,
                ]
                window.collectionBehavior.insert(.fullScreenPrimary)
                window.isMovableByWindowBackground = false
                window.minSize = NSSize(width: 270, height: 512)
                window.aspectRatio = NSSize(width: 360, height: 672)
                window.setContentSize(NSSize(width: 360, height: 672))
                window.center()
                window.alphaValue = 1
            }
        }
    }
}
