import Foundation
import SwiftUI
import MapKit

// MARK: - ADS-B Plugin

public final class ADSBPlugin: DecoderPlugin, ObservableObject {
    public static let identifier = "com.sdr.decoder.adsb"
    public static let name = "ADS-B"
    public static let version = "1.0.0"
    public static let author = "SDR Team"
    public static let description = "ADS-B 1090 MHz aircraft tracking"
    public static let category = DecoderCategory.aviation

    public let id = UUID()
    public let requiredSampleRate: Double = 2_000_000
    public let requiredBandwidth: Double = 2_000_000
    public let centerFrequencyOffset: Double = 0

    @Published public private(set) var trackedAircraft: [String: Aircraft] = [:]
    @Published public var showOnMap: Bool = true

    private let preamble: [UInt8] = [1, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0]

    public init() {}

    public func initialize() throws {
        trackedAircraft.removeAll()
    }

    public func shutdown() {}

    public func process(samples: [Float], sampleRate: Double) async -> [DecodedMessage] {
        var messages: [DecodedMessage] = []

        // ADS-B Mode S detection
        // 1090 MHz, PPM encoding, 1µs pulses
        // Preamble: 8µs with specific pattern
        // Message: 56 or 112 bits

        // Find preambles
        let threshold: Float = 0.1
        var i = 0
        while i < samples.count - 240 {
            // Check for preamble pattern
            if detectPreamble(samples, at: i, threshold: threshold) {
                // Extract message bits
                if let messageData = extractMessage(samples, at: i + 16) {
                    // CRC check
                    if validateCRC(messageData) {
                        if let decoded = decodeMessage(messageData) {
                            messages.append(decoded)
                        }
                    }
                }
                i += 240  // Skip past this message
            } else {
                i += 1
            }
        }

        return messages
    }

    private func detectPreamble(_ samples: [Float], at index: Int, threshold: Float) -> Bool {
        guard index + 16 < samples.count else { return false }
        // Simplified preamble detection
        let p0 = samples[index] > threshold
        let p2 = samples[index + 2] > threshold
        let p7 = samples[index + 7] > threshold
        let p9 = samples[index + 9] > threshold
        return p0 && p2 && p7 && p9
    }

    private func extractMessage(_ samples: [Float], at index: Int) -> Data? {
        guard index + 224 < samples.count else { return nil }

        var bits: [UInt8] = []
        for i in stride(from: 0, to: 224, by: 2) {
            let sample = samples[index + i]
            bits.append(sample > 0 ? 1 : 0)
        }

        // Convert bits to bytes
        var bytes = Data()
        for i in stride(from: 0, to: bits.count, by: 8) {
            var byte: UInt8 = 0
            for j in 0..<8 where i + j < bits.count {
                byte = (byte << 1) | bits[i + j]
            }
            bytes.append(byte)
        }

        return bytes
    }

    private func validateCRC(_ data: Data) -> Bool {
        // Mode S CRC-24 validation
        guard data.count >= 7 else { return false }
        // Simplified - would implement full CRC-24
        return true
    }

    private func decodeMessage(_ data: Data) -> DecodedMessage? {
        guard data.count >= 7 else { return nil }

        let df = (data[0] >> 3) & 0x1F  // Downlink Format

        // Extract ICAO address
        let icao = String(format: "%02X%02X%02X", data[1], data[2], data[3])

        var content = "ICAO: \(icao)"
        var metadata: [String: String] = ["icao": icao, "df": "\(df)"]

        switch df {
        case 17, 18:  // ADS-B
            let tc = (data[4] >> 3) & 0x1F  // Type Code
            metadata["tc"] = "\(tc)"

            if tc >= 1 && tc <= 4 {
                // Aircraft identification
                if let callsign = decodeCallsign(data) {
                    content = "[\(icao)] Callsign: \(callsign)"
                    metadata["callsign"] = callsign
                    updateAircraft(icao: icao, callsign: callsign)
                }
            } else if tc >= 9 && tc <= 18 {
                // Airborne position
                if let pos = decodePosition(data, tc: tc) {
                    content = "[\(icao)] Alt: \(pos.altitude)ft Lat: \(String(format: "%.4f", pos.latitude)) Lon: \(String(format: "%.4f", pos.longitude))"
                    metadata["altitude"] = "\(pos.altitude)"
                    metadata["latitude"] = "\(pos.latitude)"
                    metadata["longitude"] = "\(pos.longitude)"
                    updateAircraft(icao: icao, altitude: pos.altitude, latitude: pos.latitude, longitude: pos.longitude)
                }
            } else if tc == 19 {
                // Airborne velocity
                if let vel = decodeVelocity(data) {
                    content = "[\(icao)] Speed: \(vel.speed)kts Hdg: \(vel.heading)°"
                    metadata["speed"] = "\(vel.speed)"
                    metadata["heading"] = "\(vel.heading)"
                    updateAircraft(icao: icao, speed: vel.speed, heading: vel.heading)
                }
            }
        default:
            content = "[\(icao)] DF\(df) message"
        }

        return DecodedMessage(
            plugin: Self.identifier,
            timestamp: Date(),
            frequency: 1090_000_000,
            snr: nil,
            content: content,
            metadata: metadata
        )
    }

    private func decodeCallsign(_ data: Data) -> String? {
        guard data.count >= 11 else { return nil }
        let charset = "?ABCDEFGHIJKLMNOPQRSTUVWXYZ????? ???????????????0123456789??????"
        var callsign = ""

        let bits = UInt64(data[4]) << 40 | UInt64(data[5]) << 32 | UInt64(data[6]) << 24 |
                   UInt64(data[7]) << 16 | UInt64(data[8]) << 8 | UInt64(data[9])

        for i in (0..<8).reversed() {
            let index = Int((bits >> (i * 6)) & 0x3F)
            let char = charset[charset.index(charset.startIndex, offsetBy: index)]
            callsign.append(char)
        }

        return callsign.trimmingCharacters(in: .whitespaces)
    }

