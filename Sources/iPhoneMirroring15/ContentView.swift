import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var showingConnection = false
    @State private var hoveringWindowBar = false
    @State private var hoveredWindowButton: String?
    @State private var appWindow: NSWindow?

    var body: some View {
        VStack(spacing: 0) {
            windowBar
            GeometryReader { geometry in
                let screenSize = CGSize(
                    width: geometry.size.width - 8, height: geometry.size.height - 16)
                ZStack {
                    if showingConnection {
                        connectionView
                    } else if model.connected, let image = model.image {
                        RemoteScreen(image: image) { x, y, buttons in
                            model.pointer(x: x, y: y, buttons: buttons)
                        }
                        .frame(width: screenSize.width, height: screenSize.height)
                    } else {
                        phoneStatus
                    }
                }
                .frame(width: screenSize.width, height: screenSize.height)
                .clipShape(screenShape(screenSize))
                .overlay(screenShape(screenSize).stroke(Color.black.opacity(0.12), lineWidth: 1))
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
        .background(hoveringWindowBar ? Color(white: 0.96) : .clear)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
                .opacity(hoveringWindowBar ? 1 : 0)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            model.discover()
        }
        .onReceive(NotificationCenter.default.publisher(for: .connectRequested)) { _ in
            showingConnection = true
        }
    }

    private func screenShape(_ size: CGSize) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: min(size.width, size.height) * 0.05, style: .continuous)
    }

    private var windowBar: some View {
        ZStack {
            WindowDragHandle(
                onHover: { isHovered in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        hoveringWindowBar = isHovered
                    }
                },
                onWindow: { appWindow = $0 }
            )
            HStack(spacing: 8) {
                windowButton(
                    id: "close", color: .systemRed, symbol: "xmark"
                ) {
                    withWindow { $0.close() }
                }
                windowButton(
                    id: "minimize", color: .systemYellow, symbol: "minus"
                ) {
                    withWindow { $0.miniaturize(nil) }
                }
                windowButton(
                    id: "fullscreen", color: .systemGray, symbol: ""
                ) {
                    withWindow { $0.toggleFullScreen(nil) }
                }
                Spacer()
            }
            .padding(.leading, 16)
            .padding(.trailing, 20)
            .offset(y: 5)
            .opacity(hoveringWindowBar ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: hoveringWindowBar)
            .allowsHitTesting(hoveringWindowBar)
        }
        .frame(height: 28)
        .background(.clear)
    }

    private func windowButton(
        id: String, color: NSColor, symbol: String, action: @escaping () -> Void
    )
        -> some View
    {
        Button(action: action) {
            Circle()
                .fill(Color(color))
                .frame(width: 16, height: 16)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.black.opacity(0.55))
                        .opacity(hoveredWindowButton == nil ? 0 : 1)
                        .animation(.easeInOut(duration: 0.1), value: hoveredWindowButton == nil)
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if isHovering {
                hoveredWindowButton = id
            } else if hoveredWindowButton == id {
                hoveredWindowButton = nil
            }
        }
    }

    private func withWindow(_ action: (NSWindow) -> Void) {
        guard let window = appWindow else { return }
        action(window)
    }

    private var phoneStatus: some View {
        let connecting = model.busy || (model.connected && model.image == nil)
        return VStack(spacing: 18) {
            Spacer()
            Image(systemName: "iphone.gen3")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(Color(white: 0.68))
            Text(
                connecting
                    ? "Connecting…"
                    : (model.connectionError == nil ? "No iPhone Connected" : "Could Not Connect")
            )
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(Color(white: 0.28))
            Text(model.connectionError ?? "Connect to a iPhone device to begin.")
                .font(.system(size: 14))
                .foregroundStyle(Color(white: 0.32))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if !connecting {
                Button("Connect") { showingConnection = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(white: 0.25))
                    .padding(.horizontal, 25)
                    .padding(.vertical, 11)
                    .background(Color(white: 0.88), in: Capsule())
                    .padding(.top, 10)
            } else {
                ProgressView().tint(.gray).padding(.top, 10)
            }
            Spacer()
        }
        .background {
            Color(white: 0.96)
                .overlay {
                    WindowDragHandle(
                        onHover: { _ in },
                        onWindow: { appWindow = $0 },
                        skipsLeadingControls: false
                    )
                }
        }
    }

    private var connectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Connect to iPhone").font(.title3.weight(.semibold))
                Spacer()
                Button {
                    model.discover()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }.help("Refresh nearby devices")
            }
            Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if !model.discovered.isEmpty {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.discovered) { device in
                            HStack {
                                Label(device.name, systemImage: "iphone").lineLimit(1)
                                Spacer()
                                Button("Connect") {
                                    model.select(device)
                                    model.connect(device)
                                    showingConnection = false
                                }
                            }
                            .font(.callout)
                        }
                    }
                }
                .frame(maxHeight: 110)
            }
            VStack(alignment: .leading, spacing: 8) {
                TextField("Host name or IP address", text: $model.host)
                    .textFieldStyle(.roundedBorder)
                TextField("Port", text: $model.port)
                    .textFieldStyle(.roundedBorder)
                SecureField("VNC password (optional)", text: $model.password)
                    .textFieldStyle(.roundedBorder)
            }
            Spacer(minLength: 0)
            HStack {
                Button("Cancel") { showingConnection = false }
                Spacer()
                Button("Connect") {
                    model.connect()
                    showingConnection = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            Color(white: 0.96)
                .overlay {
                    WindowDragHandle(
                        onHover: { _ in },
                        onWindow: { appWindow = $0 },
                        skipsLeadingControls: false
                    )
                }
        }
        .preferredColorScheme(.light)
    }

}

