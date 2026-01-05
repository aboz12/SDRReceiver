import Foundation
import SwiftUI

// MARK: - FT8 Plugin

public final class FT8Plugin: DecoderPlugin, ObservableObject {
    public static let identifier = "com.sdr.decoder.ft8"
    public static let name = "FT8"
    public static let version = "1.0.0"
    public static let author = "SDR Team"
    public static let description = "FT8 weak signal digital mode"
    public static let category = DecoderCategory.amateur

    public let id = UUID()
    public let requiredSampleRate: Double = 12000
    public let requiredBandwidth: Double = 3000
    public let centerFrequencyOffset: Double = 1500

    // FT8: 8-GFSK, 6.25 baud, 15 second transmit cycle
    // 79 symbols per transmission, ~50 Hz bandwidth
    // Frequencies: 1840, 3573, 7074, 10136, 14074, 18100, 21074, 24915, 28074 kHz

    @Published public var decodedMessages: [FT8Message] = []
    private var audioBuffer: [Float] = []
    private let symbolsPerMessage = 79
    private let toneSpacing: Double = 6.25
    private let symbolPeriod: Double = 0.160  // 160ms per symbol

    public init() {}

    public func initialize() throws {
        decodedMessages.removeAll()
        audioBuffer.removeAll()
    }

    public func shutdown() {}

    public func process(samples: [Float], sampleRate: Double) async -> [DecodedMessage] {
        var messages: [DecodedMessage] = []

        // Accumulate samples for 15-second window
        audioBuffer.append(contentsOf: samples)

        // FT8 requires ~13 seconds of audio per decode cycle
        let requiredSamples = Int(sampleRate * 13.0)

        if audioBuffer.count >= requiredSamples {
            // Process accumulated audio
            let processBuffer = Array(audioBuffer.prefix(requiredSamples))
            audioBuffer.removeFirst(requiredSamples)

            // Find FT8 signals
            let candidates = findFT8Candidates(processBuffer, sampleRate: sampleRate)

            for candidate in candidates {
                if let decoded = decodeFT8Signal(candidate, sampleRate: sampleRate) {
                    let message = DecodedMessage(
                        plugin: Self.identifier,
                        timestamp: Date(),
                        frequency: 0,
                        snr: Float(decoded.snr),
                        content: decoded.message,
                        metadata: [
                            "dt": String(format: "%.1f", decoded.dt),
                            "freq": String(format: "%.0f", decoded.audioFreq),
                            "callsign1": decoded.callsign1 ?? "",
                            "callsign2": decoded.callsign2 ?? "",
                            "grid": decoded.grid ?? ""
                        ]
                    )
                    messages.append(message)

                    await MainActor.run {
                        decodedMessages.insert(decoded, at: 0)
                        if decodedMessages.count > 100 {
                            decodedMessages.removeLast()
                        }
                    }
                }
            }
        }

        return messages
    }

    private func findFT8Candidates(_ samples: [Float], sampleRate: Double) -> [(frequency: Double, samples: [Float])] {
        // FFT-based candidate detection
        // Look for signals in 0-3000 Hz audio bandwidth
        // FT8 signals are ~50 Hz wide

        var candidates: [(frequency: Double, samples: [Float])] = []

        // Simplified: divide spectrum into bins and look for power
        let fftSize = 4096
        let binWidth = sampleRate / Double(fftSize)

        // In real implementation:
        // 1. Compute spectrogram over 15 seconds
        // 2. Find time-frequency traces matching FT8 signature
        // 3. Extract candidate signals

        return candidates
    }

    private func decodeFT8Signal(_ candidate: (frequency: Double, samples: [Float]), sampleRate: Double) -> FT8Message? {
        // FT8 decoding:
        // 1. Sync using Costas arrays at start, middle, end
        // 2. Extract 58 data symbols + 21 sync symbols = 79 total
        // 3. Soft-decision LDPC decoding
        // 4. Extract 77-bit payload
        // 5. Unpack message fields

        // Costas sync pattern: 3,1,4,0,6,5,2 (repeated 3 times in message)

        return nil
    }

    @MainActor
    public var settingsView: AnyView? {
        AnyView(FT8SettingsView(plugin: self))
    }
}

public struct FT8Message: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let snr: Double
    public let dt: Double  // Time offset
    public let audioFreq: Double
    public let message: String
    public let callsign1: String?
    public let callsign2: String?
    public let grid: String?

    public init(id: UUID = UUID(), timestamp: Date = Date(), snr: Double, dt: Double,
                audioFreq: Double, message: String, callsign1: String? = nil,
                callsign2: String? = nil, grid: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.snr = snr
        self.dt = dt
        self.audioFreq = audioFreq
        self.message = message
        self.callsign1 = callsign1
        self.callsign2 = callsign2
        self.grid = grid
    }
}

struct FT8SettingsView: View {
    @ObservedObject var plugin: FT8Plugin

