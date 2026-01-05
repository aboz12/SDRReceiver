import Foundation
import Network
import SwiftUI

// MARK: - Remote Control Server

@MainActor
public final class RemoteControlServer: ObservableObject {
    public static let shared = RemoteControlServer()

    @Published public var isRunning = false
    @Published public var tcpPort: UInt16 = 7373
    @Published public var httpPort: UInt16 = 8080
    @Published public var connectedClients: Int = 0
    @Published public private(set) var lastCommand: String = ""
    @Published public private(set) var lastResponse: String = ""

    private var tcpListener: NWListener?
    private var httpListener: NWListener?
    private var connections: [NWConnection] = []

    private init() {}

    public func start() throws {
        guard !isRunning else { return }

        // Start TCP listener
        let tcpParams = NWParameters.tcp
        tcpListener = try NWListener(using: tcpParams, on: NWEndpoint.Port(rawValue: tcpPort)!)
        tcpListener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleNewConnection(connection)
            }
        }
        tcpListener?.start(queue: .main)

        // Start HTTP listener
        let httpParams = NWParameters.tcp
        httpListener = try NWListener(using: httpParams, on: NWEndpoint.Port(rawValue: httpPort)!)
        httpListener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleHTTPConnection(connection)
            }
        }
        httpListener?.start(queue: .main)

        isRunning = true
    }

    public func stop() {
        tcpListener?.cancel()
        httpListener?.cancel()
        tcpListener = nil
        httpListener = nil

        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()

        isRunning = false
        connectedClients = 0
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)
        connectedClients = connections.count

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                if case .cancelled = state {
                    self?.connections.removeAll { $0 === connection }
                    self?.connectedClients = self?.connections.count ?? 0
                }
            }
        }

        connection.start(queue: .main)
        receiveData(from: connection)
    }

    private func receiveData(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, _, error in
            Task { @MainActor in
                if let data = data, !data.isEmpty {
                    let command = String(data: data, encoding: .utf8) ?? ""
                    let response = await self?.processCommand(command.trimmingCharacters(in: .whitespacesAndNewlines))

                    if let responseData = (response ?? "ERROR").data(using: .utf8) {
                        connection.send(content: responseData, completion: .contentProcessed { _ in })
                    }
                }

                if error == nil {
                    self?.receiveData(from: connection)
                }
            }
        }
    }

    private func handleHTTPConnection(_ connection: NWConnection) {
        connection.start(queue: .main)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            Task { @MainActor in
                guard let data = data, !data.isEmpty else { return }

                let request = String(data: data, encoding: .utf8) ?? ""
                let response = await self?.handleHTTPRequest(request)

                if let responseData = response?.data(using: .utf8) {
                    connection.send(content: responseData, completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
            }
        }
    }

    private func handleHTTPRequest(_ request: String) async -> String {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return httpResponse(status: 400, body: "Bad Request") }

        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return httpResponse(status: 400, body: "Bad Request") }

        let method = parts[0]
        let path = parts[1]

        // Parse path and query
        let pathComponents = path.components(separatedBy: "?")
        let endpoint = pathComponents[0]
        var params: [String: String] = [:]

        if pathComponents.count > 1 {
            let query = pathComponents[1]
            for param in query.components(separatedBy: "&") {
                let kv = param.components(separatedBy: "=")
                if kv.count == 2 {
                    params[kv[0]] = kv[1].removingPercentEncoding
                }
            }
        }

        // Route requests
        switch (method, endpoint) {
        case ("GET", "/api/status"):
            return await httpResponse(status: 200, body: getStatusJSON())

        case ("GET", "/api/frequency"):
            let freq = SDREngine.shared.frequency
            return httpResponse(status: 200, body: "{\"frequency\": \(freq)}")

        case ("POST", "/api/frequency"):
            if let freqStr = params["value"], let freq = Double(freqStr) {
                SDREngine.shared.frequency = freq
                return httpResponse(status: 200, body: "{\"success\": true}")
            }
            return httpResponse(status: 400, body: "{\"error\": \"Missing frequency value\"}")

        case ("GET", "/api/mode"):
            let mode = SDREngine.shared.dspEngine.demodulationMode.rawValue
            return httpResponse(status: 200, body: "{\"mode\": \"\(mode)\"}")

        case ("POST", "/api/mode"):
            if let modeStr = params["value"], let mode = DemodulationMode(rawValue: modeStr) {
                SDREngine.shared.dspEngine.demodulationMode = mode
                return httpResponse(status: 200, body: "{\"success\": true}")
            }
            return httpResponse(status: 400, body: "{\"error\": \"Invalid mode\"}")

        case ("GET", "/api/gain"):
            let gain = SDREngine.shared.gain
            return httpResponse(status: 200, body: "{\"gain\": \(gain)}")

        case ("POST", "/api/gain"):
            if let gainStr = params["value"], let gain = Double(gainStr) {
                SDREngine.shared.gain = gain
                return httpResponse(status: 200, body: "{\"success\": true}")
            }
            return httpResponse(status: 400, body: "{\"error\": \"Missing gain value\"}")

        case ("POST", "/api/start"):
            do {
                try await SDREngine.shared.start()
                return httpResponse(status: 200, body: "{\"success\": true}")
            } catch {
                return httpResponse(status: 500, body: "{\"error\": \"\(error.localizedDescription)\"}")
            }

        case ("POST", "/api/stop"):
            SDREngine.shared.stop()
            return httpResponse(status: 200, body: "{\"success\": true}")

        default:
            return httpResponse(status: 404, body: "{\"error\": \"Not found\"}")
        }
    }

    private func httpResponse(status: Int, body: String) -> String {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Unknown"
        }

        return """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        Access-Control-Allow-Origin: *\r
        \r
        \(body)
        """
    }

    private func getStatusJSON() async -> String {
        let engine = SDREngine.shared
        return """
        {
            "running": \(engine.isRunning),
            "frequency": \(engine.frequency),
            "mode": "\(engine.dspEngine.demodulationMode.rawValue)",
            "gain": \(engine.gain),
            "gainMode": "\(engine.gainMode.rawValue)",
            "sampleRate": \(engine.sampleRate),
            "signalStrength": \(engine.dspEngine.signalStrength),
            "squelchEnabled": \(engine.dspEngine.squelchEnabled),
            "squelchLevel": \(engine.dspEngine.squelchLevel),
            "device": "\(engine.currentDevice?.name ?? "None")"
        }
        """
    }

    // MARK: - TCP Command Protocol

    private func processCommand(_ command: String) async -> String {
        lastCommand = command

        let parts = command.components(separatedBy: " ")
        guard let cmd = parts.first else { return "ERROR: Empty command" }

        let response: String

        switch cmd.uppercased() {
        case "FREQ":
            if parts.count > 1, let freq = Double(parts[1]) {
                SDREngine.shared.frequency = freq
                response = "OK FREQ \(freq)"
            } else {
                response = "FREQ \(SDREngine.shared.frequency)"
            }

        case "MODE":
            if parts.count > 1, let mode = DemodulationMode(rawValue: parts[1].uppercased()) {
                SDREngine.shared.dspEngine.demodulationMode = mode
                response = "OK MODE \(mode.rawValue)"
            } else {
                response = "MODE \(SDREngine.shared.dspEngine.demodulationMode.rawValue)"
            }

        case "GAIN":
            if parts.count > 1, let gain = Double(parts[1]) {
                SDREngine.shared.gain = gain
                response = "OK GAIN \(gain)"
            } else {
                response = "GAIN \(SDREngine.shared.gain)"
            }

        case "SQUELCH":
            if parts.count > 1, let level = Float(parts[1]) {
                SDREngine.shared.dspEngine.squelchLevel = level
                response = "OK SQUELCH \(level)"
            } else {
                response = "SQUELCH \(SDREngine.shared.dspEngine.squelchLevel)"
            }

        case "START":
            do {
                try await SDREngine.shared.start()
                response = "OK START"
            } catch {
                response = "ERROR: \(error.localizedDescription)"
            }

        case "STOP":
            SDREngine.shared.stop()
            response = "OK STOP"

        case "STATUS":
            let engine = SDREngine.shared
            response = """
            STATUS \(engine.isRunning ? "RUNNING" : "STOPPED") \
            FREQ=\(engine.frequency) \
            MODE=\(engine.dspEngine.demodulationMode.rawValue) \
            GAIN=\(engine.gain) \
            SIGNAL=\(engine.dspEngine.signalStrength)
            """

        case "HELP":
            response = """
            Commands:
            FREQ [hz] - Get/set frequency
            MODE [AM|FM|WFM|LSB|USB|CW] - Get/set mode
            GAIN [dB] - Get/set gain
            SQUELCH [dBm] - Get/set squelch level
            START - Start receiving
            STOP - Stop receiving
            STATUS - Get current status
            HELP - Show this help
            """

        default:
            response = "ERROR: Unknown command '\(cmd)'"
        }

        lastResponse = response
        return response + "\n"
    }
}

