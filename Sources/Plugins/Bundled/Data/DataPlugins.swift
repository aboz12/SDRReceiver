import Foundation
import SwiftUI
import MapKit

// MARK: - APRS Plugin

public final class APRSPlugin: PacketDecoderPlugin, ObservableObject {
    public static let identifier = "com.sdr.decoder.aprs"
    public static let name = "APRS"
    public static let version = "1.0.0"
    public static let author = "SDR Team"
    public static let description = "Automatic Packet Reporting System"
    public static let category = DecoderCategory.data

    public let id = UUID()
    public let requiredSampleRate: Double = 22050
    public let requiredBandwidth: Double = 12500
    public let centerFrequencyOffset: Double = 0

    // APRS: AX.25 at 1200 baud AFSK (1200/2200 Hz tones)
    // VHF: 144.390 MHz (North America), 144.800 MHz (Europe)

    @Published public var stations: [String: APRSStation] = [:]
    @Published public var packets: [APRSPacket] = []

    // AX.25 HDLC flag
    private let flagByte: UInt8 = 0x7E

    public init() {}

    public func initialize() throws {
        stations.removeAll()
        packets.removeAll()
    }

    public func shutdown() {}

    public func process(samples: [Float], sampleRate: Double) async -> [DecodedMessage] {
        var messages: [DecodedMessage] = []

        // APRS/AX.25 decoding:
        // 1. AFSK demodulation (1200/2200 Hz Bell 202)
        // 2. NRZI decoding
        // 3. Bit unstuffing
        // 4. AX.25 frame extraction
        // 5. APRS payload parsing

        let bits = demodulateAFSK(samples, sampleRate: sampleRate)

        // Find flag bytes and extract frames
        let frames = extractAX25Frames(bits)

        for frame in frames {
            if let packet = decodeAX25Frame(frame) {
                if let aprsPacket = parseAPRSPacket(packet) {
                    let message = DecodedMessage(
                        plugin: Self.identifier,
                        timestamp: Date(),
                        frequency: 144_390_000,
                        snr: nil,
                        content: "\(aprsPacket.source)>\(aprsPacket.destination): \(aprsPacket.info)",
                        metadata: [
                            "source": aprsPacket.source,
                            "destination": aprsPacket.destination,
                            "path": aprsPacket.path.joined(separator: ","),
                            "type": aprsPacket.packetType.rawValue
                        ]
                    )
                    messages.append(message)

                    await MainActor.run {
                        packets.insert(aprsPacket, at: 0)
                        if packets.count > 200 {
                            packets.removeLast()
                        }

                        // Update station tracking
                        if let lat = aprsPacket.latitude, let lon = aprsPacket.longitude {
                            var station = stations[aprsPacket.source] ?? APRSStation(callsign: aprsPacket.source)
                            station.latitude = lat
                            station.longitude = lon
                            station.lastHeard = Date()
                            station.comment = aprsPacket.comment
                            stations[aprsPacket.source] = station
                        }
                    }
                }
            }
        }

        return messages
    }

    private func demodulateAFSK(_ samples: [Float], sampleRate: Double) -> [Int] {
        var bits: [Int] = []

        // Bell 202 AFSK: 1200 Hz = mark (1), 2200 Hz = space (0)
        // 1200 baud

        let samplesPerBit = Int(sampleRate / 1200.0)
        let windowSize = samplesPerBit

        for i in stride(from: 0, to: samples.count - windowSize, by: samplesPerBit) {
            // Goertzel algorithm for 1200 Hz and 2200 Hz detection
            let power1200 = goertzelPower(samples, start: i, length: windowSize, targetFreq: 1200, sampleRate: sampleRate)
            let power2200 = goertzelPower(samples, start: i, length: windowSize, targetFreq: 2200, sampleRate: sampleRate)

            bits.append(power1200 > power2200 ? 1 : 0)
        }

        // NRZI decode: 0 = transition, 1 = no transition
        var nrziBits: [Int] = []
        var lastBit = 1
        for bit in bits {
            if bit == lastBit {
                nrziBits.append(1)
            } else {
                nrziBits.append(0)
            }
            lastBit = bit
        }

        return nrziBits
    }

