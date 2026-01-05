import Foundation
import SwiftUI

/// Main SDR engine that coordinates hardware, DSP, and audio
@MainActor
public final class SDREngine: ObservableObject {
    public static let shared = SDREngine()

    // Published state
    @Published public private(set) var isRunning = false
    @Published public private(set) var isRecording = false
    @Published public private(set) var currentDevice: SDRDeviceInfo?
    @Published public private(set) var availableDevices: [String] = []
    @Published public private(set) var lastError: String?

    // Frequency
    @Published public var frequency: Double = 100_000_000 {
        didSet { applyFrequency() }
    }

    // Gain
    @Published public var gain: Double = 30 {
        didSet { applyGain() }
    }

    @Published public var gainMode: GainMode = .manual {
        didSet { applyGainMode() }
    }

    // Sample Rate (determines visible bandwidth on waterfall)
    @Published public var sampleRate: Double = 2_400_000 {
        didSet { applySampleRate() }
    }

    // Available sample rates
    public let availableSampleRates: [Double] = [
        240_000,    // 240 kHz - Narrow
        480_000,    // 480 kHz
        960_000,    // 960 kHz
        1_024_000,  // 1.024 MHz
        1_440_000,  // 1.44 MHz
        1_920_000,  // 1.92 MHz
        2_048_000,  // 2.048 MHz
        2_400_000,  // 2.4 MHz - Default
        2_880_000,  // 2.88 MHz
        3_200_000   // 3.2 MHz - Wide
    ]

    // Components
    @Published public var dspEngine: DSPEngine
    public let audioEngine: AudioEngine

    private var device: SoapySDRDeviceWrapper?
    private var processingTask: Task<Void, Never>?

    private init() {
        self.audioEngine = AudioEngine()
        self.dspEngine = DSPEngine(audioEngine: audioEngine)
        refreshDevices()
    }

    /// Refresh available devices list
    public func refreshDevices() {
        let devices = SoapySDRDeviceWrapper.enumerateDevices()
        availableDevices = devices.map { $0.name }
    }

    /// Start receiving
    public func start(deviceArgs: [String: String] = [:]) async throws {
        guard !isRunning else { return }

        // Create device
        guard let dev = SoapySDRDeviceWrapper(args: deviceArgs) else {
            throw SDRDeviceError.deviceNotFound
        }

        device = dev
        currentDevice = SDRDeviceInfo(
            id: dev.id,
            name: dev.name,
            driver: dev.driver
        )

        // Apply settings
        dev.centerFrequency = frequency
        dev.gain = gain
        dev.gainMode = gainMode
        dev.sampleRate = sampleRate
        dev.bandwidth = sampleRate

        // Start streaming
        try dev.startStreaming()

        // Start audio
        try audioEngine.start()

        // Start DSP processing
        dspEngine.startProcessing(from: dev.sampleStream)

        isRunning = true
        lastError = nil
    }

    /// Stop receiving
    public func stop() {
        isRunning = false

        dspEngine.stopProcessing()
        audioEngine.stop()
        device?.stopStreaming()
        device?.close()
        device = nil
        currentDevice = nil
    }

    /// Tune to a frequency
    public func tuneTo(_ newFrequency: Double) {
        frequency = newFrequency
    }

    /// Tune by an offset
    public func tuneBy(_ offset: Double) {
        frequency += offset
    }

    /// Toggle I/Q recording
    public func toggleRecording() {
        isRecording.toggle()
        // TODO: Implement I/Q recording
    }

    private func applyFrequency() {
        device?.centerFrequency = frequency
    }

    private func applyGain() {
        device?.gain = gain
    }

    private func applyGainMode() {
        device?.gainMode = gainMode
    }

    private func applySampleRate() {
        device?.sampleRate = sampleRate
        device?.bandwidth = sampleRate
    }

    /// Get the visible frequency span (same as sample rate)
    public var visibleBandwidth: Double {
        sampleRate
    }

    /// Get frequency range visible on waterfall
    public var visibleFrequencyRange: ClosedRange<Double> {
        let halfSpan = sampleRate / 2
        return (frequency - halfSpan)...(frequency + halfSpan)
    }
}
