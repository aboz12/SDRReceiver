import Foundation
import Accelerate

/// Main DSP orchestration engine
@MainActor
public final class DSPEngine: ObservableObject {
    // Published state
    @Published public private(set) var isRunning = false
    @Published public private(set) var spectrumData: SpectrumData?
    @Published public private(set) var waterfallLine: WaterfallLine?
    @Published public private(set) var audioLevel: Float = 0.0
    @Published public private(set) var signalStrength: Float = -120.0  // dBm

    // Configuration
    @Published public var demodulationMode: DemodulationMode = .fm {
        didSet { updateDemodulator() }
    }
    @Published public var filterBandwidth: Double = 12500  // Hz
    @Published public var squelchLevel: Float = -100.0  // dBm
    @Published public var squelchEnabled: Bool = true
    @Published public var agcEnabled: Bool = true
    @Published public var agcSpeed: AGCSpeed = .medium

    // Components
    private let fftProcessor: FFTProcessor
    private var demodulator: (any Demodulator)?
    private let audioResampler: Resampler
    private weak var audioEngine: AudioEngine?

    // Processing state
    private var processingTask: Task<Void, Never>?
    private var inputSampleRate: Double = 2_400_000
    private var outputSampleRate: Double = 48000

    // AGC state
    private var agcGain: Float = 1.0
    private let agcTargetLevel: Float = 0.5

    public init(audioEngine: AudioEngine? = nil) {
        self.fftProcessor = FFTProcessor(fftSize: 4096)
        self.audioResampler = Resampler(inputRate: 48000, outputRate: 48000)
        self.audioEngine = audioEngine
        updateDemodulator()
    }

    private func updateDemodulator() {
        switch demodulationMode {
        case .am:
            demodulator = AMDemodulator()
        case .fm:
            demodulator = FMDemodulator(bandwidth: filterBandwidth, deemphasis: 75e-6)
        case .wfm:
            demodulator = FMDemodulator(bandwidth: 200000, deemphasis: 75e-6)
        case .lsb:
            demodulator = SSBDemodulator(sideband: .lower)
        case .usb:
            demodulator = SSBDemodulator(sideband: .upper)
        case .cw:
            demodulator = CWDemodulator(toneFrequency: 700)
        case .raw:
            demodulator = nil
        }
    }

    /// Process incoming I/Q samples
    public func process(_ buffer: IQSampleBuffer) async {
        guard !buffer.isEmpty else { return }

        inputSampleRate = buffer.sampleRate

        // 1. Compute FFT for spectrum/waterfall
        let spectrum = fftProcessor.computeSpectrum(
            buffer.samples,
            centerFrequency: buffer.centerFrequency,
            sampleRate: buffer.sampleRate
        )
        self.spectrumData = spectrum
        self.waterfallLine = WaterfallLine(from: spectrum)

        // 1b. Run signal detection
        SignalDetector.shared.analyzeSpectrum(spectrum, centerFrequency: buffer.centerFrequency, sampleRate: buffer.sampleRate)

        // 2. Calculate signal strength
        signalStrength = calculateSignalStrength(spectrum)

        // 3. Check squelch
        let squelchOpen = !squelchEnabled || signalStrength > squelchLevel

        // 4. Demodulate if squelch is open
        if squelchOpen, let demod = demodulator {
            var audioSamples = demod.demodulate(buffer.samples, sampleRate: buffer.sampleRate)

            // Apply AGC
            if agcEnabled {
                audioSamples = applyAGC(audioSamples)
            }

            // Calculate audio level for meter
            audioLevel = calculateAudioLevel(audioSamples)

            // Output to audio engine
            await audioEngine?.write(audioSamples)
        } else {
            audioLevel = 0
        }
    }

    private func calculateSignalStrength(_ spectrum: SpectrumData) -> Float {
        guard !spectrum.isEmpty else { return -120 }

        // Use center bins for signal strength
        let centerStart = spectrum.magnitudes.count / 2 - 10
        let centerEnd = spectrum.magnitudes.count / 2 + 10
        let centerBins = Array(spectrum.magnitudes[centerStart..<centerEnd])

        // Peak value
        let peak = centerBins.max() ?? -120
        return peak
    }

    private func calculateAudioLevel(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }

        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return rms
    }

    private func applyAGC(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }

        var output = samples

        // Calculate current level
        var peak: Float = 0
        vDSP_maxv(samples, 1, &peak, vDSP_Length(samples.count))

        // Adjust gain based on AGC speed
        let attackRate: Float
        let releaseRate: Float

        switch agcSpeed {
        case .fast:
            attackRate = 0.1
            releaseRate = 0.001
        case .medium:
            attackRate = 0.01
            releaseRate = 0.0001
        case .slow:
            attackRate = 0.001
            releaseRate = 0.00001
        }

        let targetGain = peak > 0 ? agcTargetLevel / peak : agcGain
        let rate = targetGain < agcGain ? attackRate : releaseRate
        agcGain += (targetGain - agcGain) * rate
        agcGain = max(0.001, min(100, agcGain))

        // Apply gain
        vDSP_vsmul(samples, 1, &agcGain, &output, 1, vDSP_Length(samples.count))

        return output
    }

    /// Start processing with sample stream
    public func startProcessing(from stream: AsyncStream<IQSampleBuffer>) {
        isRunning = true
        processingTask = Task { [weak self] in
            for await buffer in stream {
                guard !Task.isCancelled else { break }
                await self?.process(buffer)
            }
        }
    }

    public func stopProcessing() {
        isRunning = false
        processingTask?.cancel()
        processingTask = nil
    }
}

// MARK: - AGC Speed

public enum AGCSpeed: String, CaseIterable, Sendable {
    case fast = "Fast"
    case medium = "Medium"
    case slow = "Slow"
}

// MARK: - Resampler

/// Simple resampler for audio rate conversion
public final class Resampler {
    private var inputRate: Double
    private var outputRate: Double
    private var ratio: Double

    public init(inputRate: Double, outputRate: Double) {
        self.inputRate = inputRate
        self.outputRate = outputRate
        self.ratio = outputRate / inputRate
    }

    public func resample(_ samples: [Float]) -> [Float] {
        guard ratio != 1.0 else { return samples }

        let outputCount = Int(Double(samples.count) * ratio)
        var output = [Float](repeating: 0, count: outputCount)

        // Linear interpolation resampling
        for i in 0..<outputCount {
            let srcIndex = Double(i) / ratio
            let srcIndexInt = Int(srcIndex)
            let frac = Float(srcIndex - Double(srcIndexInt))

            if srcIndexInt + 1 < samples.count {
                output[i] = samples[srcIndexInt] * (1 - frac) + samples[srcIndexInt + 1] * frac
            } else if srcIndexInt < samples.count {
                output[i] = samples[srcIndexInt]
            }
        }

        return output
    }

    public func setRates(input: Double, output: Double) {
        self.inputRate = input
        self.outputRate = output
        self.ratio = output / input
    }
}