    private func decodePosition(_ data: Data, tc: UInt8) -> (altitude: Int, latitude: Double, longitude: Double)? {
        guard data.count >= 11 else { return nil }

        // Altitude
        let altBits = (UInt16(data[5]) << 4) | (UInt16(data[6]) >> 4)
        let altitude = Int((altBits & 0x1FF0) * 25 - 1000)

        // CPR encoded lat/lon (simplified - would need odd/even frame pairing for accuracy)
        let latCpr = Double((UInt32(data[6] & 0x03) << 15) | (UInt32(data[7]) << 7) | UInt32(data[8] >> 1)) / 131072.0
        let lonCpr = Double((UInt32(data[8] & 0x01) << 16) | (UInt32(data[9]) << 8) | UInt32(data[10])) / 131072.0

        // Very rough decode (proper decode needs reference position or odd/even frames)
        let latitude = latCpr * 90.0
        let longitude = lonCpr * 180.0 - 90.0

        return (altitude, latitude, longitude)
    }

    private func decodeVelocity(_ data: Data) -> (speed: Int, heading: Int)? {
        guard data.count >= 11 else { return nil }

        let subtype = data[4] & 0x07

        if subtype == 1 || subtype == 2 {
            // Ground speed
            let ewDir = (data[5] >> 2) & 0x01
            let ewVel = Int((UInt16(data[5] & 0x03) << 8) | UInt16(data[6])) - 1
            let nsDir = (data[7] >> 7) & 0x01
            let nsVel = Int((UInt16(data[7] & 0x7F) << 3) | UInt16(data[8] >> 5)) - 1

            let vx = ewDir == 1 ? -ewVel : ewVel
            let vy = nsDir == 1 ? -nsVel : nsVel

            let speed = Int(sqrt(Double(vx * vx + vy * vy)))
            var heading = Int(atan2(Double(vx), Double(vy)) * 180 / .pi)
            if heading < 0 { heading += 360 }

            return (speed, heading)
        }

        return nil
    }

    private func updateAircraft(icao: String, callsign: String? = nil, altitude: Int? = nil,
                                latitude: Double? = nil, longitude: Double? = nil,
                                speed: Int? = nil, heading: Int? = nil) {
        Task { @MainActor in
            var aircraft = trackedAircraft[icao] ?? Aircraft(id: icao)
            if let c = callsign { aircraft.callsign = c }
            if let a = altitude { aircraft.altitude = a }
            if let lat = latitude { aircraft.latitude = lat }
            if let lon = longitude { aircraft.longitude = lon }
            if let s = speed { aircraft.groundSpeed = s }
            if let h = heading { aircraft.heading = h }
            aircraft.lastSeen = Date()
            trackedAircraft[icao] = aircraft
        }
    }

    @MainActor
    public var settingsView: AnyView? {
        AnyView(ADSBSettingsView(plugin: self))
    }
}

struct ADSBSettingsView: View {
    @ObservedObject var plugin: ADSBPlugin

    var body: some View {
        VStack {
            Toggle("Show on Map", isOn: $plugin.showOnMap)

            Text("Tracked Aircraft: \(plugin.trackedAircraft.count)")
                .font(.headline)

            List(Array(plugin.trackedAircraft.values), id: \.id) { aircraft in
                VStack(alignment: .leading) {
                    Text(aircraft.callsign ?? aircraft.id)
                        .font(.headline)
                    Text("Alt: \(aircraft.altitude ?? 0)ft | Speed: \(aircraft.groundSpeed ?? 0)kts")
                        .font(.caption)
                }
            }
        }
        .padding()
    }
}

// MARK: - Aircraft Model

public struct Aircraft: Identifiable, Sendable {
    public let id: String  // ICAO 24-bit address
    public var callsign: String?
    public var latitude: Double?
    public var longitude: Double?
    public var altitude: Int?       // feet
    public var groundSpeed: Int?    // knots
    public var heading: Int?        // degrees
    public var verticalRate: Int?   // ft/min
    public var squawk: String?
    public var lastSeen: Date

    public init(id: String) {
        self.id = id
        self.lastSeen = Date()
    }
}

// MARK: - ACARS Plugin

public final class ACARSPlugin: DecoderPlugin {
    public static let identifier = "com.sdr.decoder.acars"
    public static let name = "ACARS"
    public static let version = "1.0.0"
    public static let author = "SDR Team"
    public static let description = "Aircraft Communications Addressing and Reporting System"
    public static let category = DecoderCategory.aviation

    public let id = UUID()
    public let requiredSampleRate: Double = 48000
    public let requiredBandwidth: Double = 12500
    public let centerFrequencyOffset: Double = 0

    // ACARS frequencies: 131.550, 131.725, 131.450, 130.025, 130.450 MHz

    public init() {}

    public func initialize() throws {}
    public func shutdown() {}

    public func process(samples: [Float], sampleRate: Double) async -> [DecodedMessage] {
        // ACARS uses AM-MSK at 2400 bps
        // Pre-key tone: 1800 Hz
        // Sync: ++++++
        // SOH (0x01) starts message

        var messages: [DecodedMessage] = []

        // TODO: Implement full ACARS decoder
        // 1. Detect 1800 Hz pre-key tone
        // 2. Look for sync sequence
        // 3. Decode MSK symbols
        // 4. Extract and validate message

        return messages
    }

    @MainActor
    public var settingsView: AnyView? { nil }
}
