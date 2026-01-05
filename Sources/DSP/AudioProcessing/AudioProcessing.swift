import Foundation
import Accelerate
import SwiftUI

// MARK: - Noise Reduction

@MainActor
public final class NoiseReduction: ObservableObject {
    @Published public var enabled: Bool = false
    @Published public var strength: Float = 0.5 // 0.0 to 1.0
    @Published public var algorithm: NoiseReductionAlgorithm = .spectralSubtraction

    public enum NoiseReductionAlgorithm: String, CaseIterable {
        case spectralSubtraction = "Spectral Subtraction"
        case wienerFilter = "Wiener Filter"
        case adaptive = "Adaptive"
    }

    // Noise floor estimation
    private var noiseFloor: [Float] = []
    private var noiseFloorUpdateRate: Float = 0.01

    public init() {}

    public func process(_ samples: [Float], sampleRate: Double) -> [Float] {
        guard enabled, !samples.isEmpty else { return samples }

        switch algorithm {
        case .spectralSubtraction:
            return spectralSubtraction(samples, sampleRate: sampleRate)
        case .wienerFilter:
            return wienerFilter(samples)
        case .adaptive:
            return adaptiveNR(samples)
        }
    }

    private func spectralSubtraction(_ samples: [Float], sampleRate: Double) -> [Float] {
        let fftSize = 1024
        guard samples.count >= fftSize else { return samples }

        var output = samples

        // Simple spectral subtraction approach
        // In a full implementation, this would use FFT-based processing
        let alpha = strength * 2.0

        // Apply simple noise gate as approximation
        var threshold: Float = 0
        vDSP_rmsqv(samples, 1, &threshold, vDSP_Length(samples.count))
        threshold *= (1.0 - strength) * 0.5

        for i in 0..<output.count {
            if abs(output[i]) < threshold {
                output[i] *= (1.0 - strength * 0.8)
            }
        }

        return output
    }

    private func wienerFilter(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }

        var output = samples

        // Estimate signal and noise power
        var signalPower: Float = 0
        vDSP_measqv(samples, 1, &signalPower, vDSP_Length(samples.count))

        // Estimate noise power from quiet sections
        let noisePower = signalPower * (1.0 - strength) * 0.1

        // Wiener gain
        let gain = max(0.1, (signalPower - noisePower) / max(signalPower, 0.0001))

        // Apply gain
        var gainVal = gain
        vDSP_vsmul(samples, 1, &gainVal, &output, 1, vDSP_Length(samples.count))

        return output
    }

    private func adaptiveNR(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }

        var output = samples

        // Simple LMS-like adaptive filter
        var mu = strength * 0.01
        var error: Float = 0

        for i in 1..<output.count {
            let predicted = output[i-1]
            error = output[i] - predicted
            output[i] = output[i] - mu * error
        }

        return output
    }
}

// MARK: - Noise Blanker

@MainActor
public final class NoiseBlanker: ObservableObject {
    @Published public var enabled: Bool = false
    @Published public var threshold: Float = 0.7 // 0.0 to 1.0
    @Published public var blankingTime: Float = 0.001 // seconds

    private var blankedSamples: Int = 0

    public init() {}

    public func process(_ samples: [Float], sampleRate: Double) -> [Float] {
        guard enabled, !samples.isEmpty else { return samples }

        var output = samples
        let blankingSamples = Int(blankingTime * Float(sampleRate))

        // Calculate peak threshold
        var peak: Float = 0
        vDSP_maxv(samples, 1, &peak, vDSP_Length(samples.count))
        let actualThreshold = peak * threshold

        var i = 0
        while i < output.count {
            if abs(output[i]) > actualThreshold {
                // Blank this sample and surrounding samples
                let start = max(0, i - blankingSamples/2)
                let end = min(output.count, i + blankingSamples/2)

                for j in start..<end {
                    output[j] = 0
                }
                i = end
            } else {
                i += 1
            }
        }

        return output
    }
}