// MARK: - AppleScript Support

@MainActor
public final class AppleScriptHandler: ObservableObject {
    public static let shared = AppleScriptHandler()

    private init() {}

    /// Handle AppleScript command
    public func handleCommand(_ command: String, arguments: [String]) -> String {
        switch command.lowercased() {
        case "getfrequency":
            return String(format: "%.0f", SDREngine.shared.frequency)

        case "setfrequency":
            if let freqStr = arguments.first, let freq = Double(freqStr) {
                SDREngine.shared.frequency = freq
                return "OK"
            }
            return "ERROR: Invalid frequency"

        case "getmode":
            return SDREngine.shared.dspEngine.demodulationMode.rawValue

        case "setmode":
            if let modeStr = arguments.first, let mode = DemodulationMode(rawValue: modeStr.uppercased()) {
                SDREngine.shared.dspEngine.demodulationMode = mode
                return "OK"
            }
            return "ERROR: Invalid mode"

        case "getgain":
            return String(format: "%.1f", SDREngine.shared.gain)

        case "setgain":
            if let gainStr = arguments.first, let gain = Double(gainStr) {
                SDREngine.shared.gain = gain
                return "OK"
            }
            return "ERROR: Invalid gain"

        case "start":
            Task {
                try? await SDREngine.shared.start()
            }
            return "OK"

        case "stop":
            SDREngine.shared.stop()
            return "OK"

        case "isrunning":
            return SDREngine.shared.isRunning ? "true" : "false"

        case "getsignal":
            return String(format: "%.1f", SDREngine.shared.dspEngine.signalStrength)

        default:
            return "ERROR: Unknown command"
        }
    }

