import Foundation
import SwiftUI

// MARK: - POCSAG Plugin

public final class POCSAGPlugin: DecoderPlugin, ObservableObject {
    public static let identifier = "com.sdr.decoder.pocsag"
    public static let name = "POCSAG"
    public static let version = "1.0.0"
    public static let author = "SDR Team"
    public static let description = "Post Office Code Standardisation Advisory Group"
    public static let category = DecoderCategory.paging

    public let id = UUID()
    public let requiredSampleRate: Double = 22050
    public let requiredBandwidth: Double = 12500
    public let centerFrequencyOffset: Double = 0

    // POCSAG: FSK, ±4.5 kHz deviation, 512/1200/2400 bps
    // Common frequencies: 148-149 MHz, 152-153 MHz, 157-159 MHz, 454-460 MHz

    @Published public var baudRate: Int = 1200
    @Published public var messages: [POCSAGMessage] = []

    // Sync codeword: 0x7CD215D8
    private let syncWord: UInt32 = 0x7CD215D8
    // Idle codeword: 0x7A89C197
    private let idleWord: UInt32 = 0x7A89C197

    public init() {}

    public func initialize() throws {
        messages.removeAll()
    }

    public func shutdown() {}

    public func process(samples: [Float], sampleRate: Double) async -> [DecodedMessage] {
        var decodedMessages: [DecodedMessage] = []

        // POCSAG decoding:
        // 1. FSK demodulation
        // 2. Find sync word (32 bits, repeated in preamble)
        // 3. Decode batches (sync + 8 frames, each frame = 2 codewords)
        // 4. BCH(31,21) error correction
        // 5. Extract address and message content

        let bits = demodulateNFSK(samples, sampleRate: sampleRate, deviation: 4500)

        var i = 0
        while i < bits.count - 544 {  // Minimum: sync + 1 batch
            // Look for sync word
            if matchSyncWord(bits, at: i) {
                // Found sync, process batch
                if let batch = decodeBatch(Array(bits[(i + 32)...])) {
                    for (address, messageType, content) in batch {
                        let pocsagMsg = POCSAGMessage(
                            id: UUID(),
                            timestamp: Date(),
                            address: address,
                            functionCode: messageType,
                            content: content
                        )

                        let message = DecodedMessage(
                            plugin: Self.identifier,
                            timestamp: Date(),
                            frequency: 0,
                            snr: nil,
                            content: "[\(address)] \(content)",
                            metadata: [
                                "address": "\(address)",
                                "function": "\(messageType)",
                                "baud": "\(baudRate)"
                            ]
                        )
                        decodedMessages.append(message)

                        await MainActor.run {
                            messages.insert(pocsagMsg, at: 0)
                            if messages.count > 200 {
                                messages.removeLast()
                            }
                        }
                    }
                }
                i += 544  // Skip past batch
            } else {
                i += 1
            }
        }

        return decodedMessages
    }

    private func demodulateNFSK(_ samples: [Float], sampleRate: Double, deviation: Double) -> [Int] {
        var bits: [Int] = []
        let samplesPerBit = Int(sampleRate / Double(baudRate))

        // Simple FSK discrimination
        for i in stride(from: 0, to: samples.count - samplesPerBit, by: samplesPerBit) {
            var sum: Float = 0
            for j in 0..<samplesPerBit {
                sum += samples[i + j]
            }
            bits.append(sum > 0 ? 1 : 0)
        }

        return bits
    }

    private func matchSyncWord(_ bits: [Int], at index: Int) -> Bool {
        guard index + 32 <= bits.count else { return false }

        var word: UInt32 = 0
        for i in 0..<32 {
            word = (word << 1) | UInt32(bits[index + i])
        }

        return word == syncWord
    }