// MARK: - CTCSS/DCS Decoder

public struct CTCSSTone: Identifiable, Hashable {
    public let id = UUID()
    public let frequency: Float
    public let name: String

    public static let standardTones: [CTCSSTone] = [
        CTCSSTone(frequency: 67.0, name: "XZ"),
        CTCSSTone(frequency: 69.3, name: "WZ"),
        CTCSSTone(frequency: 71.9, name: "XA"),
        CTCSSTone(frequency: 74.4, name: "WA"),
        CTCSSTone(frequency: 77.0, name: "XB"),
        CTCSSTone(frequency: 79.7, name: "WB"),
        CTCSSTone(frequency: 82.5, name: "YZ"),
        CTCSSTone(frequency: 85.4, name: "YA"),
        CTCSSTone(frequency: 88.5, name: "YB"),
        CTCSSTone(frequency: 91.5, name: "ZZ"),
        CTCSSTone(frequency: 94.8, name: "ZA"),
        CTCSSTone(frequency: 97.4, name: "ZB"),
        CTCSSTone(frequency: 100.0, name: "1Z"),
        CTCSSTone(frequency: 103.5, name: "1A"),
        CTCSSTone(frequency: 107.2, name: "1B"),
        CTCSSTone(frequency: 110.9, name: "2Z"),
        CTCSSTone(frequency: 114.8, name: "2A"),
        CTCSSTone(frequency: 118.8, name: "2B"),
        CTCSSTone(frequency: 123.0, name: "3Z"),
        CTCSSTone(frequency: 127.3, name: "3A"),
        CTCSSTone(frequency: 131.8, name: "3B"),
        CTCSSTone(frequency: 136.5, name: "4Z"),
        CTCSSTone(frequency: 141.3, name: "4A"),
        CTCSSTone(frequency: 146.2, name: "4B"),
        CTCSSTone(frequency: 151.4, name: "5Z"),
        CTCSSTone(frequency: 156.7, name: "5A"),
        CTCSSTone(frequency: 162.2, name: "5B"),
        CTCSSTone(frequency: 167.9, name: "6Z"),
        CTCSSTone(frequency: 173.8, name: "6A"),
        CTCSSTone(frequency: 179.9, name: "6B"),
        CTCSSTone(frequency: 186.2, name: "7Z"),
        CTCSSTone(frequency: 192.8, name: "7A"),
        CTCSSTone(frequency: 203.5, name: "M1"),
        CTCSSTone(frequency: 210.7, name: "M2"),
        CTCSSTone(frequency: 218.1, name: "M3"),
        CTCSSTone(frequency: 225.7, name: "M4"),
        CTCSSTone(frequency: 233.6, name: "M5"),
        CTCSSTone(frequency: 241.8, name: "M6"),
        CTCSSTone(frequency: 250.3, name: "M7")
    ]
}

public struct DCSCode: Identifiable, Hashable {
    public let id = UUID()
    public let code: Int
    public let inverted: Bool

    public var displayName: String {
        inverted ? "D\(String(format: "%03d", code))I" : "D\(String(format: "%03d", code))N"
    }

    public static let standardCodes: [DCSCode] = [
        023, 025, 026, 031, 032, 036, 043, 047, 051, 053,
        054, 065, 071, 072, 073, 074, 114, 115, 116, 122,
        125, 131, 132, 134, 143, 145, 152, 155, 156, 162,
        165, 172, 174, 205, 212, 223, 225, 226, 243, 244,
        245, 246, 251, 252, 255, 261, 263, 265, 266, 271,
        274, 306, 311, 315, 325, 331, 332, 343, 346, 351,
        356, 364, 365, 371, 411, 412, 413, 423, 431, 432,
        445, 446, 452, 454, 455, 462, 464, 465, 466, 503,
        506, 516, 523, 526, 532, 546, 565, 606, 612, 624,
        627, 631, 632, 654, 662, 664, 703, 712, 723, 731,
        732, 734, 743, 754
    ].map { DCSCode(code: $0, inverted: false) }
}

