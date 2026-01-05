import Foundation
import SwiftUI

// MARK: - Complex Number

/// Complex number for I/Q samples
public struct ComplexFloat: Sendable {
    public var real: Float
    public var imag: Float

    public init(real: Float = 0, imag: Float = 0) {
        self.real = real
        self.imag = imag
    }

    public var magnitude: Float {
        sqrt(real * real + imag * imag)
    }

    public var phase: Float {
        atan2(imag, real)
    }

    public var magnitudeSquared: Float {
        real * real + imag * imag
    }

    public static func + (lhs: ComplexFloat, rhs: ComplexFloat) -> ComplexFloat {
        ComplexFloat(real: lhs.real + rhs.real, imag: lhs.imag + rhs.imag)
    }

    public static func * (lhs: ComplexFloat, rhs: ComplexFloat) -> ComplexFloat {
        ComplexFloat(
            real: lhs.real * rhs.real - lhs.imag * rhs.imag,
            imag: lhs.real * rhs.imag + lhs.imag * rhs.real
        )
    }

    public func conjugate() -> ComplexFloat {
        ComplexFloat(real: real, imag: -imag)
    }
}

// MARK: - I/Q Sample Buffer

/// Buffer of I/Q samples from SDR
public struct IQSampleBuffer: Sendable {
    public let samples: [ComplexFloat]
    public let timestamp: UInt64  // nanoseconds
    public let centerFrequency: Double
    public let sampleRate: Double
    public let overflowDetected: Bool

    public init(
        samples: [ComplexFloat],
        timestamp: UInt64 = 0,
        centerFrequency: Double = 0,
        sampleRate: Double = 0,
        overflowDetected: Bool = false
    ) {
        self.samples = samples
        self.timestamp = timestamp
        self.centerFrequency = centerFrequency
        self.sampleRate = sampleRate
        self.overflowDetected = overflowDetected
    }

    public var count: Int { samples.count }
    public var isEmpty: Bool { samples.isEmpty }
}

// MARK: - Demodulation Modes

/// Available demodulation modes
public enum DemodulationMode: String, CaseIterable, Sendable {
    case am = "AM"
    case fm = "FM"
    case wfm = "WFM"
    case lsb = "LSB"
    case usb = "USB"
    case cw = "CW"
    case raw = "RAW"

    public var shortcut: KeyEquivalent {
        switch self {
        case .am: return "1"
        case .fm: return "2"
        case .wfm: return "3"
        case .lsb: return "4"
        case .usb: return "5"
        case .cw: return "6"
        case .raw: return "7"
        }
    }

    public var defaultBandwidth: Double {
        switch self {
        case .am: return 10000
        case .fm: return 12500
        case .wfm: return 200000
        case .lsb, .usb: return 2700
        case .cw: return 500
        case .raw: return 48000
        }
    }
}

// MARK: - Spectrum Data

/// FFT spectrum data for display
public struct SpectrumData: Sendable {
    public let magnitudes: [Float]  // dB values
    public let fftSize: Int
    public let centerFrequency: Double
    public let sampleRate: Double
    public let timestamp: Date

    public init(
        magnitudes: [Float],
        fftSize: Int,
        centerFrequency: Double = 0,
        sampleRate: Double = 0,
        timestamp: Date = Date()
    ) {
        self.magnitudes = magnitudes
        self.fftSize = fftSize
        self.centerFrequency = centerFrequency
        self.sampleRate = sampleRate
        self.timestamp = timestamp
    }

    public static var empty: SpectrumData {
        SpectrumData(magnitudes: [], fftSize: 0)
    }

    public var isEmpty: Bool { magnitudes.isEmpty }

    /// Frequency at a given bin index
    public func frequency(at binIndex: Int) -> Double {
        let binWidth = sampleRate / Double(fftSize)
        let offset = Double(binIndex - fftSize / 2) * binWidth
        return centerFrequency + offset
    }
}

// MARK: - Waterfall Line

/// Single line of waterfall display
public struct WaterfallLine: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let magnitudes: [Float]
    public let timestamp: Date
    public let centerFrequency: Double

    public init(magnitudes: [Float], timestamp: Date = Date(), centerFrequency: Double = 0) {
        self.id = UUID()
        self.magnitudes = magnitudes
        self.timestamp = timestamp
        self.centerFrequency = centerFrequency
    }

    public init(from spectrum: SpectrumData) {
        self.id = UUID()
        self.magnitudes = spectrum.magnitudes
        self.timestamp = spectrum.timestamp
        self.centerFrequency = spectrum.centerFrequency
    }
}

// MARK: - Decoded Message

/// Message decoded by a decoder plugin
public struct DecodedMessage: Identifiable, Sendable {
    public let id: UUID
    public let plugin: String
    public let timestamp: Date
    public let frequency: Double
    public let snr: Float?
    public let content: String
    public let metadata: [String: String]

    public init(
        id: UUID = UUID(),
        plugin: String,
        timestamp: Date = Date(),
        frequency: Double = 0,
        snr: Float? = nil,
        content: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.plugin = plugin
        self.timestamp = timestamp
        self.frequency = frequency
        self.snr = snr
        self.content = content
        self.metadata = metadata
    }
}

// MARK: - Frequency Formatter

/// Format frequency values for display
public struct FrequencyFormatter {
    public static func format(_ frequency: Double) -> String {
        if frequency >= 1_000_000_000 {
            return String(format: "%.6f GHz", frequency / 1_000_000_000)
        } else if frequency >= 1_000_000 {
            return String(format: "%.6f MHz", frequency / 1_000_000)
        } else if frequency >= 1000 {
            return String(format: "%.3f kHz", frequency / 1000)
        } else {
            return String(format: "%.0f Hz", frequency)
        }
    }

    public static func formatShort(_ frequency: Double) -> String {
        if frequency >= 1_000_000_000 {
            return String(format: "%.3f GHz", frequency / 1_000_000_000)
        } else if frequency >= 1_000_000 {
            return String(format: "%.3f MHz", frequency / 1_000_000)
        } else {
            return String(format: "%.1f kHz", frequency / 1000)
        }
    }
}

// MARK: - Signal Strength

/// Signal strength measurement
public struct SignalStrength: Sendable {
    public let rssi: Float  // dBm
    public let snr: Float?  // dB

    public init(rssi: Float, snr: Float? = nil) {
        self.rssi = rssi
        self.snr = snr
    }

    /// S-meter reading (S0-S9+)
    public var sMeter: String {
        // S9 = -73 dBm, each S unit = 6 dB
        let sUnits = (rssi + 73) / 6 + 9
        if sUnits >= 9 {
            let over = Int((sUnits - 9) * 10)
            return over > 0 ? "S9+\(over)" : "S9"
        } else {
            return "S\(max(0, Int(sUnits)))"
        }
    }
}