private struct RemoteScreen: NSViewRepresentable {
    let image: NSImage
    let onPointer: (Int, Int, UInt8) -> Void
    func makeNSView(context: Context) -> ScreenView { ScreenView() }
    func updateNSView(_ view: ScreenView, context: Context) {
        view.image = image
        view.onPointer = onPointer
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    let onHover: (Bool) -> Void
    let onWindow: (NSWindow?) -> Void
    var skipsLeadingControls = true

    func makeNSView(context: Context) -> NSView {
        let view = DragView()
        view.onHover = onHover
        view.onWindow = onWindow
        view.skipsLeadingControls = skipsLeadingControls
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? DragView)?.onHover = onHover
        (view as? DragView)?.onWindow = onWindow
        (view as? DragView)?.skipsLeadingControls = skipsLeadingControls
    }

    private final class DragView: NSView {
        var onHover: ((Bool) -> Void)?
        var onWindow: ((NSWindow?) -> Void)?
        var skipsLeadingControls = true
        private var hasPointerMoved = false
        private var isHovering = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let localPoint = convert(point, from: superview)
            if skipsLeadingControls && localPoint.x < 96 { return nil }
            return super.hitTest(point)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(
                NSTrackingArea(
                    rect: .zero,
                    options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                    owner: self, userInfo: nil))
        }

        override func mouseEntered(with event: NSEvent) {
            guard hasPointerMoved else { return }
            setHovering(true)
        }
        override func mouseExited(with event: NSEvent) {
            guard hasPointerMoved else { return }
            setHovering(false)
        }
        override func mouseMoved(with event: NSEvent) {
            hasPointerMoved = true
            let point = convert(event.locationInWindow, from: nil)
            setHovering(bounds.contains(point))
        }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }

        private func setHovering(_ hovering: Bool) {
            guard hovering != isHovering else { return }
            isHovering = hovering
            window?.hasShadow = hovering
            window?.invalidateShadow()
            onHover?(hovering)
        }
    }
}

private final class ScreenView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var onPointer: ((Int, Int, UInt8) -> Void)?
    private var buttons: UInt8 = 0
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(
            in: NSRect(
                x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                width: size.width, height: size.height))
    }
    override func mouseDown(with event: NSEvent) {
        buttons = 1
        send(event)
    }
    override func mouseDragged(with event: NSEvent) { send(event) }
    override func mouseUp(with event: NSEvent) {
        buttons = 0
        send(event)
    }
    override func rightMouseDown(with event: NSEvent) { onPointer?(0, 0, 4) }
    override func rightMouseUp(with event: NSEvent) { onPointer?(0, 0, 0) }
    override func otherMouseDown(with event: NSEvent) { onPointer?(0, 0, 2) }
    override func otherMouseUp(with event: NSEvent) { onPointer?(0, 0, 0) }

    private func send(_ event: NSEvent) {
        guard let image else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let originX = (bounds.width - image.size.width * scale) / 2
        let originY = (bounds.height - image.size.height * scale) / 2
        let x = min(max(Int((point.x - originX) / scale), 0), Int(image.size.width) - 1)
        let y = min(max(Int((point.y - originY) / scale), 0), Int(image.size.height) - 1)
        onPointer?(x, y, buttons)
    }
}