    private func goertzelPower(_ samples: [Float], start: Int, length: Int, targetFreq: Double, sampleRate: Double) -> Float {
        let k = Int(0.5 + Double(length) * targetFreq / sampleRate)
        let w = 2.0 * Double.pi * Double(k) / Double(length)
        let coeff = Float(2.0 * cos(w))

        var s0: Float = 0
        var s1: Float = 0
        var s2: Float = 0

        for i in 0..<length {
            s0 = samples[start + i] + coeff * s1 - s2
            s2 = s1
            s1 = s0
        }

        return s1 * s1 + s2 * s2 - coeff * s1 * s2
    }

    private func extractAX25Frames(_ bits: [Int]) -> [[Int]] {
        var frames: [[Int]] = []
        var currentFrame: [Int] = []
        var onesCount = 0
        var inFrame = false

        for bit in bits {
            if bit == 1 {
                onesCount += 1
                if onesCount < 6 {
                    if inFrame {
                        currentFrame.append(bit)
                    }
                }
            } else {
                if onesCount == 6 {
                    // Flag detected
                    if inFrame && currentFrame.count > 0 {
                        frames.append(currentFrame)
                    }
                    currentFrame = []
                    inFrame = true
                } else if onesCount == 5 {
                    // Bit stuffing - skip this 0
                } else {
                    if inFrame {
                        currentFrame.append(bit)
                    }
                }
                onesCount = 0
            }
        }

        return frames
    }

    private func decodeAX25Frame(_ bits: [Int]) -> AX25Frame? {
        guard bits.count >= 136 else { return nil }  // Minimum frame size

        // Convert bits to bytes (LSB first for AX.25)
        var bytes: [UInt8] = []
        for i in stride(from: 0, to: bits.count - 7, by: 8) {
            var byte: UInt8 = 0
            for j in 0..<8 {
                byte |= UInt8(bits[i + j]) << j  // LSB first
            }
            bytes.append(byte)
        }

        guard bytes.count >= 17 else { return nil }  // Minimum: 14 addr + 1 control + 1 pid + 1 fcs

        // Extract addresses (7 bytes each, shifted left 1 bit)
        let destAddr = extractCallsign(Array(bytes[0..<7]))
        let srcAddr = extractCallsign(Array(bytes[7..<14]))

        // Check for digipeater addresses
        var path: [String] = []
        var addrIndex = 14
        while addrIndex + 7 <= bytes.count && (bytes[addrIndex - 1] & 0x01) == 0 {
            path.append(extractCallsign(Array(bytes[addrIndex..<(addrIndex + 7)])))
            addrIndex += 7
        }

        guard addrIndex + 2 < bytes.count else { return nil }

        let control = bytes[addrIndex]
        let pid = bytes[addrIndex + 1]
        let info = Array(bytes[(addrIndex + 2)..<(bytes.count - 2)])

        return AX25Frame(
            destination: destAddr,
            source: srcAddr,
            path: path,
            control: control,
            pid: pid,
            info: Data(info)
        )
    }

    private func extractCallsign(_ bytes: [UInt8]) -> String {
        guard bytes.count == 7 else { return "" }

        var callsign = ""
        for i in 0..<6 {
            let char = bytes[i] >> 1
            if char >= 0x20 && char <= 0x7E {
                callsign.append(Character(UnicodeScalar(char)))
            }
        }

        let ssid = (bytes[6] >> 1) & 0x0F
        callsign = callsign.trimmingCharacters(in: .whitespaces)

        if ssid > 0 {
            callsign += "-\(ssid)"
        }

        return callsign
    }

    private func parseAPRSPacket(_ frame: AX25Frame) -> APRSPacket? {
        guard let infoString = String(data: frame.info, encoding: .ascii) else { return nil }

        var packet = APRSPacket(
            id: UUID(),
            timestamp: Date(),
            source: frame.source,
            destination: frame.destination,
            path: frame.path,
            packetType: .unknown,
            info: infoString
        )

        // Parse APRS data type identifier (first character)
        guard let firstChar = infoString.first else { return packet }

        switch firstChar {
        case "!", "/", "@", "=":
            // Position report
            packet.packetType = .position
            parsePositionReport(infoString, into: &packet)
        case ">":
            // Status
            packet.packetType = .status
            packet.comment = String(infoString.dropFirst())
        case ":":
            // Message
            packet.packetType = .message
        case ";":
            // Object
            packet.packetType = .object
        case ")":
            // Item
            packet.packetType = .item
        case "T":
            // Telemetry
            packet.packetType = .telemetry
        case "_":
            // Weather
            packet.packetType = .weather
        case "`", "'":
            // Mic-E
            packet.packetType = .micE
            parseMicEPosition(frame.destination, infoString, into: &packet)
        default:
            packet.packetType = .unknown
        }

        return packet
    }

