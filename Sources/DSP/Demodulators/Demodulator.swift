import Foundation
import Accelerate

// MARK: - Demodulator Protocol

/// Base protocol for all demodulators
public protocol Demodulator {
    var name: String { get }

    /// Demodulate I/Q samples to audio
    func demodulate(_ samples: [ComplexFloat], sampleRate: Double) -> [Float]

    /// Reset internal state
    func reset()
}

// MARK: - AM Demodulator

/// Amplitude Modulation demodulator
public final class AMDemodulator: Demodulator {
    public let name = "AM"

    private var dcOffset: Float = 0
    private let dcAlpha: Float = 0.001  // DC blocking filter coefficient

    public init() {}

    public func demodulate(_ samples: [ComplexFloat], sampleRate: Double) -> [Float] {
        var output = [Float](repeating: 0, count: samples.count)

        // AM demodulation: envelope detection (magnitude)
        for i in 0..<samples.count {
            let magnitude = samples[i].magnitude

            // DC blocking filter
            dcOffset = dcOffset * (1 - dcAlpha) + magnitude * dcAlpha
            output[i] = magnitude - dcOffset
        }

        return output
    }

    public func reset() {
        dcOffset = 0
    }
}

// MARK: - FM Demodulator

/// Frequency Modulation demodulator using phase differentiation
public final class FMDemodulator: Demodulator {
    public let name = "FM"

    private var previousPhase: Float = 0
    private let bandwidth: Double
    private var deemphasisState: Float = 0
    private let deemphasisAlpha: Float

    public init(bandwidth: Double, deemphasis: Double? = 75e-6) {
        self.bandwidth = bandwidth

        // Calculate de-emphasis filter coefficient
        if let tau = deemphasis {
            // Assuming 48kHz audio sample rate
            let fc = 1.0 / (2.0 * .pi * tau)
            let dt = 1.0 / 48000.0
            deemphasisAlpha = Float(dt / (dt + 1.0 / (2.0 * .pi * fc)))
        } else {
            deemphasisAlpha = 1.0  // No de-emphasis
        }
    }

    public func demodulate(_ samples: [ComplexFloat], sampleRate: Double) -> [Float] {
        var output = [Float](repeating: 0, count: samples.count)

        // FM demodulation: phase differentiation (arctan method)
        for i in 0..<samples.count {
            let phase = atan2(samples[i].imag, samples[i].real)
            var phaseDiff = phase - previousPhase

            // Phase unwrapping
            if phaseDiff > .pi {
                phaseDiff -= 2 * .pi
            } else if phaseDiff < -.pi {
                phaseDiff += 2 * .pi
            }

            // Normalize output to [-1, 1]
            output[i] = phaseDiff / .pi

            previousPhase = phase
        }

        // Apply de-emphasis filter (lowpass)
        for i in 0..<output.count {
            deemphasisState = deemphasisState + deemphasisAlpha * (output[i] - deemphasisState)
            output[i] = deemphasisState
        }

        return output
    }

    public func reset() {
        previousPhase = 0
        deemphasisState = 0
    }
}

// MARK: - SSB Demodulator

/// Single Side Band demodulator
public final class SSBDemodulator: Demodulator {
    public enum Sideband {
        case upper  // USB
        case lower  // LSB
    }

    public var name: String {
        sideband == .upper ? "USB" : "LSB"
    }

    private let sideband: Sideband
    private var hilbertState: [ComplexFloat] = []

    public init(sideband: Sideband) {
        self.sideband = sideband
    }

    public func demodulate(_ samples: [ComplexFloat], sampleRate: Double) -> [Float] {
        var output = [Float](repeating: 0, count: samples.count)

        // SSB demodulation using Weaver method approximation
        // For USB: take real part directly (after proper filtering)
        // For LSB: conjugate first

        for i in 0..<samples.count {
            switch sideband {
            case .upper:
                // USB: Real part of I + jQ after frequency shift
                output[i] = samples[i].real
            case .lower:
                // LSB: Real part of I - jQ (conjugate)
                output[i] = samples[i].real
            }
        }

        return output
    }

    public func reset() {
        hilbertState.removeAll()
    }
}

// MARK: - CW Demodulator

/// Continuous Wave (Morse) demodulator with beat frequency oscillator
public final class CWDemodulator: Demodulator {
    public let name = "CW"

    private let toneFrequency: Double
    private var oscillatorPhase: Double = 0

    public init(toneFrequency: Double = 700) {
        self.toneFrequency = toneFrequency
    }

    public func demodulate(_ samples: [ComplexFloat], sampleRate: Double) -> [Float] {
        var output = [Float](repeating: 0, count: samples.count)

        let phaseIncrement = 2 * Double.pi * toneFrequency / sampleRate

        // CW demodulation: mix with BFO (beat frequency oscillator)
        for i in 0..<samples.count {
            let bfoI = Float(cos(oscillatorPhase))
            let bfoQ = Float(sin(oscillatorPhase))

            // Mix signal with BFO
            output[i] = samples[i].real * bfoI + samples[i].imag * bfoQ

            oscillatorPhase += phaseIncrement
            if oscillatorPhase >= 2 * Double.pi {
                oscillatorPhase -= 2 * Double.pi
            }
        }

        return output
    }

    public func reset() {
        oscillatorPhase = 0
    }
}
