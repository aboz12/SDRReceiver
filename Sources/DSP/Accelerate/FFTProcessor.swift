import Foundation
import Accelerate

/// High-performance FFT using Apple Accelerate vDSP
public final class FFTProcessor {
    private var fftSetup: FFTSetup?
    private let log2n: vDSP_Length
    private let fftSize: Int
    private var window: [Float]
    private var realBuffer: [Float]
    private var imagBuffer: [Float]
    private var magnitudes: [Float]
    private var averagedMagnitudes: [Float]
    private var averagingBuffer: [[Float]] = []
    private var averagingIndex: Int = 0

    public var averagingCount: Int = 4 {
        didSet {
            averagingBuffer = []
            averagingIndex = 0
        }
    }

    public var windowType: WindowType = .blackmanHarris {
        didSet {
            window = Self.createWindow(type: windowType, size: fftSize)
        }
    }

    public init(fftSize: Int = 4096, windowType: WindowType = .blackmanHarris) {
        self.fftSize = fftSize
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        self.window = Self.createWindow(type: windowType, size: fftSize)
        self.realBuffer = [Float](repeating: 0, count: fftSize)
        self.imagBuffer = [Float](repeating: 0, count: fftSize)
        self.magnitudes = [Float](repeating: 0, count: fftSize / 2)
        self.averagedMagnitudes = [Float](repeating: 0, count: fftSize / 2)
        self.windowType = windowType
    }

    deinit {
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }

    /// Compute spectrum magnitude from I/Q samples
    public func computeSpectrum(
        _ samples: [ComplexFloat],
        centerFrequency: Double = 0,
        sampleRate: Double = 0
    ) -> SpectrumData {
        guard samples.count >= fftSize, let setup = fftSetup else {
            return SpectrumData.empty
        }

        // Apply window function to I/Q samples
        for i in 0..<fftSize {
            realBuffer[i] = samples[i].real * window[i]
            imagBuffer[i] = samples[i].imag * window[i]
        }

        // Create split complex for FFT
        realBuffer.withUnsafeMutableBufferPointer { realPtr in
            imagBuffer.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(
                    realp: realPtr.baseAddress!,
                    imagp: imagPtr.baseAddress!
                )

                // Perform FFT
                vDSP_fft_zip(setup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))

                // Compute magnitudes squared
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        // Convert to dB
        var logMagnitudes = [Float](repeating: 0, count: fftSize / 2)
        var one: Float = 1e-10  // Prevent log(0)
        vDSP_vsadd(magnitudes, 1, &one, &magnitudes, 1, vDSP_Length(fftSize / 2))
        vDSP_vdbcon(magnitudes, 1, &one, &logMagnitudes, 1, vDSP_Length(fftSize / 2), 0)

        // Scale (FFT produces values that need normalization)
        var scale = Float(-10)  // Offset for display
        vDSP_vsadd(logMagnitudes, 1, &scale, &logMagnitudes, 1, vDSP_Length(fftSize / 2))

        // Apply averaging
        let result = applyAveraging(logMagnitudes)

        // FFT shift (move DC to center)
        let shifted = fftShift(result)

        return SpectrumData(
            magnitudes: shifted,
            fftSize: fftSize,
            centerFrequency: centerFrequency,
            sampleRate: sampleRate
        )
    }

    private func applyAveraging(_ magnitudes: [Float]) -> [Float] {
        guard averagingCount > 1 else { return magnitudes }

        // Initialize averaging buffer if needed
        if averagingBuffer.isEmpty {
            averagingBuffer = Array(repeating: magnitudes, count: averagingCount)
        }

        // Store current frame
        averagingBuffer[averagingIndex] = magnitudes
        averagingIndex = (averagingIndex + 1) % averagingCount

        // Compute average
        var result = [Float](repeating: 0, count: magnitudes.count)
        for frame in averagingBuffer {
            vDSP_vadd(result, 1, frame, 1, &result, 1, vDSP_Length(magnitudes.count))
        }
        var divisor = Float(averagingCount)
        vDSP_vsdiv(result, 1, &divisor, &result, 1, vDSP_Length(magnitudes.count))

        return result
    }

    private func fftShift(_ data: [Float]) -> [Float] {
        let half = data.count / 2
        return Array(data[half...]) + Array(data[..<half])
    }

    private static func createWindow(type: WindowType, size: Int) -> [Float] {
        var window = [Float](repeating: 0, count: size)
        switch type {
        case .blackmanHarris:
            // Blackman-Harris window
            for i in 0..<size {
                let n = Float(i)
                let N = Float(size)
                window[i] = 0.35875 -
                    0.48829 * cos(2 * .pi * n / N) +
                    0.14128 * cos(4 * .pi * n / N) -
                    0.01168 * cos(6 * .pi * n / N)
            }
        case .hamming:
            vDSP_hamm_window(&window, vDSP_Length(size), 0)
        case .hanning:
            vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        case .rectangular:
            for i in 0..<size {
                window[i] = 1.0
            }
        case .flattop:
            // Flat-top window (good for amplitude accuracy)
            for i in 0..<size {
                let n = Float(i)
                let N = Float(size)
                window[i] = 0.21557895 -
                    0.41663158 * cos(2 * .pi * n / N) +
                    0.277263158 * cos(4 * .pi * n / N) -
                    0.083578947 * cos(6 * .pi * n / N) +
                    0.006947368 * cos(8 * .pi * n / N)
            }
        }
        return window
    }
}

// MARK: - Window Types

public enum WindowType: String, CaseIterable, Sendable {
    case blackmanHarris = "Blackman-Harris"
    case hamming = "Hamming"
    case hanning = "Hanning"
    case rectangular = "Rectangular"
    case flattop = "Flat-top"
}