@MainActor
public final class ToneDecoder: ObservableObject {
    @Published public var enabled: Bool = false
    @Published public private(set) var detectedCTCSS: CTCSSTone?
    @Published public private(set) var detectedDCS: DCSCode?
    @Published public private(set) var toneConfidence: Float = 0

    private var goertzelCoefficients: [Float: Float] = [:]
    private var detectionHistory: [Float: Int] = [:]
    private let requiredDetections = 3

    public init() {
        // Precompute Goertzel coefficients for CTCSS tones
        for tone in CTCSSTone.standardTones {
            let k = Int(0.5 + Float(256) * tone.frequency / 8000.0)
            let omega = 2.0 * Float.pi * Float(k) / 256.0
            goertzelCoefficients[tone.frequency] = 2.0 * cos(omega)
        }
    }

    public func analyze(_ samples: [Float], sampleRate: Double) {
        guard enabled, !samples.isEmpty else {
            detectedCTCSS = nil
            detectedDCS = nil
            toneConfidence = 0
            return
        }

        // Detect CTCSS using Goertzel algorithm
        var maxPower: Float = 0
        var detectedTone: CTCSSTone?

        for tone in CTCSSTone.standardTones {
            let power = goertzel(samples, targetFreq: tone.frequency, sampleRate: Float(sampleRate))

            if power > maxPower && power > 0.01 {
                maxPower = power
                detectedTone = tone
            }
        }

        if let tone = detectedTone {
            detectionHistory[tone.frequency, default: 0] += 1

            if detectionHistory[tone.frequency]! >= requiredDetections {
                detectedCTCSS = tone
                toneConfidence = min(1.0, Float(detectionHistory[tone.frequency]!) / 10.0)
            }
        } else {
            // Decay detection history
            for key in detectionHistory.keys {
                detectionHistory[key] = max(0, (detectionHistory[key] ?? 0) - 1)
            }

            if detectionHistory.values.allSatisfy({ $0 == 0 }) {
                detectedCTCSS = nil
                toneConfidence = 0
            }
        }
    }

    private func goertzel(_ samples: [Float], targetFreq: Float, sampleRate: Float) -> Float {
        let n = samples.count
        let k = Int(0.5 + Float(n) * targetFreq / sampleRate)
        let omega = 2.0 * Float.pi * Float(k) / Float(n)
        let coeff = 2.0 * cos(omega)

        var s0: Float = 0
        var s1: Float = 0
        var s2: Float = 0

        for sample in samples {
            s0 = sample + coeff * s1 - s2
            s2 = s1
            s1 = s0
        }

        let power = s1 * s1 + s2 * s2 - coeff * s1 * s2
        return power / Float(n * n)
    }
}

// MARK: - Audio Equalizer

@MainActor
public final class AudioEqualizer: ObservableObject {
    @Published public var enabled: Bool = false
    @Published public var bands: [EQBand]

    public struct EQBand: Identifiable {
        public let id = UUID()
        public let frequency: Float
        public let name: String
        public var gain: Float // -12 to +12 dB

        public init(frequency: Float, name: String, gain: Float = 0) {
            self.frequency = frequency
            self.name = name
            self.gain = gain
        }
    }

    // Biquad filter states
    private var filterStates: [[Float]] = []

    public init() {
        self.bands = [
            EQBand(frequency: 100, name: "100 Hz"),
            EQBand(frequency: 300, name: "300 Hz"),
            EQBand(frequency: 1000, name: "1 kHz"),
            EQBand(frequency: 3000, name: "3 kHz"),
            EQBand(frequency: 6000, name: "6 kHz")
        ]
        resetFilterStates()
    }

    private func resetFilterStates() {
        filterStates = bands.map { _ in [Float](repeating: 0, count: 4) }
    }

