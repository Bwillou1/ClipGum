import Foundation
import Network

public struct P2PDevice: Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let endpoint: NWEndpoint

    public init(id: UUID = UUID(), name: String, endpoint: NWEndpoint) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
    }
}

public enum P2PServiceStatus: Equatable, Sendable {
    case idle
    case browsing
    case connecting
    case awaitingPairing
    case ready
    case closed
}

/// Explicitly started Bonjour/AWDL transport. No instance is created or
/// started by the core's initialization, and no clipboard data is read here.
@MainActor
public final class LocalP2PService {
    public static let serviceType = "_clipgum._tcp"

    public var onDevicesChanged: ([P2PDevice]) -> Void = { _ in }
    public var onPairingCode: (String) -> Void = { _ in }
    public var onReady: () -> Void = {}
    public var onReceivedSanitizedText: (String) -> Void = { _ in }
    public var onDeliveryAcknowledged: () -> Void = {}
    public var onStatusChanged: (P2PServiceStatus) -> Void = { _ in }
    public var onError: (P2PError) -> Void = { _ in }

    private let deviceName: String
    private let serviceName: String
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var activeConnection: P2PNetworkConnection?
    private var deviceIDs: [NWEndpoint: UUID] = [:]
    private var devices: [P2PDevice] = []

    public init(deviceName: String = "ClipGum Device") {
        let trimmed = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.deviceName = String((trimmed.isEmpty ? "ClipGum Device" : trimmed).prefix(48))
        self.serviceName = "\(self.deviceName)-\(UUID().uuidString.prefix(8))"
    }

    public var isRunning: Bool { listener != nil }
    public var discoveredDevices: [P2PDevice] { devices }

    public func start() throws {
        guard listener == nil else { return }
        let listener = try NWListener(using: Self.parameters())
        listener.service = NWListener.Service(name: serviceName, type: Self.serviceType)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.onStatusChanged(.browsing)
            case .failed:
                self.onError(.connectionClosed)
                self.stop()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        let browser = NWBrowser(
            for: .bonjour(type: Self.serviceType, domain: nil),
            using: Self.parameters()
        )
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.onError(.connectionClosed) }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.updateDevices(results)
        }

        self.listener = listener
        self.browser = browser
        listener.start(queue: .main)
        browser.start(queue: .main)
        onStatusChanged(.browsing)
    }

    public func stop() {
        activeConnection?.close(notify: false)
        activeConnection = nil
        listener?.cancel()
        browser?.cancel()
        listener = nil
        browser = nil
        deviceIDs.removeAll()
        devices.removeAll()
        onDevicesChanged([])
        onStatusChanged(.idle)
    }

    public func connect(to device: P2PDevice) throws {
        guard listener != nil, activeConnection == nil else { throw P2PError.invalidTransition }
        let connection = NWConnection(to: device.endpoint, using: Self.parameters())
        let peer = try P2PNetworkConnection(
            connection: connection,
            deviceName: deviceName,
            isInitiator: true,
            onOutput: { [weak self] output in self?.handle(output) },
            onFailure: { [weak self] error in self?.onError(error) },
            onClose: { [weak self] in self?.connectionDidClose() }
        )
        activeConnection = peer
        onStatusChanged(.connecting)
        peer.start()
    }

    public func confirmPairing(code: String) throws {
        guard let activeConnection else { throw P2PError.invalidTransition }
        try activeConnection.confirmPairing(code: code)
    }

    public func sendSanitized(_ text: String) throws {
        guard let activeConnection else { throw P2PError.invalidTransition }
        try activeConnection.sendSanitized(text)
    }

    public func closeConnection() {
        activeConnection?.close()
        activeConnection = nil
        onStatusChanged(listener == nil ? .idle : .browsing)
    }

    private func accept(_ connection: NWConnection) {
        guard activeConnection == nil else {
            connection.cancel()
            return
        }
        do {
            let peer = try P2PNetworkConnection(
                connection: connection,
                deviceName: deviceName,
                isInitiator: false,
                onOutput: { [weak self] output in self?.handle(output) },
                onFailure: { [weak self] error in self?.onError(error) },
                onClose: { [weak self] in self?.connectionDidClose() }
            )
            activeConnection = peer
            onStatusChanged(.connecting)
            peer.start()
        } catch {
            connection.cancel()
            onError(error as? P2PError ?? .invalidConfiguration)
        }
    }

    private func updateDevices(_ results: Set<NWBrowser.Result>) {
        var updated: [P2PDevice] = []
        for result in results {
            let endpoint = result.endpoint
            if case .service(let name, _, _, _) = endpoint, name == serviceName { continue }
            let id = deviceIDs[endpoint] ?? UUID()
            deviceIDs[endpoint] = id
            let name: String
            if case .service(let serviceName, _, _, _) = endpoint {
                name = serviceName
            } else {
                name = "ClipGum peer"
            }
            updated.append(P2PDevice(id: id, name: name, endpoint: endpoint))
        }
        devices = updated.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        onDevicesChanged(devices)
    }

    private func handle(_ output: P2PSessionOutput) {
        guard let connection = activeConnection else { return }
        for frame in output.outgoingFrames { connection.send(frame) }
        for event in output.events {
            switch event {
            case .pairingCode(let code):
                onStatusChanged(.awaitingPairing)
                onPairingCode(code)
            case .ready:
                onStatusChanged(.ready)
                onReady()
            case .receivedSanitizedText(let text):
                onReceivedSanitizedText(text)
            case .deliveryAcknowledged:
                onDeliveryAcknowledged()
            case .closed:
                onStatusChanged(.closed)
            }
        }
    }

    private func connectionDidClose() {
        activeConnection = nil
        onStatusChanged(listener == nil ? .idle : .browsing)
    }

    private static func parameters() -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        return parameters
    }
}