    /// Get SDEF for scripting dictionary
    public static var scriptingDefinition: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE dictionary SYSTEM "file://localhost/System/Library/DTDs/sdef.dtd">
        <dictionary title="SDRReceiver Terminology">
            <suite name="SDRReceiver Suite" code="SDRR" description="SDRReceiver scripting commands">
                <command name="get frequency" code="SDRRgfrq" description="Get current frequency in Hz">
                    <result type="real" description="Frequency in Hz"/>
                </command>
                <command name="set frequency" code="SDRRsfrq" description="Set frequency in Hz">
                    <direct-parameter type="real" description="Frequency in Hz"/>
                </command>
                <command name="get mode" code="SDRRgmod" description="Get current demodulation mode">
                    <result type="text" description="Mode (AM, FM, WFM, LSB, USB, CW)"/>
                </command>
                <command name="set mode" code="SDRRsmod" description="Set demodulation mode">
                    <direct-parameter type="text" description="Mode (AM, FM, WFM, LSB, USB, CW)"/>
                </command>
                <command name="get gain" code="SDRRggai" description="Get current gain in dB">
                    <result type="real" description="Gain in dB"/>
                </command>
                <command name="set gain" code="SDRRsgai" description="Set gain in dB">
                    <direct-parameter type="real" description="Gain in dB"/>
                </command>
                <command name="start receiving" code="SDRRstrt" description="Start SDR reception"/>
                <command name="stop receiving" code="SDRRstop" description="Stop SDR reception"/>
                <command name="get signal strength" code="SDRRgsig" description="Get signal strength in dBm">
                    <result type="real" description="Signal strength in dBm"/>
                </command>
            </suite>
        </dictionary>
        """
    }
}

// MARK: - Remote Control Views

public struct RemoteControlSettingsView: View {
    @ObservedObject var server = RemoteControlServer.shared

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Remote Control")
                    .font(.headline)

                Spacer()

                Circle()
                    .fill(server.isRunning ? .green : .red)
                    .frame(width: 8, height: 8)

                Text(server.isRunning ? "Running" : "Stopped")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            GroupBox("TCP Server") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Port:")
                        TextField("Port", value: $server.tcpPort, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .disabled(server.isRunning)
                    }

                    if server.isRunning {
                        Text("telnet localhost \(server.tcpPort)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            GroupBox("HTTP API") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Port:")
                        TextField("Port", value: $server.httpPort, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .disabled(server.isRunning)
                    }

                    if server.isRunning {
                        Text("http://localhost:\(server.httpPort)/api/status")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if server.isRunning {
                GroupBox("Status") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Connected clients:")
                            Spacer()
                            Text("\(server.connectedClients)")
                        }

                        if !server.lastCommand.isEmpty {
                            Divider()
                            Text("Last command: \(server.lastCommand)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Response: \(server.lastResponse)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            HStack {
                Button(server.isRunning ? "Stop Server" : "Start Server") {
                    if server.isRunning {
                        server.stop()
                    } else {
                        try? server.start()
                    }
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }

            GroupBox("API Endpoints") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GET /api/status - Get full status")
                    Text("GET /api/frequency - Get frequency")
                    Text("POST /api/frequency?value=Hz - Set frequency")
                    Text("GET /api/mode - Get demodulation mode")
                    Text("POST /api/mode?value=MODE - Set mode")
                    Text("POST /api/start - Start receiving")
                    Text("POST /api/stop - Stop receiving")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

public struct AppleScriptHelpView: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AppleScript Support")
                .font(.headline)

            GroupBox("Example Scripts") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        codeBlock("""
                        -- Get current frequency
                        tell application "SDRReceiver"
                            get frequency
                        end tell
                        """)

                        codeBlock("""
                        -- Tune to 144.200 MHz
                        tell application "SDRReceiver"
                            set frequency to 144200000
                        end tell
                        """)

                        codeBlock("""
                        -- Change mode to USB
                        tell application "SDRReceiver"
                            set mode to "USB"
                        end tell
                        """)

                        codeBlock("""
                        -- Start/stop receiver
                        tell application "SDRReceiver"
                            start receiving
                            delay 10
                            stop receiving
                        end tell
                        """)
                    }
                }
            }
        }
        .padding()
    }

    @ViewBuilder
    private func codeBlock(_ code: String) -> some View {
        Text(code)
            .font(.system(.caption, design: .monospaced))
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.2))
            .cornerRadius(4)
    }
}