    var body: some View {
        VStack(alignment: .leading) {
            Text("FT8 Decoded Messages")
                .font(.headline)

            List(plugin.decodedMessages) { msg in
                VStack(alignment: .leading) {
                    Text(msg.message)
                        .font(.system(.body, design: .monospaced))
                    HStack {
                        Text("SNR: \(Int(msg.snr)) dB")
                        Text("Freq: \(Int(msg.audioFreq)) Hz")
                        Text("DT: \(String(format: "%.1f", msg.dt))s")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }
}

// MARK: - FT4 Plugin

public final class FT4Plugin: DecoderPlugin {
    public static let identifier = "com.sdr.decoder.ft4"
    public static let name = "FT4"
    public static let version = "1.0.0"
    public static let author = "SDR Team"
    public static let description = "FT4 fast digital mode (contest)"
    public static let category = DecoderCategory.amateur

    public let id = UUID()
    public let requiredSampleRate: Double = 12000
    public let requiredBandwidth: Double = 3000
    public let centerFrequencyOffset: Double = 1500

    // FT4: 4-GFSK, 20.8333 baud, 7.5 second cycle
    // 105 symbols, ~90 Hz bandwidth

    public init() {}

    public func initialize() throws {}
    public func shutdown() {}

    public func process(samples: [Float], sampleRate: Double) async -> [DecodedMessage] {
        // Similar to FT8 but faster
        // 7.5 second transmit cycle vs 15 seconds
        return []
    }

    @MainActor
    public var settingsView: AnyView? { nil }
}

// MARK: - WSPR Plugin

public final class WSPRPlugin: DecoderPlugin {
    public static let identifier = "com.sdr.decoder.wspr"
    public static let name = "WSPR"
    public static let version = "1.0.0"
    public static let author = "SDR Team"
    public static let description = "Weak Signal Propagation Reporter"
    public static let category = DecoderCategory.amateur

    public let id = UUID()
    public let requiredSampleRate: Double = 12000
    public let requiredBandwidth: Double = 200
    public let centerFrequencyOffset: Double = 1500

    // WSPR: 4-FSK, 1.4648 baud, 2 minute transmit cycle
    // 162 symbols, ~6 Hz bandwidth
    // Frequencies: 136 kHz, 474 kHz, 1836 kHz, 3568 kHz, 7038 kHz, etc.

    @Published public var spots: [WSPRSpot] = []
    private var audioBuffer: [Float] = []

    public init() {}

    public func initialize() throws {
        spots.removeAll()
        audioBuffer.removeAll()
    }

    public func shutdown() {}

    public func process(samples: [Float], sampleRate: Double) async -> [DecodedMessage] {
        var messages: [DecodedMessage] = []

        // Accumulate 2 minutes of audio
        audioBuffer.append(contentsOf: samples)

        let requiredSamples = Int(sampleRate * 120)  // 2 minutes

        if audioBuffer.count >= requiredSamples {
            let processBuffer = Array(audioBuffer.prefix(requiredSamples))
            audioBuffer.removeFirst(requiredSamples)

            // WSPR decoding:
            // 1. FFT to find candidates in 200 Hz bandwidth
            // 2. Extract 4-FSK symbols (1.4648 baud)
            // 3. Convolutional decoding (K=32, r=1/2)
            // 4. Extract 50-bit message: callsign, grid, power

            // TODO: Implement full WSPR decoder
        }

        return messages
    }

    @MainActor
    public var settingsView: AnyView? { nil }
}

public struct WSPRSpot: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let callsign: String
    public let grid: String
    public let power: Int  // dBm
    public let snr: Double
    public let frequency: Double
    public let drift: Double
}

// MARK: - PSK31 Plugin

public final class PSK31Plugin: DecoderPlugin, ObservableObject {
    public static let identifier = "com.sdr.decoder.psk31"
    public static let name = "PSK31"
    public static let version = "1.0.0"
    public static let author = "SDR Team"
    public static let description = "Phase Shift Keying 31.25 baud"
    public static let category = DecoderCategory.amateur

    public let id = UUID()
    public let requiredSampleRate: Double = 8000
    public let requiredBandwidth: Double = 500
    public let centerFrequencyOffset: Double = 1000

    // PSK31: BPSK or QPSK, 31.25 baud
    // Varicode encoding, ~62.5 Hz bandwidth

    @Published public var decodedText: String = ""
    private var phaseHistory: [Float] = []
    private var bitBuffer: [Int] = []

    public init() {}

    public func initialize() throws {
        decodedText = ""
        phaseHistory.removeAll()
        bitBuffer.removeAll()
    }

    public func shutdown() {}

    public func process(samples: [Float], sampleRate: Double) async -> [DecodedMessage] {
        var messages: [DecodedMessage] = []

        // PSK31 decoding:
        // 1. Carrier recovery (Costas loop PLL)
        // 2. Symbol timing recovery
        // 3. BPSK differential decoding
        // 4. Varicode to ASCII conversion

        let symbolRate = 31.25
        let samplesPerSymbol = Int(sampleRate / symbolRate)

        // TODO: Implement full PSK31 decoder

        return messages
    }

    private func varicodeToChar(_ bits: [Int]) -> Character? {
        // Varicode lookup table (partial)
        let varicode: [String: Character] = [
            "1010101011": " ",
            "1011011011": "A",
            "1011010101": "B",
            "10110101": "C",
            "10110111": "D",
            "11": "E",
            // ... etc
        ]

        let bitString = bits.map { String($0) }.joined()
        return varicode[bitString]
    }

    @MainActor
    public var settingsView: AnyView? {
        AnyView(PSK31SettingsView(plugin: self))
    }
}

struct PSK31SettingsView: View {
    @ObservedObject var plugin: PSK31Plugin

    var body: some View {
        VStack(alignment: .leading) {
            Text("PSK31 Decoded Text")
                .font(.headline)

            ScrollView {
                Text(plugin.decodedText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 200)
            .border(Color.gray, width: 1)
        }
        .padding()
    }
}

// MARK: - RTTY Plugin

public final class RTTYPlugin: DecoderPlugin, ObservableObject {
    public static let identifier = "com.sdr.decoder.rtty"
    public static let name = "RTTY"
    public static let version = "1.0.0"
    public static let author = "SDR Team"
    public static let description = "Radio Teletype (45.45 baud)"
    public static let category = DecoderCategory.amateur

    public let id = UUID()
    public let requiredSampleRate: Double = 8000
    public let requiredBandwidth: Double = 500
    public let centerFrequencyOffset: Double = 1000

    // RTTY: FSK with 170 Hz shift, 45.45 baud (also 50, 75, 100 baud)
    // 5-bit Baudot code, mark = 2125 Hz, space = 2295 Hz

    @Published public var baudRate: Double = 45.45
    @Published public var shift: Double = 170
    @Published public var decodedText: String = ""

    private var letterShift = true  // LTRS vs FIGS mode

    public init() {}

    public func initialize() throws {
        decodedText = ""
        letterShift = true
    }

    public func shutdown() {}

    public func process(samples: [Float], sampleRate: Double) async -> [DecodedMessage] {
        var messages: [DecodedMessage] = []

        // RTTY decoding:
        // 1. FSK demodulation (discriminator or two-filter method)
        // 2. Bit clock recovery
        // 3. Start/stop bit detection (1 start, 5 data, 1.5 stop)
        // 4. Baudot to ASCII conversion

        // TODO: Implement full RTTY decoder

        return messages
    }

    private func baudotToChar(_ code: UInt8) -> Character? {
        // ITA2 Baudot code tables
        let letters = [
            0x00: "\0", 0x01: "E", 0x02: "\n", 0x03: "A", 0x04: " ", 0x05: "S",
            0x06: "I", 0x07: "U", 0x08: "\r", 0x09: "D", 0x0A: "R", 0x0B: "J",
            0x0C: "N", 0x0D: "F", 0x0E: "C", 0x0F: "K", 0x10: "T", 0x11: "Z",
            0x12: "L", 0x13: "W", 0x14: "H", 0x15: "Y", 0x16: "P", 0x17: "Q",
            0x18: "O", 0x19: "B", 0x1A: "G", 0x1B: "", 0x1C: "M", 0x1D: "X",
            0x1E: "V", 0x1F: ""
        ]

        let figures = [
            0x00: "\0", 0x01: "3", 0x02: "\n", 0x03: "-", 0x04: " ", 0x05: "'",
            0x06: "8", 0x07: "7", 0x08: "\r", 0x09: "$", 0x0A: "4", 0x0B: "'",
            0x0C: ",", 0x0D: "!", 0x0E: ":", 0x0F: "(", 0x10: "5", 0x11: "+",
            0x12: ")", 0x13: "2", 0x14: "#", 0x15: "6", 0x16: "0", 0x17: "1",
            0x18: "9", 0x19: "?", 0x1A: "&", 0x1B: "", 0x1C: ".", 0x1D: "/",
            0x1E: ";", 0x1F: ""
        ]

        if code == 0x1B {  // LTRS
            letterShift = true
            return nil
        } else if code == 0x1F {  // FIGS
            letterShift = false
            return nil
        }

        let table = letterShift ? letters : figures
        if let str = table[Int(code)], let char = str.first {
            return char
        }
        return nil
    }

    @MainActor
    public var settingsView: AnyView? {
        AnyView(RTTYSettingsView(plugin: self))
    }
}

struct RTTYSettingsView: View {
    @ObservedObject var plugin: RTTYPlugin

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Baud Rate:")
                Picker("", selection: $plugin.baudRate) {
                    Text("45.45").tag(Double(45.45))
                    Text("50").tag(Double(50.0))
                    Text("75").tag(Double(75.0))
                    Text("100").tag(Double(100.0))
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            HStack {
                Text("Shift:")
                Picker("", selection: $plugin.shift) {
                    Text("170 Hz").tag(Double(170.0))
                    Text("425 Hz").tag(Double(425.0))
                    Text("850 Hz").tag(Double(850.0))
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            Divider()

            Text("Decoded Text")
                .font(.headline)

            ScrollView {
                Text(plugin.decodedText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 200)
            .border(Color.gray, width: 1)
        }
        .padding()
    }
}