@MainActor
private final class P2PNetworkConnection {
    private let connection: NWConnection
    private var session: P2PSession
    private var accumulator = P2PFrameAccumulator()
    private var timeout: DispatchWorkItem?
    private var didClose = false
    private let onOutput: (P2PSessionOutput) -> Void
    private let onFailure: (P2PError) -> Void
    private let onClose: () -> Void

    init(
        connection: NWConnection,
        deviceName: String,
        isInitiator: Bool,
        onOutput: @escaping (P2PSessionOutput) -> Void,
        onFailure: @escaping (P2PError) -> Void,
        onClose: @escaping () -> Void
    ) throws {
        self.connection = connection
        session = try P2PSession(deviceName: deviceName, isInitiator: isInitiator)
        self.onOutput = onOutput
        self.onFailure = onFailure
        self.onClose = onClose
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed, .cancelled:
                self.finish()
            default:
                break
            }
        }
        connection.start(queue: .main)
        do {
            try handle(session.start())
            scheduleTimeout()
            receive()
        } catch {
            fail(error)
        }
    }

    func confirmPairing(code: String) throws {
        try handle(session.confirmPairing(code: code))
    }

    func sendSanitized(_ text: String) throws {
        try handle(session.sendSanitized(text))
    }

    func send(_ frame: P2PFrame) {
        guard !didClose else { return }
        do {
            var packet = try P2PFrameCodec.encode(frame)
            connection.send(content: packet, completion: .contentProcessed { [weak self] error in
                if let error { self?.fail(error) }
                wipeP2PData(&packet)
            })
            scheduleTimeout(after: session.state == .ready ? 60 : 30)
        } catch {
            fail(error)
        }
    }

    func close(notify: Bool = true) {
        guard !didClose else { return }
        if notify, let output = try? session.close() {
            for frame in output.outgoingFrames { send(frame) }
        }
        finish()
    }

    private func receive() {
        guard !didClose else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) {
            [weak self] data, _, isComplete, error in
            guard let self, !self.didClose else { return }
            if let error {
                self.fail(error)
                return
            }
            do {
                if var data, !data.isEmpty {
                    let frames = try self.accumulator.append(data)
                    wipeP2PData(&data)
                    for frame in frames {
                        var body = frame.body
                        try self.handle(self.session.receive(P2PFrame(kind: frame.kind, body: body)))
                        wipeP2PData(&body)
                    }
                }
                if isComplete {
                    self.finish()
                } else {
                    self.receive()
                }
            } catch {
                self.fail(error)
            }
        }
    }

    private func handle(_ output: P2PSessionOutput) throws {
        if output.events.contains(.ready) {
            scheduleTimeout(after: 60)
        }
        onOutput(output)
    }

    private func scheduleTimeout(after interval: TimeInterval = 30) {
        timeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.fail(P2PError.connectionClosed)
        }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: work)
    }

    private func fail(_ error: Error) {
        // Network errors are reduced to safe codes; packet contents and
        // NWError descriptions are never logged by this layer.
        onFailure(error as? P2PError ?? .connectionClosed)
        finish()
    }

    private func finish() {
        guard !didClose else { return }
        didClose = true
        timeout?.cancel()
        timeout = nil
        accumulator.wipe()
        connection.stateUpdateHandler = nil
        connection.cancel()
        onClose()
    }
}

