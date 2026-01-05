import Foundation
import SwiftUI
import AppKit

// MARK: - NOAA APT Plugin

public final class NOAAAPTPlugin: ImageDecoderPlugin, ObservableObject {
    public static let identifier = "com.sdr.decoder.noaa.apt"
    public static let name = "NOAA APT"
    public static let version = "1.0.0"
    public static let author = "SDR Team"
    public static let description = "NOAA Automatic Picture Transmission"
    public static let category = DecoderCategory.weather

    public let id = UUID()
    public let requiredSampleRate: Double = 20800
    public let requiredBandwidth: Double = 34000
    public let centerFrequencyOffset: Double = 0

    // NOAA APT: FM at 137 MHz, 2400 Hz subcarrier, 4160 samples/line
    // NOAA 15: 137.620 MHz
    // NOAA 18: 137.9125 MHz
    // NOAA 19: 137.100 MHz

    @Published public var currentImage: DecodedImage?
    @Published public var lineCount: Int = 0

    private var imageBuffer: [[UInt8]] = []
    private var audioBuffer: [Float] = []
    private let samplesPerLine = 4160
    private let linesPerImage = 2080  // ~8 minutes of data

    // Sync patterns
    private let syncA: [Int] = [0, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0,
                                1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0,
                                1, 1, 0, 0, 1, 1, 0, 0]  // Channel A sync
    private let syncB: [Int] = [0, 0, 0, 0, 1, 1, 1, 0, 0, 1, 1, 1, 0, 0, 1, 1,
                                1, 0, 0, 1, 1, 1, 0, 0, 1, 1, 1, 0, 0, 1, 1, 1,
                                0, 0, 1, 1, 1, 0, 0, 0]  // Channel B sync

    public init() {}

    public func initialize() throws {
        imageBuffer.removeAll()
        audioBuffer.removeAll()
        currentImage = nil
        lineCount = 0
    }

    public func shutdown() {}

    public func process(samples: [Float], sampleRate: Double) async -> [DecodedMessage] {
        var messages: [DecodedMessage] = []

        // APT decoding:
        // 1. AM demodulation of 2400 Hz subcarrier
        // 2. Sync word detection
        // 3. Line extraction (2080 pixels per line)
        // 4. Image reconstruction

        audioBuffer.append(contentsOf: samples)

        // Need enough samples for one line
        let samplesNeeded = Int(sampleRate / 2.0)  // 2 lines per second

        while audioBuffer.count >= samplesNeeded {
            let lineData = Array(audioBuffer.prefix(samplesNeeded))
            audioBuffer.removeFirst(samplesNeeded)

            // Demodulate AM subcarrier
            if let line = demodulateAPTLine(lineData, sampleRate: sampleRate) {
                imageBuffer.append(line)
                lineCount = imageBuffer.count

                // Update image periodically
                if imageBuffer.count % 50 == 0 || imageBuffer.count >= linesPerImage {
                    await updateImage()
                }

                // Create message on first line or when image complete
                if imageBuffer.count == 1 || imageBuffer.count == linesPerImage {
                    let message = DecodedMessage(
                        plugin: Self.identifier,
                        timestamp: Date(),
                        frequency: 137_500_000,
                        snr: nil,
                        content: imageBuffer.count == linesPerImage ?
                            "NOAA APT image complete (\(linesPerImage) lines)" :
                            "NOAA APT signal detected, receiving...",
                        metadata: ["lines": "\(imageBuffer.count)"]
                    )
                    messages.append(message)
                }

                // Reset buffer if full
                if imageBuffer.count >= linesPerImage {
                    imageBuffer.removeAll()
                }
            }
        }

        return messages
    }

    private func demodulateAPTLine(_ samples: [Float], sampleRate: Double) -> [UInt8]? {
        // AM envelope detection at 2400 Hz subcarrier
        var pixels: [UInt8] = []

        let pixelsPerLine = 2080
        let samplesPerPixel = samples.count / pixelsPerLine

        for i in 0..<pixelsPerLine {
            let start = i * samplesPerPixel
            let end = min(start + samplesPerPixel, samples.count)

            // Simple envelope detection
            var maxVal: Float = 0
            for j in start..<end {
                maxVal = max(maxVal, abs(samples[j]))
            }

            // Normalize to 0-255
            let pixel = UInt8(min(255, max(0, maxVal * 255)))
            pixels.append(pixel)
        }

        return pixels.count == pixelsPerLine ? pixels : nil
    }

