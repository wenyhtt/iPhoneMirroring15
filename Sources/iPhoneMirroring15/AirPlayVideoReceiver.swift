import AppKit

final class AirPlayVideoStream {
    private var receiver: OpaquePointer?
    private let onFrame: (NSImage) -> Void
    private let onError: (String) -> Void
    private let frameLock = NSLock()
    private var frameDeliveryPending = false

    init(onFrame: @escaping (NSImage) -> Void, onError: @escaping (String) -> Void) {
        self.onFrame = onFrame
        self.onError = onError
    }

    func start() throws -> Int32 {
        var port: Int32 = 0
        var errorMessage: UnsafeMutablePointer<CChar>?
        let context = Unmanaged.passUnretained(self).toOpaque()
        receiver = airplay_video_start(Self.frameCallback, Self.errorCallback, context, &port, &errorMessage)
        guard receiver != nil else {
            let message = errorMessage.map { String(cString: $0) } ?? "Could not start the AirPlay video receiver"
            airplay_video_free_error(errorMessage)
            throw NSError(domain: "AirPlayVideo", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return port
    }

    func stop() {
        guard let receiver else { return }
        airplay_video_stop(receiver)
        self.receiver = nil
    }

    deinit { stop() }

    private func receiveFrame(_ bytes: UnsafePointer<UInt8>, width: Int32, height: Int32, stride: Int32) {
        guard width > 0, height > 0, stride >= width * 4 else { return }
        frameLock.lock()
        guard !frameDeliveryPending else { frameLock.unlock(); return }
        frameDeliveryPending = true
        frameLock.unlock()

        let data = Data(bytes: bytes, count: Int(stride) * Int(height))
        guard let provider = CGDataProvider(data: data as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let cgImage = CGImage(width: Int(width), height: Int(height), bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: Int(stride), space: colorSpace,
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            frameLock.lock()
            frameDeliveryPending = false
            frameLock.unlock()
            return
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: Int(width), height: Int(height)))
        DispatchQueue.main.async {
            self.onFrame(image)
            self.frameLock.lock()
            self.frameDeliveryPending = false
            self.frameLock.unlock()
        }
    }

    private func reportError(_ message: String) {
        DispatchQueue.main.async { self.onError(message) }
    }

    private static let frameCallback: AirPlayVideoFrameCallback = { bytes, width, height, stride, context in
        guard let bytes, let context else { return }
        Unmanaged<AirPlayVideoStream>.fromOpaque(context).takeUnretainedValue()
            .receiveFrame(bytes, width: width, height: height, stride: stride)
    }

    private static let errorCallback: AirPlayVideoErrorCallback = { message, context in
        guard let message, let context else { return }
        Unmanaged<AirPlayVideoStream>.fromOpaque(context).takeUnretainedValue()
            .reportError(String(cString: message))
    }
}