    private func parsePositionReport(_ info: String, into packet: inout APRSPacket) {
        // Format: !DDMM.mmN/DDDMM.mmW# or with timestamp /HHMMSSh or @HHMMSSz
        let chars = Array(info)
        guard chars.count >= 19 else { return }

        var offset = 1
        if chars[0] == "/" || chars[0] == "@" {
            offset = 8  // Skip timestamp
        }

        guard chars.count >= offset + 18 else { return }

        // Parse latitude: DDMM.mmN
        let latStr = String(chars[offset..<(offset + 8)])
        if let lat = parseLatitude(latStr) {
            packet.latitude = lat
        }

        // Parse longitude: DDDMM.mmW
        let lonStr = String(chars[(offset + 9)..<(offset + 18)])
        if let lon = parseLongitude(lonStr) {
            packet.longitude = lon
        }

        // Symbol table and code
        if offset + 18 < chars.count {
            packet.symbolTable = chars[offset + 8]
            packet.symbolCode = chars[offset + 18]
        }

        // Comment (everything after position)
        if chars.count > offset + 19 {
            packet.comment = String(chars[(offset + 19)...])
        }
    }

    private func parseLatitude(_ str: String) -> Double? {
        guard str.count == 8 else { return nil }
        let chars = Array(str)

        guard let degrees = Double(String(chars[0..<2])),
              let minutes = Double(String(chars[2..<7])) else { return nil }

        var lat = degrees + minutes / 60.0
        if chars[7] == "S" { lat = -lat }

        return lat
    }

    private func parseLongitude(_ str: String) -> Double? {
        guard str.count == 9 else { return nil }
        let chars = Array(str)

        guard let degrees = Double(String(chars[0..<3])),
              let minutes = Double(String(chars[3..<8])) else { return nil }

        var lon = degrees + minutes / 60.0
        if chars[8] == "W" { lon = -lon }

        return lon
    }

    private func parseMicEPosition(_ dest: String, _ info: String, into packet: inout APRSPacket) {
        // Mic-E encodes latitude in destination address
        // and longitude/course/speed in info field
        // TODO: Implement full Mic-E decoding
    }

    public func decodePacket(data: Data) -> DecodedPacket? {
        return nil
    }

    @MainActor
    public var settingsView: AnyView? {
        AnyView(APRSSettingsView(plugin: self))
    }
}

public struct APRSStation: Identifiable, Sendable {
    public var id: String { callsign }
    public let callsign: String
    public var latitude: Double?
    public var longitude: Double?
    public var altitude: Double?
    public var course: Int?
    public var speed: Int?
    public var comment: String?
    public var lastHeard: Date = Date()

    public init(callsign: String) {
        self.callsign = callsign
    }
}

public struct APRSPacket: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let source: String
    public let destination: String
    public let path: [String]
    public var packetType: APRSPacketType
    public var info: String
    public var latitude: Double?
    public var longitude: Double?
    public var altitude: Double?
    public var course: Int?
    public var speed: Int?
    public var symbolTable: Character?
    public var symbolCode: Character?
    public var comment: String?
}

public enum APRSPacketType: String, Sendable {
    case position = "Position"
    case message = "Message"
    case status = "Status"
    case object = "Object"
    case item = "Item"
    case telemetry = "Telemetry"
    case weather = "Weather"
    case micE = "Mic-E"
    case unknown = "Unknown"
}

struct AX25Frame {
    let destination: String
    let source: String
    let path: [String]
    let control: UInt8
    let pid: UInt8
    let info: Data
}

struct APRSSettingsView: View {
    @ObservedObject var plugin: APRSPlugin

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("APRS Decoder")
                .font(.headline)

            Text("Stations: \(plugin.stations.count) | Packets: \(plugin.packets.count)")

