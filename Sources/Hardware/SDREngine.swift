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
        dev.sampleRate = 2_400_000
        dev.bandwidth = 2_400_000

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
}
