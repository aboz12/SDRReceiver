import Foundation
import SwiftUI
import Network

// MARK: - Streaming Protocol

public enum StreamingProtocol: String, CaseIterable {
    case tcp = "TCP"
    case udp = "UDP"
    case rtlTcp = "RTL-TCP"
}

public enum StreamingFormat: String, CaseIterable {
    case iq8 = "I/Q 8-bit"
    case iq16 = "I/Q 16-bit"
    case float32 = "Float32"
    case audio = "Audio"
}

// MARK: - Streaming Server

@MainActor
public final class StreamingServer: ObservableObject {
    public static let shared = StreamingServer()

    @Published public var isRunning = false
    @Published public var port: UInt16 = 1234
    @Published public var protocol_: StreamingProtocol = .tcp
    @Published public var format: StreamingFormat = .iq16
    @Published public var connectedClients: Int = 0
    @Published public var bytesSent: UInt64 = 0

    private var listener: NWListener?
    private var connections: [NWConnection] = []

    private init() {}

    public func startServer() throws {
        let params = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

        listener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isRunning = true
                case .failed, .cancelled:
                    self?.isRunning = false
                default:
                    break
                }
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleNewConnection(connection)
            }
        }

        listener?.start(queue: .main)
    }

    public func stopServer() {
        listener?.cancel()
        listener = nil

        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()

        isRunning = false
        connectedClients = 0
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.connections.append(connection)
                    self?.connectedClients = self?.connections.count ?? 0
                case .failed, .cancelled:
                    self?.connections.removeAll { $0 === connection }
                    self?.connectedClients = self?.connections.count ?? 0
                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
    }

    public func broadcastSamples(_ samples: [ComplexFloat]) {
        guard isRunning, !connections.isEmpty else { return }

        let data: Data

        switch format {
        case .iq8:
            var bytes = Data(capacity: samples.count * 2)
            for sample in samples {
                bytes.append(UInt8(clamping: Int((sample.real + 1) * 127.5)))
                bytes.append(UInt8(clamping: Int((sample.imag + 1) * 127.5)))
            }
            data = bytes

        case .iq16:
            var bytes = Data(capacity: samples.count * 4)
            for sample in samples {
                var i = Int16(clamping: Int(sample.real * 32767))
                var q = Int16(clamping: Int(sample.imag * 32767))
                bytes.append(contentsOf: withUnsafeBytes(of: &i) { Array($0) })
                bytes.append(contentsOf: withUnsafeBytes(of: &q) { Array($0) })
            }
            data = bytes

        case .float32:
            var bytes = Data(capacity: samples.count * 8)
            for sample in samples {
                var i = sample.real
                var q = sample.imag
                bytes.append(contentsOf: withUnsafeBytes(of: &i) { Array($0) })
                bytes.append(contentsOf: withUnsafeBytes(of: &q) { Array($0) })
            }
            data = bytes

        case .audio:
            // Send demodulated audio instead
            return
        }

        for connection in connections {
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if error == nil {
                    Task { @MainActor in
                        self?.bytesSent += UInt64(data.count)
                    }
                }
            })
        }
    }

    public func broadcastAudio(_ samples: [Float]) {
        guard isRunning, format == .audio, !connections.isEmpty else { return }

        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            var pcm = Int16(clamping: Int(sample * 32767))
            data.append(contentsOf: withUnsafeBytes(of: &pcm) { Array($0) })
        }

        for connection in connections {
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
    }
}

// MARK: - Streaming Client

@MainActor
public final class StreamingClient: ObservableObject {
    public static let shared = StreamingClient()

    @Published public var isConnected = false
    @Published public var serverAddress = ""
    @Published public var serverPort: UInt16 = 1234
    @Published public var bytesReceived: UInt64 = 0

    private var connection: NWConnection?

    public var onSamplesReceived: (([ComplexFloat]) -> Void)?

    private init() {}

