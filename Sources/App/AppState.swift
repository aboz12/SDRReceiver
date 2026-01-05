import SwiftUI

/// Global application state
@MainActor
public final class AppState: ObservableObject {
    @Published var showFrequencyEntry = false
    @Published var showDeviceSelector = false
    @Published var showDecoderPanel = true
    @Published var selectedDecoder: String?
    @Published var recentFrequencies: [Double] = []

    // UI Layout
    @Published var spectrumHeight: CGFloat = 200
    @Published var waterfallHeight: CGFloat = 300
    @Published var showSpectrum = true
    @Published var showWaterfall = true

    // Display settings
    @Published var spectrumReferenceLevel: Float = 0  // dB
    @Published var spectrumRange: Float = 100  // dB
    @Published var waterfallSpeed: Double = 1.0

    func addRecentFrequency(_ frequency: Double) {
        if !recentFrequencies.contains(frequency) {
            recentFrequencies.insert(frequency, at: 0)
            if recentFrequencies.count > 20 {
                recentFrequencies.removeLast()
            }
        }
    }
}
