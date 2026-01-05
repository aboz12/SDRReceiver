import Foundation
import AVFoundation
import Accelerate

/// Audio output engine using AVAudioEngine
@MainActor
public final class AudioEngine: ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?

    @Published public private(set) var isRunning = false
    @Published public var volume: Float = 1.0 {
        didSet { applyVolume() }
    }
    @Published public var isMuted: Bool = false {
        didSet { applyVolume() }
    }

    private let sampleRate: Double = 48000
    private let bufferSize: Int = 1024
    private var pendingSamples: [Float] = []

    public init() {
        setupAudioEngine()
    }

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        guard let engine = audioEngine,
              let player = playerNode else { return }

        audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )

        engine.attach(player)

        if let format = audioFormat {
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
    }

    public func start() throws {
        guard let engine = audioEngine,
              let player = playerNode else { return }

        try engine.start()
        player.play()
        isRunning = true

        // Apply current volume settings
        applyVolume()

        // Start buffer scheduling
        scheduleBuffers()
    }

    public func stop() {
        playerNode?.stop()
        audioEngine?.stop()
        isRunning = false
    }

    public func setVolume(_ newVolume: Float) {
        volume = max(0, min(1, newVolume))
    }

    public func toggleMute() {
        isMuted.toggle()
    }

    private func applyVolume() {
        let effectiveVolume = isMuted ? 0 : volume
        audioEngine?.mainMixerNode.outputVolume = effectiveVolume
    }

    /// Write audio samples to the output
    public func write(_ samples: [Float]) async {
        await MainActor.run {
            pendingSamples.append(contentsOf: samples)
        }
    }

    private func scheduleBuffers() {
        guard isRunning,
              let player = playerNode,
              let format = audioFormat else { return }

        // Schedule next buffer
        Task { @MainActor in
            while isRunning {
                // Get samples from pending buffer
                let samplesToPlay: [Float]
                if pendingSamples.count >= bufferSize {
                    samplesToPlay = Array(pendingSamples.prefix(bufferSize))
                    pendingSamples.removeFirst(bufferSize)
                } else {
                    samplesToPlay = []
                }

                if !samplesToPlay.isEmpty {
                    // Create audio buffer
                    if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samplesToPlay.count)) {
                        buffer.frameLength = AVAudioFrameCount(samplesToPlay.count)

                        if let channelData = buffer.floatChannelData?[0] {
                            for i in 0..<samplesToPlay.count {
                                channelData[i] = samplesToPlay[i] * volume
                            }
                        }

                        player.scheduleBuffer(buffer, completionHandler: nil)
                    }
                }

                // Wait a bit before scheduling next buffer
                try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
            }
        }
    }
}