    public func process(_ samples: [Float], sampleRate: Double) -> [Float] {
        guard enabled, !samples.isEmpty else { return samples }

        var output = samples

        for (index, band) in bands.enumerated() {
            if abs(band.gain) > 0.1 {
                output = applyBiquad(output, band: band, sampleRate: Float(sampleRate), stateIndex: index)
            }
        }

        return output
    }

    private func applyBiquad(_ samples: [Float], band: EQBand, sampleRate: Float, stateIndex: Int) -> [Float] {
        var output = [Float](repeating: 0, count: samples.count)

        // Calculate biquad coefficients for peaking EQ
        let gain = pow(10, band.gain / 20.0)
        let omega = 2.0 * Float.pi * band.frequency / sampleRate
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)
        let q: Float = 1.0
        let alpha = sinOmega / (2.0 * q)

        let a0 = 1.0 + alpha / gain
        let a1 = -2.0 * cosOmega
        let a2 = 1.0 - alpha / gain
        let b0 = (1.0 + alpha * gain) / a0
        let b1 = (-2.0 * cosOmega) / a0
        let b2 = (1.0 - alpha * gain) / a0
        let na1 = a1 / a0
        let na2 = a2 / a0

        var z1 = filterStates[stateIndex][0]
        var z2 = filterStates[stateIndex][1]

        for i in 0..<samples.count {
            let input = samples[i]
            output[i] = b0 * input + z1
            z1 = b1 * input - na1 * output[i] + z2
            z2 = b2 * input - na2 * output[i]
        }

        filterStates[stateIndex][0] = z1
        filterStates[stateIndex][1] = z2

        return output
    }

    public func resetBands() {
        for i in 0..<bands.count {
            bands[i].gain = 0
        }
        resetFilterStates()
    }

    // Presets
    public func applyVoicePreset() {
        bands[0].gain = -6  // 100 Hz - reduce bass
        bands[1].gain = 0   // 300 Hz
        bands[2].gain = 3   // 1 kHz - boost mids
        bands[3].gain = 4   // 3 kHz - boost clarity
        bands[4].gain = 2   // 6 kHz
    }

    public func appleBassBoostPreset() {
        bands[0].gain = 6   // 100 Hz
        bands[1].gain = 4   // 300 Hz
        bands[2].gain = 0   // 1 kHz
        bands[3].gain = 0   // 3 kHz
        bands[4].gain = 0   // 6 kHz
    }

    public func applyTrebleBoostPreset() {
        bands[0].gain = 0   // 100 Hz
        bands[1].gain = 0   // 300 Hz
        bands[2].gain = 2   // 1 kHz
        bands[3].gain = 4   // 3 kHz
        bands[4].gain = 6   // 6 kHz
    }
}

// MARK: - Audio Processor Manager

@MainActor
public final class AudioProcessor: ObservableObject {
    public static let shared = AudioProcessor()

    @Published public var noiseReduction = NoiseReduction()
    @Published public var noiseBlanker = NoiseBlanker()
    @Published public var toneDecoder = ToneDecoder()
    @Published public var equalizer = AudioEqualizer()

    private init() {}

    public func process(_ samples: [Float], sampleRate: Double) -> [Float] {
        var output = samples

        // Apply processing chain
        output = noiseBlanker.process(output, sampleRate: sampleRate)
        output = noiseReduction.process(output, sampleRate: sampleRate)
        output = equalizer.process(output, sampleRate: sampleRate)

        // Analyze for tones (doesn't modify audio)
        toneDecoder.analyze(output, sampleRate: sampleRate)

        return output
    }
}

// MARK: - Audio Processing Views

@MainActor
public struct NoiseReductionView: View {
    @ObservedObject var nr: NoiseReduction