    @MainActor
    private func updateImage() {
        guard !imageBuffer.isEmpty else { return }

        let width = imageBuffer[0].count
        let height = imageBuffer.count

        var pixels: [UInt8] = []
        for line in imageBuffer {
            pixels.append(contentsOf: line)
        }

        currentImage = DecodedImage(
            timestamp: Date(),
            width: width,
            height: height,
            pixels: pixels,
            isComplete: imageBuffer.count >= linesPerImage
        )
    }

    public func decodeImage(samples: [Float]) -> DecodedImage? {
        return currentImage
    }

    @MainActor
    public var settingsView: AnyView? {
        AnyView(NOAAAPTSettingsView(plugin: self))
    }
}

struct NOAAAPTSettingsView: View {
    @ObservedObject var plugin: NOAAAPTPlugin

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NOAA APT Image Decoder")
                .font(.headline)

            Text("Lines received: \(plugin.lineCount)")

            if let image = plugin.currentImage {
                Text("Image: \(image.width) × \(image.height)")

                // Display image preview
                if let nsImage = createNSImage(from: image) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 400)
                }

                if image.isComplete {
                    Text("Image complete!")
                        .foregroundColor(.green)
                }
            } else {
                Text("Waiting for signal...")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    private func createNSImage(from decodedImage: DecodedImage) -> NSImage? {
        let width = decodedImage.width
        let height = decodedImage.height
        let pixels = decodedImage.pixels

        guard pixels.count == width * height else { return nil }

        // Create grayscale bitmap
        var rgbPixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<pixels.count {
            let gray = pixels[i]
            rgbPixels[i * 4 + 0] = gray  // R
            rgbPixels[i * 4 + 1] = gray  // G
            rgbPixels[i * 4 + 2] = gray  // B
            rgbPixels[i * 4 + 3] = 255   // A
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &rgbPixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        guard let cgImage = context.makeImage() else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
}

// MARK: - Meteor LRPT Plugin

public final class MeteorLRPTPlugin: ImageDecoderPlugin, ObservableObject {
    public static let identifier = "com.sdr.decoder.meteor.lrpt"
    public static let name = "Meteor LRPT"
    public static let version = "1.0.0"
    public static let author = "SDR Team"
    public static let description = "Meteor-M LRPT (Low Rate Picture Transmission)"
    public static let category = DecoderCategory.weather

    public let id = UUID()
    public let requiredSampleRate: Double = 140000
    public let requiredBandwidth: Double = 120000
    public let centerFrequencyOffset: Double = 0

    // Meteor LRPT: QPSK at 72 kbps, 137.1 or 137.9 MHz
    // Much higher resolution than NOAA APT

    @Published public var currentImage: DecodedImage?
    @Published public var packetsReceived: Int = 0

    private var imageChannels: [[UInt8]] = [[], [], []]  // RGB or 3 IR channels

    public init() {}

    public func initialize() throws {
        currentImage = nil
        packetsReceived = 0
        imageChannels = [[], [], []]
    }

    public func shutdown() {}

    public func process(samples: [Float], sampleRate: Double) async -> [DecodedMessage] {
        var messages: [DecodedMessage] = []

        // Meteor LRPT decoding:
        // 1. QPSK demodulation at 72 ksymbols/sec
        // 2. Find sync word
        // 3. Reed-Solomon error correction
        // 4. CADU (Channel Access Data Unit) extraction
        // 5. VCDU (Virtual Channel Data Unit) demuxing
        // 6. M-CADU packet processing
        // 7. Image line reconstruction

        // TODO: Implement full Meteor LRPT decoder

        return messages
    }

    public func decodeImage(samples: [Float]) -> DecodedImage? {
        return currentImage
    }

    @MainActor
    public var settingsView: AnyView? {
        AnyView(MeteorLRPTSettingsView(plugin: self))
    }
}

struct MeteorLRPTSettingsView: View {
    @ObservedObject var plugin: MeteorLRPTPlugin

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Meteor-M LRPT Decoder")
                .font(.headline)

            Text("Packets received: \(plugin.packetsReceived)")

            if let image = plugin.currentImage {
                Text("Image: \(image.width) × \(image.height)")

                if image.isComplete {
                    Text("Image complete!")
                        .foregroundColor(.green)
                }
            } else {
                Text("Waiting for signal...")
                    .foregroundColor(.secondary)
            }

            Text("Note: Meteor LRPT requires 120 kHz bandwidth")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
