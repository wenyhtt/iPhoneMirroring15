import AppKit
import CommonCrypto
import Network

final class RFBConnection {
    enum Event { case connected(String?), frame(NSImage), failed(String) }
    private let host: String
    private let port: UInt16
    private let password: String
    private let endpoint: NWEndpoint?
    private let onEvent: (Event) -> Void
    private let queue = DispatchQueue(label: "rfb.connection")
    private var connection: NWConnection?
    private var bytes = Data()
    private var stage = 0
    private var width = 0
    private var height = 0
    private var nameLength = 0
    private var pixels = Data()
    private var closed = false

    init(host: String, port: UInt16, password: String, endpoint: NWEndpoint? = nil, onEvent: @escaping (Event) -> Void) {
        self.host = host; self.port = port; self.password = password; self.endpoint = endpoint; self.onEvent = onEvent
    }

    func connect() {
        let connection: NWConnection
        if let endpoint { connection = NWConnection(to: endpoint, using: .tcp) }
        else { connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp) }
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state { self?.fail(error.localizedDescription) }
        }
        connection.start(queue: queue)
        receive()
    }

    func disconnect() {
        queue.async { [weak self] in
            guard let self else { return }
            self.closed = true
            self.connection?.cancel()
            self.connection = nil
        }
    }

    func pointer(x: Int, y: Int, buttons: UInt8) {
        queue.async { [weak self] in
            guard let self, self.width > 0, self.height > 0 else { return }
            self.send(Data([5, buttons]) + be16(UInt16(max(0, min(self.width - 1, x)))) + be16(UInt16(max(0, min(self.height - 1, y)))))
        }
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data { self.bytes.append(data); self.parse() }
            if let error { self.fail(error.localizedDescription); return }
            if complete { self.fail("The VNC server closed the connection"); return }
            self.receive()
        }
    }

    private func parse() {
        while true {
            switch stage {
            case 0:
                guard bytes.count >= 12 else { return }
                guard String(data: bytes.prefix(4), encoding: .ascii)?.hasPrefix("RFB ") == true else { fail("Not an RFB/VNC server"); return }
                consume(12); send(Data("RFB 003.008\n".utf8)); stage = 1
            case 1:
                guard bytes.count >= 1 else { return }
                let count = Int(bytes[0])
                guard count > 0, bytes.count >= count + 1 else { if count == 0 { fail("VNC server rejected the connection"); return }; return }
                let types = Array(bytes[1...count]); consume(count + 1)
                let security: UInt8 = password.isEmpty && types.contains(1) ? 1 : (types.contains(2) ? 2 : (types.contains(1) ? 1 : 0))
                guard security != 0 else { fail("Unsupported VNC authentication"); return }
                send(Data([security])); stage = security == 2 ? 2 : 3
            case 2:
                guard bytes.count >= 16 else { return }
                let challenge = Data(bytes.prefix(16)); consume(16)
                guard let response = vncResponse(challenge, password: password) else { fail("VNC password encryption failed"); return }
                send(response); stage = 3
            case 3:
                guard bytes.count >= 4 else { return }
                let result = read32(bytes, 0); consume(4)
                guard result == 0 else { fail("VNC authentication failed"); return }
                send(Data([1]))
                stage = 4
            case 4:
                guard bytes.count >= 24 else { return }
                width = Int(read16(bytes, 0)); height = Int(read16(bytes, 2)); nameLength = Int(read32(bytes, 20))
                guard width > 0, height > 0, width <= 8192, height <= 8192, width * height <= 16_000_000 else { fail("Invalid framebuffer dimensions"); return }
                guard nameLength <= 4096 else { fail("Invalid desktop name"); return }
                guard bytes.count >= 24 + nameLength else { return }
                consume(24 + nameLength)
                pixels = Data(count: width * height * 4)
                let format = Data([0, 0, 0, 0, 32, 24, 0, 1]) + be16(255) + be16(255) + be16(255) + Data([16, 8, 0, 0, 0, 0])
                let encodings = Data([2, 0]) + be16(2) + be32(0) + be32(UInt32(bitPattern: -223))
                send(format + encodings + framebufferRequest())
                stage = 5
                let resolvedHost: String?
                if case let .hostPort(host, _) = connection?.currentPath?.remoteEndpoint { resolvedHost = "\(host)" }
                else { resolvedHost = nil }
                onEvent(.connected(resolvedHost))
            case 5:
                guard bytes.count >= 1 else { return }
                if bytes[0] == 0 {
                    guard bytes.count >= 4 else { return }
                    let count = Int(read16(bytes, 2)); consume(4)
                    stage = 6; pendingRects = count
                } else if bytes[0] == 1 {
                    guard bytes.count >= 6 else { return }
                    let length = Int(read16(bytes, 4)) * 6
                    guard bytes.count >= 6 + length else { return }
                    consume(6 + length)
                } else if bytes[0] == 2 {
                    consume(1)
                } else if bytes[0] == 3 {
                    guard bytes.count >= 8 else { return }
                    let length = Int(read32(bytes, 4))
                    guard bytes.count >= 8 + length else { return }
                    consume(8 + length)
                } else { fail("Unsupported VNC server message"); return }
            case 6:
                if pendingRects == 0 {
                    stage = 5
                    send(framebufferRequest())
                    emitFrame()
                    continue
                }
                guard bytes.count >= 12 else { return }
                let x = Int(read16(bytes, 0)), y = Int(read16(bytes, 2))
                let w = Int(read16(bytes, 4)), h = Int(read16(bytes, 6))
                let encoding = Int32(bitPattern: read32(bytes, 8))
                if encoding == -223 {
                    consume(12); width = w; height = h
                    guard width > 0, height > 0, width <= 8192, height <= 8192, width * height <= 16_000_000 else { fail("Invalid framebuffer dimensions"); return }
                    pixels = Data(count: width * height * 4); pendingRects -= 1
                } else if encoding == 0 {
                    guard w > 0, h > 0, x >= 0, y >= 0, x + w <= width, y + h <= height else { fail("Framebuffer rectangle is out of bounds"); return }
                    let length = w * h * 4
                    guard bytes.count >= 12 + length else { return }
                    consume(12)
                    for row in 0..<h {
                        let source = row * w * 4
                        let destination = ((y + row) * width + x) * 4
                        pixels.replaceSubrange(destination..<(destination + w * 4), with: bytes[source..<(source + w * 4)])
                    }
                    consume(length); pendingRects -= 1
                } else { fail("Server selected an unsupported framebuffer encoding"); return }
            default: return
            }
        }
    }

    private var pendingRects = 0
    private func consume(_ count: Int) { bytes = Data(bytes.dropFirst(count)) }
    private func framebufferRequest() -> Data { Data([3, 1]) + be16(0) + be16(0) + be16(UInt16(width)) + be16(UInt16(height)) }
    private func send(_ data: Data) { connection?.send(content: data, completion: .contentProcessed { [weak self] error in if let error { self?.fail(error.localizedDescription) } }) }
    private func fail(_ message: String) {
        guard !closed else { return }; closed = true; connection?.cancel(); onEvent(.failed(message))
    }
    private func emitFrame() {
        var rgbx = Data(count: pixels.count)
        pixels.withUnsafeBytes { source in
            rgbx.withUnsafeMutableBytes { destination in
                guard let src = source.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let dst = destination.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                for offset in stride(from: 0, to: pixels.count, by: 4) {
                    dst[offset] = src[offset + 2]
                    dst[offset + 1] = src[offset + 1]
                    dst[offset + 2] = src[offset]
                    dst[offset + 3] = 255
                }
            }
        }
        guard let provider = CGDataProvider(data: rgbx as CFData), let color = CGColorSpace(name: CGColorSpace.sRGB),
              let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                    space: color, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return }
        onEvent(.frame(NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))))
    }
}

private func be16(_ value: UInt16) -> Data { Data([UInt8(value >> 8), UInt8(value & 255)]) }
private func be32(_ value: UInt32) -> Data { Data([UInt8(value >> 24), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)]) }
private func read16(_ data: Data, _ offset: Int) -> UInt16 { UInt16(data[offset]) << 8 | UInt16(data[offset + 1]) }
private func read32(_ data: Data, _ offset: Int) -> UInt32 { UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16 | UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3]) }

private func vncResponse(_ challenge: Data, password: String) -> Data? {
    var key = Array(password.utf8.prefix(8)) + Array(repeating: 0, count: max(0, 8 - password.utf8.count))
    key = key.map { value in var result: UInt8 = 0; for bit in 0..<8 { result |= ((value >> bit) & 1) << (7 - bit) }; return result }
    var output = [UInt8](repeating: 0, count: 16)
    var moved = 0
    let status = CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmDES), CCOptions(kCCOptionECBMode), key, kCCKeySizeDES, nil, Array(challenge), 16, &output, 16, &moved)
    return status == kCCSuccess ? Data(output) : nil
}