    private func decodeBatch(_ bits: [Int]) -> [(address: Int, function: Int, content: String)]? {
        guard bits.count >= 512 else { return nil }  // 16 codewords × 32 bits

        var results: [(Int, Int, String)] = []
        var currentAddress: Int = 0
        var currentFunction: Int = 0
        var messageChars: [Character] = []

        for frame in 0..<8 {
            for codewordIndex in 0..<2 {
                let offset = frame * 64 + codewordIndex * 32

                var codeword: UInt32 = 0
                for i in 0..<32 {
                    if offset + i < bits.count {
                        codeword = (codeword << 1) | UInt32(bits[offset + i])
                    }
                }

                if codeword == idleWord {
                    continue
                }

                // Check if address or message codeword
                let isAddress = (codeword & 0x80000000) == 0

                if isAddress {
                    // Flush any pending message
                    if currentAddress != 0 && !messageChars.isEmpty {
                        results.append((currentAddress, currentFunction, String(messageChars)))
                        messageChars.removeAll()
                    }

                    // Address codeword: bits 31=0, 30-13=address (18 bits), 12-11=function, 10-1=BCH, 0=parity
                    let addressBits = (codeword >> 13) & 0x3FFFF
                    currentAddress = Int(addressBits) * 8 + frame  // Frame adds low 3 bits
                    currentFunction = Int((codeword >> 11) & 0x03)
                } else {
                    // Message codeword: bits 31=1, 30-11=message (20 bits), 10-1=BCH, 0=parity
                    let messageBits = (codeword >> 11) & 0xFFFFF

                    // Decode as 7-bit ASCII (for alphanumeric) or BCD (for numeric)
                    if currentFunction == 0 || currentFunction == 1 {
                        // Numeric - BCD
                        for digit in stride(from: 16, through: 0, by: -4) {
                            let bcd = Int((messageBits >> digit) & 0x0F)
                            if bcd < 10 {
                                messageChars.append(Character("\(bcd)"))
                            } else if bcd == 10 {
                                messageChars.append(" ")
                            } else if bcd == 11 {
                                messageChars.append("U")
                            } else if bcd == 12 {
                                messageChars.append(" ")
                            } else if bcd == 13 {
                                messageChars.append("-")
                            } else if bcd == 14 {
                                messageChars.append(")")
                            } else if bcd == 15 {
                                messageChars.append("(")
                            }
                        }
                    } else {
                        // Alphanumeric - 7-bit ASCII packed
                        // 20 bits = 2 chars + 6 bits
                        let char1 = (messageBits >> 13) & 0x7F
                        let char2 = (messageBits >> 6) & 0x7F
                        if char1 >= 32 && char1 < 127 {
                            messageChars.append(Character(UnicodeScalar(Int(char1))!))
                        }
                        if char2 >= 32 && char2 < 127 {
                            messageChars.append(Character(UnicodeScalar(Int(char2))!))
                        }
                    }
                }
            }
        }

        // Flush final message
        if currentAddress != 0 {
            results.append((currentAddress, currentFunction, String(messageChars)))
        }

        return results.isEmpty ? nil : results
    }

    @MainActor
    public var settingsView: AnyView? {
        AnyView(POCSAGSettingsView(plugin: self))
    }
}

public struct POCSAGMessage: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let address: Int
    public let functionCode: Int
    public let content: String
}

struct POCSAGSettingsView: View {
    @ObservedObject var plugin: POCSAGPlugin

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Baud Rate", selection: $plugin.baudRate) {
                Text("512").tag(512)
                Text("1200").tag(1200)
                Text("2400").tag(2400)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Divider()

            Text("Decoded Messages: \(plugin.messages.count)")
                .font(.headline)

            List(plugin.messages) { msg in
                VStack(alignment: .leading) {
                    HStack {
                        Text("Address: \(msg.address)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Func: \(msg.functionCode)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(msg.content)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .padding()
    }
}

// MARK: - FLEX Plugin

public final class FLEXPlugin: DecoderPlugin {
    public static let identifier = "com.sdr.decoder.flex"
    public static let name = "FLEX"
    public static let version = "1.0.0"
    public static let author = "SDR Team"
    public static let description = "Motorola FLEX paging protocol"
    public static let category = DecoderCategory.paging

    public let id = UUID()
    public let requiredSampleRate: Double = 16000
    public let requiredBandwidth: Double = 25000
    public let centerFrequencyOffset: Double = 0

    // FLEX: 1600/3200/6400 bps, 2-FSK or 4-FSK
    // Common frequencies: 929-932 MHz

    @Published public var messages: [FLEXMessage] = []

    // FLEX sync patterns
    private let sync1Pattern: UInt32 = 0xA6C6AAAA  // Sync 1 (frame info)
    private let sync2Pattern: UInt32 = 0xAAAA55E1  // Sync 2

    public init() {}

    public func initialize() throws {
        messages.removeAll()
    }

    public func shutdown() {}

    public func process(samples: [Float], sampleRate: Double) async -> [DecodedMessage] {
        var decodedMessages: [DecodedMessage] = []

        // FLEX decoding:
        // 1. 4-level FSK demodulation
        // 2. Find sync pattern
        // 3. Decode frame info word (FIW)
        // 4. Process 11 blocks per frame
        // 5. BCH error correction
        // 6. Extract address and message

        // TODO: Implement full FLEX decoder

        return decodedMessages
    }

    @MainActor
    public var settingsView: AnyView? { nil }
}

public struct FLEXMessage: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let capcode: Int
    public let messageType: FLEXMessageType
    public let content: String
}

public enum FLEXMessageType: String, Sendable {
    case alphanumeric = "Alpha"
    case numeric = "Numeric"
    case tone = "Tone"
    case unknown = "Unknown"
}