    public func connect() {
        let host = NWEndpoint.Host(serverAddress)
        let port = NWEndpoint.Port(rawValue: serverPort)!

        connection = NWConnection(host: host, port: port, using: .tcp)

        connection?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isConnected = true
                    self?.receiveData()
                case .failed, .cancelled:
                    self?.isConnected = false
                default:
                    break
                }
            }
        }

        connection?.start(queue: .main)
    }

    public func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
    }

    private func receiveData() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            if let data = data {
                Task { @MainActor in
                    self?.bytesReceived += UInt64(data.count)
                    self?.processReceivedData(data)
                    self?.receiveData()  // Continue receiving
                }
            } else if let error = error {
                print("Receive error: \(error)")
            }
        }
    }

    private func processReceivedData(_ data: Data) {
        // Convert to complex samples (assuming 16-bit I/Q)
        var samples: [ComplexFloat] = []
        let count = data.count / 4

        data.withUnsafeBytes { ptr in
            let int16Ptr = ptr.bindMemory(to: Int16.self)
            for i in 0..<count {
                let real = Float(int16Ptr[i * 2]) / 32767
                let imag = Float(int16Ptr[i * 2 + 1]) / 32767
                samples.append(ComplexFloat(real: real, imag: imag))
            }
        }

        onSamplesReceived?(samples)
    }
}

// MARK: - Streaming View

public struct NetworkStreamingView: View {
    @ObservedObject var server = StreamingServer.shared
    @ObservedObject var client = StreamingClient.shared

    @State private var mode: StreamingMode = .server

    enum StreamingMode {
        case server, client
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Mode selector
            Picker("Mode", selection: $mode) {
                Text("Server").tag(StreamingMode.server)
                Text("Client").tag(StreamingMode.client)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            if mode == .server {
                ServerView()
            } else {
                ClientView()
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

struct ServerView: View {
    @ObservedObject var server = StreamingServer.shared

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Status:")
                Circle()
                    .fill(server.isRunning ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(server.isRunning ? "Running" : "Stopped")
                    .font(.system(size: 12))
            }

            HStack {
                Text("Port:")
                TextField("Port", value: $server.port, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .disabled(server.isRunning)
            }

            HStack {
                Text("Format:")
                Picker("Format", selection: $server.format) {
                    ForEach(StreamingFormat.allCases, id: \.self) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.menu)
                .disabled(server.isRunning)
            }

            Divider()

            HStack {
                Text("Clients: \(server.connectedClients)")
                Spacer()
                Text("Sent: \(formatBytes(server.bytesSent))")
            }
            .font(.system(size: 12))

            Button {
                if server.isRunning {
                    server.stopServer()
                } else {
                    try? server.startServer()
                }
            } label: {
                Text(server.isRunning ? "Stop Server" : "Start Server")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(width: 250)
    }
}

struct ClientView: View {
    @ObservedObject var client = StreamingClient.shared

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Status:")
                Circle()
                    .fill(client.isConnected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(client.isConnected ? "Connected" : "Disconnected")
                    .font(.system(size: 12))
            }

            HStack {
                Text("Server:")
                TextField("Address", text: $client.serverAddress)
                    .textFieldStyle(.roundedBorder)
                    .disabled(client.isConnected)
            }

            HStack {
                Text("Port:")
                TextField("Port", value: $client.serverPort, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .disabled(client.isConnected)
            }

            Divider()

            HStack {
                Text("Received: \(formatBytes(client.bytesReceived))")
            }
            .font(.system(size: 12))

            Button {
                if client.isConnected {
                    client.disconnect()
                } else {
                    client.connect()
                }
            } label: {
                Text(client.isConnected ? "Disconnect" : "Connect")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(width: 250)
    }
}

private func formatBytes(_ bytes: UInt64) -> String {
    if bytes >= 1_073_741_824 {
        return String(format: "%.2f GB", Double(bytes) / 1_073_741_824)
    } else if bytes >= 1_048_576 {
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    } else if bytes >= 1024 {
        return String(format: "%.0f KB", Double(bytes) / 1024)
    } else {
        return "\(bytes) B"
    }
}
