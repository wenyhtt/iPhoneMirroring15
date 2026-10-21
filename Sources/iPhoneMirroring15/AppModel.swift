import AppKit
import Combine
import Darwin
import Network
import Security

struct SavedDevice: Codable, Identifiable, Hashable {
    var id: String { "\(host):\(port)" }
    var name: String
    var host: String
    var port: UInt16
}

final class AppModel: ObservableObject {
    @Published var devices: [SavedDevice] = []
    @Published var discovered: [SavedDevice] = []
    @Published var selected: SavedDevice?
    @Published var host = ""
    @Published var port = "5901"
    @Published var password = ""
    @Published var status = "Find a device or enter its address"
    @Published var connectionError: String?
    @Published var image: NSImage?
    @Published var framebufferWidth = 0
    @Published var framebufferHeight = 0
    @Published var connected = false
    @Published var busy = false
    @Published var airPlayError: String?

    private var browser: NWBrowser?
    private var connection: RFBConnection?
    private var serviceEndpoints: [String: NWEndpoint] = [:]
    private var videoReceiver: AirPlayVideoStream?
    private var uxplayProcess: Process?
    private var uxplayErrorOutput = ""
    private let uxplayErrorLock = NSLock()
    private var isShuttingDown = false

    init() {
        configureBundledGStreamer()
        devices = (try? JSONDecoder().decode([SavedDevice].self, from: UserDefaults.standard.data(forKey: "devices") ?? Data())) ?? []
        startAirPlay()
        discover()
        if let lastID = UserDefaults.standard.string(forKey: "lastConnectedDevice"),
           let device = devices.first(where: { $0.id == lastID }) ?? devices.first {
            select(device)
            connect(device)
        }
    }

