import Foundation
import SwiftUI

// MARK: - Decoder Plugin Protocol

/// Base protocol for all decoder plugins
public protocol DecoderPlugin: AnyObject, Identifiable {
    static var identifier: String { get }
    static var name: String { get }
    static var version: String { get }
    static var author: String { get }
    static var description: String { get }
    static var category: DecoderCategory { get }

    var id: UUID { get }

    /// Required input characteristics
    var requiredSampleRate: Double { get }
    var requiredBandwidth: Double { get }
    var centerFrequencyOffset: Double { get }

    /// Plugin lifecycle
    func initialize() throws
    func shutdown()

    /// Processing - receives demodulated audio or raw I/Q
    func process(samples: [Float], sampleRate: Double) async -> [DecodedMessage]

    /// Configuration UI (optional SwiftUI view)
    @MainActor
    var settingsView: AnyView? { get }
}

// MARK: - Decoder Category

public enum DecoderCategory: String, CaseIterable, Sendable {
    case analog = "Analog"
    case voiceDigital = "Voice Digital"
    case paging = "Paging"
    case aviation = "Aviation"
    case satellite = "Satellite"
    case amateur = "Amateur"
    case weather = "Weather"
    case data = "Data"
}

// MARK: - Specialized Decoder Protocols

/// Digital mode decoder (FSK, PSK, etc.)
public protocol DigitalDecoderPlugin: DecoderPlugin {
    var modulationType: ModulationType { get }
    var symbolRate: Double { get }
    var syncPattern: [UInt8] { get }
}

/// Voice decoder (DMR, P25, etc.)
public protocol VoiceDecoderPlugin: DecoderPlugin {
    var voiceCodec: VoiceCodec { get }
    func decodeVoice(samples: [Float]) -> [Int16]  // PCM audio output
}

/// Packet decoder (AX.25, APRS, etc.)
public protocol PacketDecoderPlugin: DecoderPlugin {
    func decodePacket(data: Data) -> DecodedPacket?
}

/// Image decoder (NOAA APT, SSTV, etc.)
public protocol ImageDecoderPlugin: DecoderPlugin {
    func decodeImage(samples: [Float]) -> DecodedImage?
}

// MARK: - Supporting Types

public enum ModulationType: String, Sendable {
    case ask = "ASK"
    case fsk2 = "2FSK"
    case fsk4 = "4FSK"
    case gfsk = "GFSK"
    case gmsk = "GMSK"
    case psk = "PSK"
    case qpsk = "QPSK"
    case ofdm = "OFDM"
    case ook = "OOK"
}

public enum VoiceCodec: String, Sendable {
    case ambe = "AMBE"
    case ambe2 = "AMBE+2"
    case imbe = "IMBE"
    case codec2 = "Codec2"
    case opus = "Opus"
    case pcm = "PCM"
}

public struct DecodedPacket: Sendable {
    public let timestamp: Date
    public let rawData: Data
    public let protocol_: String
    public let fields: [String: String]

    public init(timestamp: Date = Date(), rawData: Data, protocol_: String, fields: [String: String]) {
        self.timestamp = timestamp
        self.rawData = rawData
        self.protocol_ = protocol_
        self.fields = fields
    }
}

public struct DecodedImage: Sendable {
    public let timestamp: Date
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]  // RGB or grayscale
    public let isComplete: Bool

    public init(timestamp: Date = Date(), width: Int, height: Int, pixels: [UInt8], isComplete: Bool) {
        self.timestamp = timestamp
        self.width = width
        self.height = height
        self.pixels = pixels
        self.isComplete = isComplete
    }
}

// MARK: - Plugin Error

public enum PluginError: Error, LocalizedError {
    case loadFailed(URL)
    case invalidPlugin(URL)
    case initializationFailed(String)
    case processingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .loadFailed(let url):
            return "Failed to load plugin at \(url.path)"
        case .invalidPlugin(let url):
            return "Invalid plugin at \(url.path)"
        case .initializationFailed(let reason):
            return "Plugin initialization failed: \(reason)"
        case .processingFailed(let reason):
            return "Plugin processing failed: \(reason)"
        }
    }
}