            Divider()

            Text("Recent Packets")
                .font(.subheadline)

            List(plugin.packets.prefix(50)) { packet in
                VStack(alignment: .leading) {
                    HStack {
                        Text(packet.source)
                            .font(.headline)
                        Text("→")
                        Text(packet.destination)
                        Spacer()
                        Text(packet.packetType.rawValue)
                            .font(.caption)
                            .padding(2)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }

                    if let lat = packet.latitude, let lon = packet.longitude {
                        Text("Pos: \(String(format: "%.4f", lat)), \(String(format: "%.4f", lon))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(packet.info)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding()
    }
}

// MARK: - LoRa Plugin

public final class LoRaPlugin: DecoderPlugin, ObservableObject {
    public static let identifier = "com.sdr.decoder.lora"
    public static let name = "LoRa"
    public static let version = "1.0.0"
    public static let author = "SDR Team"
    public static let description = "LoRa (Long Range) modulation decoder"
    public static let category = DecoderCategory.data

    public let id = UUID()
    public let requiredSampleRate: Double = 250000
    public let requiredBandwidth: Double = 125000
    public let centerFrequencyOffset: Double = 0

    // LoRa: Chirp Spread Spectrum (CSS)
    // ISM bands: 433 MHz (Asia), 868 MHz (Europe), 915 MHz (Americas)
    // Spreading factors: SF7-SF12, Bandwidth: 125/250/500 kHz

    @Published public var spreadingFactor: Int = 7
    @Published public var bandwidth: Double = 125000
    @Published public var packets: [LoRaPacket] = []

    public init() {}

    public func initialize() throws {
        packets.removeAll()
    }

    public func shutdown() {}

    public func process(samples: [Float], sampleRate: Double) async -> [DecodedMessage] {
        var messages: [DecodedMessage] = []

        // LoRa CSS decoding:
        // 1. Detect preamble (upchirps)
        // 2. Sync word detection
        // 3. Dechirp using matched filter
        // 4. FFT to extract symbols
        // 5. Gray code and interleaving
        // 6. FEC decoding (Hamming)
        // 7. CRC check
        // 8. Payload extraction

        // Chirp characteristics
        let symbolDuration = pow(2.0, Double(spreadingFactor)) / bandwidth
        let samplesPerSymbol = Int(sampleRate * symbolDuration)

        // TODO: Implement full LoRa decoder

        return messages
    }

    private func detectPreamble(_ samples: [Float], sampleRate: Double) -> Int? {
        // Look for sequence of upchirps
        // Minimum 8 upchirps for valid preamble
        return nil
    }

    private func dechirp(_ samples: [Float], isUpchirp: Bool) -> [Float] {
        // Multiply by conjugate chirp
        return []
    }

    @MainActor
    public var settingsView: AnyView? {
        AnyView(LoRaSettingsView(plugin: self))
    }
}

public struct LoRaPacket: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let spreadingFactor: Int
    public let bandwidth: Double
    public let rssi: Double
    public let snr: Double
    public let payload: Data
}

struct LoRaSettingsView: View {
    @ObservedObject var plugin: LoRaPlugin

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LoRa Decoder")
                .font(.headline)

            HStack {
                Text("Spreading Factor:")
                Picker("", selection: $plugin.spreadingFactor) {
                    ForEach(7..<13) { sf in
                        Text("SF\(sf)").tag(sf)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }

            HStack {
                Text("Bandwidth:")
                Picker("", selection: $plugin.bandwidth) {
                    Text("125 kHz").tag(125000.0)
                    Text("250 kHz").tag(250000.0)
                    Text("500 kHz").tag(500000.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            Divider()

            Text("Decoded Packets: \(plugin.packets.count)")

            List(plugin.packets) { packet in
                VStack(alignment: .leading) {
                    HStack {
                        Text("SF\(packet.spreadingFactor)")
                        Text("BW: \(Int(packet.bandwidth / 1000)) kHz")
                        Spacer()
                        Text("RSSI: \(Int(packet.rssi)) dBm")
                        Text("SNR: \(String(format: "%.1f", packet.snr)) dB")
                    }
                    .font(.caption)

                    Text(packet.payload.map { String(format: "%02X", $0) }.joined(separator: " "))
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
        .padding()
    }
}