    public init(nr: NoiseReduction? = nil) {
        self.nr = nr ?? AudioProcessor.shared.noiseReduction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Noise Reduction", isOn: $nr.enabled)
                .toggleStyle(.switch)

            if nr.enabled {
                Picker("Algorithm", selection: $nr.algorithm) {
                    ForEach(NoiseReduction.NoiseReductionAlgorithm.allCases, id: \.self) { algo in
                        Text(algo.rawValue).tag(algo)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Strength")
                    Slider(value: $nr.strength, in: 0...1)
                    Text(String(format: "%.0f%%", nr.strength * 100))
                        .frame(width: 40)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}

@MainActor
public struct NoiseBlankerView: View {
    @ObservedObject var nb: NoiseBlanker

    public init(nb: NoiseBlanker? = nil) {
        self.nb = nb ?? AudioProcessor.shared.noiseBlanker
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Noise Blanker", isOn: $nb.enabled)
                .toggleStyle(.switch)

            if nb.enabled {
                HStack {
                    Text("Threshold")
                    Slider(value: $nb.threshold, in: 0.1...1)
                    Text(String(format: "%.0f%%", nb.threshold * 100))
                        .frame(width: 40)
                }

                HStack {
                    Text("Blanking Time")
                    Slider(value: $nb.blankingTime, in: 0.0001...0.01)
                    Text(String(format: "%.1fms", nb.blankingTime * 1000))
                        .frame(width: 50)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}

@MainActor
public struct ToneDecoderView: View {
    @ObservedObject var decoder: ToneDecoder

    public init(decoder: ToneDecoder? = nil) {
        self.decoder = decoder ?? AudioProcessor.shared.toneDecoder
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("CTCSS/DCS Decoder", isOn: $decoder.enabled)
                .toggleStyle(.switch)

            if decoder.enabled {
                HStack {
                    Text("Detected:")
                        .foregroundColor(.secondary)

                    if let tone = decoder.detectedCTCSS {
                        Text("\(String(format: "%.1f", tone.frequency)) Hz")
                            .foregroundColor(.green)
                            .fontWeight(.semibold)
                        Text("(\(tone.name))")
                            .foregroundColor(.secondary)
                    } else if let dcs = decoder.detectedDCS {
                        Text(dcs.displayName)
                            .foregroundColor(.green)
                            .fontWeight(.semibold)
                    } else {
                        Text("None")
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if decoder.toneConfidence > 0 {
                        ProgressView(value: decoder.toneConfidence)
                            .frame(width: 50)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}

@MainActor
public struct EqualizerView: View {
    @ObservedObject var eq: AudioEqualizer

    public init(eq: AudioEqualizer? = nil) {
        self.eq = eq ?? AudioProcessor.shared.equalizer
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Equalizer", isOn: $eq.enabled)
                    .toggleStyle(.switch)

                Spacer()

                if eq.enabled {
                    Menu {
                        Button("Voice") { eq.applyVoicePreset() }
                        Button("Bass Boost") { eq.appleBassBoostPreset() }
                        Button("Treble Boost") { eq.applyTrebleBoostPreset() }
                        Divider()
                        Button("Reset") { eq.resetBands() }
                    } label: {
                        Text("Presets")
                            .font(.caption)
                    }
                }
            }

            if eq.enabled {
                HStack(spacing: 16) {
                    ForEach(eq.bands.indices, id: \.self) { index in
                        VStack(spacing: 4) {
                            Text(String(format: "%+.0f", eq.bands[index].gain))
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Slider(value: Binding(
                                get: { eq.bands[index].gain },
                                set: { eq.bands[index].gain = $0 }
                            ), in: -12...12)
                            .rotationEffect(.degrees(-90))
                            .frame(width: 60, height: 20)

                            Text(eq.bands[index].name)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(height: 100)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}

public struct AudioProcessingPanel: View {
    @ObservedObject var processor = AudioProcessor.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            Text("Audio Processing")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            NoiseReductionView(nr: processor.noiseReduction)
            NoiseBlankerView(nb: processor.noiseBlanker)
            ToneDecoderView(decoder: processor.toneDecoder)
            EqualizerView(eq: processor.equalizer)
        }
        .padding()
    }
}
