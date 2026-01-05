import Foundation

// MARK: - SDR Device Protocol

/// Protocol defining the interface for all SDR hardware devices
public protocol SDRDevice: AnyObject, Identifiable {
    var id: String { get }
    var name: String { get }
    var driver: String { get }
    var isConnected: Bool { get }
    var capabilities: DeviceCapabilities { get }

    // Configuration
    var centerFrequency: Double { get set }
    var sampleRate: Double { get set }
    var bandwidth: Double { get set }
    var gain: Double { get set }
    var gainMode: GainMode { get set }
    var antenna: String { get set }

    // Corrections
    var dcOffsetCorrection: Bool { get set }
    var iqBalanceCorrection: Bool { get set }
    var ppmCorrection: Double { get set }

    // Streaming
    func startStreaming() throws
    func stopStreaming()
    var isStreaming: Bool { get }

    // Sample reading
    func readSamples(into buffer: UnsafeMutablePointer<ComplexFloat>, count: Int) -> Int

    // Async sample stream
    var sampleStream: AsyncStream<IQSampleBuffer> { get }

    // Cleanup
    func close()
}

// MARK: - Device Capabilities

/// Device capabilities descriptor
public struct DeviceCapabilities: Sendable {
    public let frequencyRange: ClosedRange<Double>  // Hz
    public let sampleRateRange: ClosedRange<Double>  // Hz
    public let bandwidthRange: ClosedRange<Double>  // Hz
    public let gainRange: ClosedRange<Double>  // dB
    public let supportedAntennas: [String]
    public let hasDCOffsetCorrection: Bool
    public let hasIQBalanceCorrection: Bool
    public let hasHardwareAGC: Bool
    public let maxBandwidth: Double
    public let supportsTransmit: Bool
    public let nativeFormat: SampleFormat

    public init(
        frequencyRange: ClosedRange<Double> = 24_000_000...1_700_000_000,
        sampleRateRange: ClosedRange<Double> = 225_001...3_200_000,
        bandwidthRange: ClosedRange<Double> = 0...3_200_000,
        gainRange: ClosedRange<Double> = 0...49.6,
        supportedAntennas: [String] = ["RX"],
        hasDCOffsetCorrection: Bool = true,
        hasIQBalanceCorrection: Bool = false,
        hasHardwareAGC: Bool = true,
        maxBandwidth: Double = 3_200_000,
        supportsTransmit: Bool = false,
        nativeFormat: SampleFormat = .complexUInt8
    ) {
        self.frequencyRange = frequencyRange
        self.sampleRateRange = sampleRateRange
        self.bandwidthRange = bandwidthRange
        self.gainRange = gainRange
        self.supportedAntennas = supportedAntennas
        self.hasDCOffsetCorrection = hasDCOffsetCorrection
        self.hasIQBalanceCorrection = hasIQBalanceCorrection
        self.hasHardwareAGC = hasHardwareAGC
        self.maxBandwidth = maxBandwidth
        self.supportsTransmit = supportsTransmit
        self.nativeFormat = nativeFormat
    }

    /// Default capabilities for RTL-SDR
    public static var rtlsdr: DeviceCapabilities {
        DeviceCapabilities(
            frequencyRange: 24_000_000...1_766_000_000,
            sampleRateRange: 225_001...3_200_000,
            bandwidthRange: 0...3_200_000,
            gainRange: 0...49.6,
            supportedAntennas: ["RX"],
            hasDCOffsetCorrection: true,
            hasIQBalanceCorrection: false,
            hasHardwareAGC: true,
            maxBandwidth: 3_200_000,
            supportsTransmit: false,
            nativeFormat: .complexUInt8
        )
    }

    /// Default capabilities for HackRF
    public static var hackrf: DeviceCapabilities {
        DeviceCapabilities(
            frequencyRange: 1_000_000...6_000_000_000,
            sampleRateRange: 2_000_000...20_000_000,
            bandwidthRange: 1_750_000...28_000_000,
            gainRange: 0...62,
            supportedAntennas: ["TX/RX", "RX"],
            hasDCOffsetCorrection: true,
            hasIQBalanceCorrection: true,
            hasHardwareAGC: false,
            maxBandwidth: 20_000_000,
            supportsTransmit: true,
            nativeFormat: .complexInt8
        )
    }
}

// MARK: - Supporting Types

/// Gain control mode
public enum GainMode: String, CaseIterable, Sendable {
    case manual = "Manual"
    case automatic = "AGC"
}

/// Sample format from SDR
public enum SampleFormat: String, Sendable {
    case complexFloat32 = "CF32"
    case complexInt16 = "CS16"
    case complexInt8 = "CS8"
    case complexUInt8 = "CU8"
}

/// SDR device errors
public enum SDRDeviceError: Error, LocalizedError {
    case deviceNotFound
    case connectionFailed(String)
    case streamingFailed(String)
    case configurationFailed(String)
    case unsupportedOperation(String)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "SDR device not found"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .streamingFailed(let reason):
            return "Streaming failed: \(reason)"
        case .configurationFailed(let reason):
            return "Configuration failed: \(reason)"
        case .unsupportedOperation(let operation):
            return "Unsupported operation: \(operation)"
        case .timeout:
            return "Operation timed out"
        }
    }
}

// MARK: - Device Info

/// Information about a detected SDR device
public struct SDRDeviceInfo: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let driver: String
    public let serial: String?
    public let product: String?

    public init(id: String, name: String, driver: String, serial: String? = nil, product: String? = nil) {
        self.id = id
        self.name = name
        self.driver = driver
        self.serial = serial
        self.product = product
    }
}