    func discover() {
        browser?.cancel()
        let browser = NWBrowser(for: .bonjour(type: "_rfb._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap { result -> (SavedDevice, NWEndpoint)? in
                guard case let .service(name, _, domain, _) = result.endpoint else { return nil }
                return (SavedDevice(name: name, host: "\(name).\(domain)", port: 5901), result.endpoint)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.discovered = found.map(\.0)
                self.serviceEndpoints = Dictionary(found.map { ($0.0.id, $0.1) }, uniquingKeysWith: { first, _ in first })
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state { DispatchQueue.main.async { self?.status = "Discovery failed: \(error.localizedDescription)" } }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    func connect(_ device: SavedDevice? = nil) {
        var target = device ?? SavedDevice(name: host, host: host.trimmingCharacters(in: .whitespacesAndNewlines), port: UInt16(port) ?? 0)
        guard !target.host.isEmpty, target.port > 0 else { status = "Enter a valid host and port"; return }
        connection?.disconnect()
        selected = target
        busy = true
        connectionError = nil
        status = "Connecting to \(target.name)…"
        let endpoint = serviceEndpoints[target.id]
        connection = RFBConnection(host: target.host, port: target.port, password: password, endpoint: endpoint) { [weak self] event in
            DispatchQueue.main.async {
                guard let self else { return }
                switch event {
                case .connected(let resolvedHost, let width, let height):
                    self.busy = false
                    self.connected = true
                    self.framebufferWidth = width
                    self.framebufferHeight = height
                    if let resolvedHost, endpoint != nil {
                        target.host = resolvedHost
                        self.selected = target
                        if let index = self.devices.firstIndex(where: { $0.name == target.name }) { self.devices[index] = target }
                        else { self.devices.insert(target, at: 0) }
                        UserDefaults.standard.set(try? JSONEncoder().encode(self.devices), forKey: "devices")
                    }
                    if !self.password.isEmpty { self.storePassword(for: target) }
                    UserDefaults.standard.set(target.id, forKey: "lastConnectedDevice")
                    self.status = "Connected to \(target.name)"
                    if endpoint == nil && !self.devices.contains(where: { $0.id == target.id }) {
                        self.devices.insert(target, at: 0)
                        UserDefaults.standard.set(try? JSONEncoder().encode(self.devices), forKey: "devices")
                    }
                case .failed(let message):
                    self.busy = false
                    self.connected = false
                    self.connectionError = message
                    self.status = message
                }
            }
        }
        connection?.connect()
    }

    func disconnect() {
        connection?.disconnect()
        connection = nil
        connected = false
        busy = false
        status = "Disconnected"
    }

    func shutdown() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        connection?.disconnect()
        connection = nil
        videoReceiver?.stop()
        videoReceiver = nil
        if let uxplayProcess, uxplayProcess.isRunning { uxplayProcess.terminate() }
        uxplayProcess = nil
    }

    func pointer(x: Int, y: Int, buttons: UInt8) { connection?.pointer(x: x, y: y, buttons: buttons) }
    func home() { connection?.pointer(x: 0, y: 0, buttons: 4); connection?.pointer(x: 0, y: 0, buttons: 0) }
    func power() { connection?.pointer(x: 0, y: 0, buttons: 2); connection?.pointer(x: 0, y: 0, buttons: 0) }

    private func storePassword(for device: SavedDevice) {
        let data = Data(password.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "iPhoneMirroring15", kSecAttrAccount as String: "\(device.name):\(device.port)"]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        SecItemAdd(item as CFDictionary, nil)
    }

    private func startAirPlay() {
        let receiver = AirPlayVideoStream(onFrame: { [weak self] image in
            self?.image = image
        }, onError: { [weak self] message in
            self?.airPlayError = message
        })
        do {
            let port = try receiver.start()
            videoReceiver = receiver

            let executable: URL
            if let override = ProcessInfo.processInfo.environment["UXPLAY_PATH"], !override.isEmpty {
                executable = URL(fileURLWithPath: override)
            } else {
                let bundledExecutable = Bundle.main.bundleURL
                    .appendingPathComponent("Contents/Helpers/uxplay")
                if FileManager.default.isExecutableFile(atPath: bundledExecutable.path) {
                    executable = bundledExecutable
                } else {
                    executable = Bundle.main.bundleURL
                        .deletingLastPathComponent()
                        .deletingLastPathComponent()
                        .appendingPathComponent("../UxPlay/build/uxplay")
                        .standardizedFileURL
                }
            }
            guard FileManager.default.isExecutableFile(atPath: executable.path) else {
                airPlayError = "UxPlay not found at \(executable.path). Set UXPLAY_PATH to its executable."
                return
            }

            let process = Process()
            process.executableURL = executable
            process.arguments = ["-n", "iPhone Mirroring 15", "-vrtp", "config-interval=1 ! udpsink host=127.0.0.1 port=\(port)"]
            process.standardOutput = FileHandle.nullDevice
            let errorPipe = Pipe()
            process.standardError = errorPipe
            uxplayErrorOutput = ""
            errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let self else {
                    handle.readabilityHandler = nil
                    return
                }
                let output = String(decoding: data, as: UTF8.self)
                self.uxplayErrorLock.lock()
                self.uxplayErrorOutput = String((self.uxplayErrorOutput + output).suffix(600))
                self.uxplayErrorLock.unlock()
            }
            process.terminationHandler = { [weak self] process in
                errorPipe.fileHandleForReading.readabilityHandler = nil
                DispatchQueue.main.async {
                    guard let self, !self.isShuttingDown, process.terminationStatus != 0 else { return }
                    self.uxplayErrorLock.lock()
                    let details = self.uxplayErrorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.uxplayErrorLock.unlock()
                    let termination = process.terminationReason == .uncaughtSignal
                        ? "signal \(process.terminationStatus)"
                        : "exit status \(process.terminationStatus)"
                    self.airPlayError = details.isEmpty
                        ? "UxPlay stopped with \(termination)"
                        : "UxPlay stopped with \(termination):\n\(details)"
                }
            }
            try process.run()
            uxplayProcess = process
            airPlayError = nil
        } catch {
            receiver.stop()
            videoReceiver = nil
            airPlayError = error.localizedDescription
        }
    }

    private func configureBundledGStreamer() {
        let contents = Bundle.main.bundleURL.appendingPathComponent("Contents")
        let plugins = contents.appendingPathComponent("PlugIns/GStreamer")
        let scanner = contents.appendingPathComponent("Helpers/gst-plugin-scanner")
        guard FileManager.default.fileExists(atPath: plugins.path),
              FileManager.default.isExecutableFile(atPath: scanner.path) else { return }

        setenv("GST_PLUGIN_SYSTEM_PATH_1_0", plugins.path, 1)
        setenv("GST_PLUGIN_SYSTEM_PATH", plugins.path, 1)
        setenv("GST_PLUGIN_SCANNER_1_0", scanner.path, 1)
        setenv("GST_PLUGIN_SCANNER", scanner.path, 1)
        unsetenv("GST_PLUGIN_PATH_1_0")
        unsetenv("GST_PLUGIN_PATH")
    }

    func select(_ device: SavedDevice) {
        selected = device
        host = device.host
        port = String(device.port)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "iPhoneMirroring15", kSecAttrAccount as String: "\(device.name):\(device.port)", kSecReturnData as String: true]
        var result: CFTypeRef?
        SecItemCopyMatching(query as CFDictionary, &result)
        password = (result as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func deleteDevices(at offsets: IndexSet) {
        devices.remove(atOffsets: offsets)
        UserDefaults.standard.set(try? JSONEncoder().encode(devices), forKey: "devices")
    }
}
