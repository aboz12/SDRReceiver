import SwiftUI
import AppKit

// MARK: - Peak Hold

@MainActor
public final class PeakHoldManager: ObservableObject {
    public static let shared = PeakHoldManager()

    @Published public var enabled: Bool = false
    @Published public var decayRate: Float = 0.995 // per frame
    @Published public var holdTime: TimeInterval = 2.0 // seconds before decay starts
    @Published public private(set) var peakValues: [Float] = []

    private var peakTimestamps: [Date] = []

    private init() {}

    public func update(with spectrum: [Float]) {
        let now = Date()

        // Initialize if needed
        if peakValues.count != spectrum.count {
            peakValues = spectrum
            peakTimestamps = [Date](repeating: now, count: spectrum.count)
            return
        }

        guard enabled else {
            peakValues = spectrum
            return
        }

        for i in 0..<spectrum.count {
            if spectrum[i] > peakValues[i] {
                // New peak
                peakValues[i] = spectrum[i]
                peakTimestamps[i] = now
            } else {
                // Check if hold time has elapsed
                let elapsed = now.timeIntervalSince(peakTimestamps[i])
                if elapsed > holdTime {
                    // Apply decay
                    peakValues[i] *= decayRate
                    // Don't let peak go below current value
                    if peakValues[i] < spectrum[i] {
                        peakValues[i] = spectrum[i]
                        peakTimestamps[i] = now
                    }
                }
            }
        }
    }

    public func reset() {
        peakValues = []
        peakTimestamps = []
    }
}

// MARK: - Waterfall Zoom

@MainActor
public final class WaterfallZoomManager: ObservableObject {
    public static let shared = WaterfallZoomManager()

    @Published public var zoomLevel: Double = 1.0 // 1.0 = full span
    @Published public var panOffset: Double = 0.0 // -0.5 to 0.5 of span

    public var minZoom: Double = 1.0
    public var maxZoom: Double = 16.0

    private init() {}

    public func zoomIn(at position: Double = 0.5) {
        let newZoom = min(zoomLevel * 1.5, maxZoom)
        adjustPanForZoom(from: zoomLevel, to: newZoom, at: position)
        zoomLevel = newZoom
    }

    public func zoomOut(at position: Double = 0.5) {
        let newZoom = max(zoomLevel / 1.5, minZoom)
        adjustPanForZoom(from: zoomLevel, to: newZoom, at: position)
        zoomLevel = newZoom
    }

    public func setZoom(_ level: Double, at position: Double = 0.5) {
        let newZoom = max(minZoom, min(maxZoom, level))
        adjustPanForZoom(from: zoomLevel, to: newZoom, at: position)
        zoomLevel = newZoom
    }

    private func adjustPanForZoom(from oldZoom: Double, to newZoom: Double, at position: Double) {
        // Keep the point under the cursor stationary
        let normalizedPos = (position - 0.5) * 2 // -1 to 1
        let oldSpan = 1.0 / oldZoom
        let newSpan = 1.0 / newZoom

        let spanDiff = oldSpan - newSpan
        panOffset += normalizedPos * spanDiff / 2

        // Clamp pan to valid range
        let maxPan = (1.0 - 1.0/zoomLevel) / 2
        panOffset = max(-maxPan, min(maxPan, panOffset))
    }

    public func pan(by delta: Double) {
        let maxPan = (1.0 - 1.0/zoomLevel) / 2
        panOffset = max(-maxPan, min(maxPan, panOffset + delta))
    }

    public func reset() {
        zoomLevel = 1.0
        panOffset = 0.0
    }

    /// Get visible frequency range given center frequency and sample rate
    public func visibleRange(centerFrequency: Double, sampleRate: Double) -> ClosedRange<Double> {
        let visibleSpan = sampleRate / zoomLevel
        let centerOffset = panOffset * sampleRate
        let visibleCenter = centerFrequency + centerOffset

        return (visibleCenter - visibleSpan/2)...(visibleCenter + visibleSpan/2)
    }

    /// Map a bin index to visible position (0-1)
    public func mapToVisible(binIndex: Int, totalBins: Int) -> Double? {
        let normalizedBin = Double(binIndex) / Double(totalBins) - 0.5 // -0.5 to 0.5
        let adjustedBin = (normalizedBin - panOffset) * zoomLevel + 0.5

        if adjustedBin >= 0 && adjustedBin <= 1 {
            return adjustedBin
        }
        return nil
    }
}

// MARK: - Waterfall Markers

public struct WaterfallMarker: Identifiable, Codable {
    public let id: UUID
    public var frequency: Double
    public var label: String
    public var color: MarkerColor
    public var isVisible: Bool

    public enum MarkerColor: String, Codable, CaseIterable {
        case red, orange, yellow, green, cyan, blue, purple, white

        public var swiftUIColor: Color {
            switch self {
            case .red: return .red
            case .orange: return .orange
            case .yellow: return .yellow
            case .green: return .green
            case .cyan: return .cyan
            case .blue: return .blue
            case .purple: return .purple
            case .white: return .white
            }
        }
    }

    public init(frequency: Double, label: String, color: MarkerColor = .yellow, isVisible: Bool = true) {
        self.id = UUID()
        self.frequency = frequency
        self.label = label
        self.color = color
        self.isVisible = isVisible
    }
}

@MainActor
public final class MarkerManager: ObservableObject {
    public static let shared = MarkerManager()

    @Published public var markers: [WaterfallMarker] = []
    @Published public var showMarkers: Bool = true

    private let saveKey = "WaterfallMarkers"

    private init() {
        loadMarkers()
    }

    public func addMarker(_ marker: WaterfallMarker) {
        markers.append(marker)
        saveMarkers()
    }

    public func addMarker(at frequency: Double, label: String = "") {
        let marker = WaterfallMarker(
            frequency: frequency,
            label: label.isEmpty ? FrequencyFormatter.format(frequency) : label
        )
        addMarker(marker)
    }

    public func removeMarker(_ marker: WaterfallMarker) {
        markers.removeAll { $0.id == marker.id }
        saveMarkers()
    }

    public func removeMarker(at index: Int) {
        guard index >= 0 && index < markers.count else { return }
        markers.remove(at: index)
        saveMarkers()
    }

    public func updateMarker(_ marker: WaterfallMarker) {
        if let index = markers.firstIndex(where: { $0.id == marker.id }) {
            markers[index] = marker
            saveMarkers()
        }
    }

    public func clearMarkers() {
        markers.removeAll()
        saveMarkers()
    }

    private func saveMarkers() {
        if let encoded = try? JSONEncoder().encode(markers) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }

    private func loadMarkers() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let decoded = try? JSONDecoder().decode([WaterfallMarker].self, from: data) else {
            return
        }
        markers = decoded
    }
}

// MARK: - Signal Labels

public struct SignalLabel: Identifiable {
    public let id = UUID()
    public let frequency: Double
    public let bandwidth: Double
    public let strength: Float
    public let label: String
    public let confidence: Float
}

@MainActor
public final class SignalLabelManager: ObservableObject {
    public static let shared = SignalLabelManager()

    @Published public var showLabels: Bool = true
    @Published public var minSignalStrength: Float = -80 // dBm
    @Published public private(set) var labels: [SignalLabel] = []

    private init() {}

    public func updateLabels(from detectedSignals: [SignalDetector.DetectedSignal], bandPlan: BandPlanManager) {
        guard showLabels else {
            labels = []
            return
        }

        labels = detectedSignals.compactMap { signal -> SignalLabel? in
            guard signal.strength > minSignalStrength else { return nil }

            // Look up band plan for label
            let matchingBand = bandPlan.bands.first { band in
                signal.frequency >= band.startFreq && signal.frequency <= band.endFreq
            }
            let bandLabel = matchingBand?.name ?? "Signal"

            return SignalLabel(
                frequency: signal.frequency,
                bandwidth: signal.bandwidth,
                strength: signal.strength,
                label: bandLabel,
                confidence: 1.0  // Default confidence
            )
        }
    }
}

// MARK: - Screenshot & Video Export

@MainActor
public final class ExportManager: ObservableObject {
    public static let shared = ExportManager()

    @Published public var isRecordingVideo: Bool = false
    @Published public private(set) var recordingDuration: TimeInterval = 0

    private var videoWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var recordingStartTime: Date?
    private var frameCount: Int64 = 0

    private init() {}

    public func captureScreenshot(of view: NSView, filename: String? = nil) -> URL? {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return nil
        }

        view.cacheDisplay(in: view.bounds, to: bitmap)

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())

        let name = filename ?? "SDRReceiver_\(timestamp).png"
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let fileURL = desktopURL.appendingPathComponent(name)

        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("Failed to save screenshot: \(error)")
            return nil
        }
    }

    public func captureSpectrumData(_ spectrum: [Float], filename: String? = nil) -> URL? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())

        let name = filename ?? "spectrum_\(timestamp).csv"
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let fileURL = desktopURL.appendingPathComponent(name)

        var csv = "bin,magnitude_db\n"
        for (index, value) in spectrum.enumerated() {
            csv += "\(index),\(value)\n"
        }

        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("Failed to save spectrum data: \(error)")
            return nil
        }
    }
}

// MARK: - Enhanced Spectrum View

public struct EnhancedSpectrumOverlay: View {
    @ObservedObject var peakHold = PeakHoldManager.shared
    @ObservedObject var zoomManager = WaterfallZoomManager.shared
    @ObservedObject var markerManager = MarkerManager.shared
    @ObservedObject var labelManager = SignalLabelManager.shared

    let centerFrequency: Double
    let sampleRate: Double
    let spectrumData: [Float]

    public init(centerFrequency: Double, sampleRate: Double, spectrumData: [Float]) {
        self.centerFrequency = centerFrequency
        self.sampleRate = sampleRate
        self.spectrumData = spectrumData
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // Peak hold line
                if peakHold.enabled && !peakHold.peakValues.isEmpty {
                    PeakHoldPath(values: peakHold.peakValues, zoomLevel: zoomManager.zoomLevel, panOffset: zoomManager.panOffset)
                        .stroke(Color.yellow.opacity(0.7), lineWidth: 1)
                }

                // Markers
                if markerManager.showMarkers {
                    ForEach(markerManager.markers) { marker in
                        if let position = frequencyToPosition(marker.frequency, width: geo.size.width) {
                            MarkerView(marker: marker, position: position, height: geo.size.height)
                        }
                    }
                }

                // Signal labels
                if labelManager.showLabels {
                    ForEach(labelManager.labels) { label in
                        if let position = frequencyToPosition(label.frequency, width: geo.size.width) {
                            SignalLabelView(label: label, position: position)
                        }
                    }
                }
            }
        }
    }

    private func frequencyToPosition(_ frequency: Double, width: CGFloat) -> CGFloat? {
        let visibleRange = zoomManager.visibleRange(centerFrequency: centerFrequency, sampleRate: sampleRate)

        guard frequency >= visibleRange.lowerBound && frequency <= visibleRange.upperBound else {
            return nil
        }

        let normalizedPos = (frequency - visibleRange.lowerBound) / (visibleRange.upperBound - visibleRange.lowerBound)
        return CGFloat(normalizedPos) * width
    }
}

struct PeakHoldPath: Shape {
    let values: [Float]
    let zoomLevel: Double
    let panOffset: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !values.isEmpty else { return path }

        let visibleBins = values.indices.compactMap { index -> (x: CGFloat, y: CGFloat)? in
            let normalizedBin = Double(index) / Double(values.count) - 0.5
            let adjustedBin = (normalizedBin - panOffset) * zoomLevel + 0.5

            guard adjustedBin >= 0 && adjustedBin <= 1 else { return nil }

            let x = CGFloat(adjustedBin) * rect.width
            let normalized = (values[index] + 120) / 120 // Normalize -120 to 0 dB
            let y = rect.height * (1 - CGFloat(max(0, min(1, normalized))))

            return (x, y)
        }

        guard let first = visibleBins.first else { return path }

        path.move(to: CGPoint(x: first.x, y: first.y))
        for point in visibleBins.dropFirst() {
            path.addLine(to: CGPoint(x: point.x, y: point.y))
        }

        return path
    }
}

struct MarkerView: View {
    let marker: WaterfallMarker
    let position: CGFloat
    let height: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            Text(marker.label)
                .font(.caption2)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(marker.color.swiftUIColor.opacity(0.8))
                .foregroundColor(.black)
                .cornerRadius(3)

            Rectangle()
                .fill(marker.color.swiftUIColor)
                .frame(width: 1, height: height - 20)
        }
        .position(x: position, y: height / 2)
    }
}

struct SignalLabelView: View {
    let label: SignalLabel
    let position: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Text(label.label)
                .font(.system(size: 9))
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(Color.blue.opacity(0.7))
                .foregroundColor(.white)
                .cornerRadius(2)

            Text(String(format: "%.0f dB", label.strength))
                .font(.system(size: 8))
                .foregroundColor(.gray)
        }
        .position(x: position, y: 30)
    }
}

// MARK: - Zoom Controls View

public struct ZoomControlsView: View {
    @ObservedObject var zoomManager = WaterfallZoomManager.shared

    public init() {}

    public var body: some View {
        HStack(spacing: 8) {
            Button {
                zoomManager.zoomOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .disabled(zoomManager.zoomLevel <= zoomManager.minZoom)

            Text(String(format: "%.1fx", zoomManager.zoomLevel))
                .font(.caption)
                .frame(width: 40)

            Button {
                zoomManager.zoomIn()
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .disabled(zoomManager.zoomLevel >= zoomManager.maxZoom)

            Button {
                zoomManager.reset()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial.opacity(0.7))
        .cornerRadius(6)
    }
}

// MARK: - Peak Hold Controls View

public struct PeakHoldControlsView: View {
    @ObservedObject var peakHold = PeakHoldManager.shared

    public init() {}

    public var body: some View {
        HStack(spacing: 8) {
            Toggle("Peak Hold", isOn: $peakHold.enabled)
                .toggleStyle(.switch)
                .controlSize(.mini)

            if peakHold.enabled {
                Button {
                    peakHold.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial.opacity(0.7))
        .cornerRadius(6)
    }
}

// MARK: - Marker Editor View

public struct MarkerEditorView: View {
    @ObservedObject var markerManager = MarkerManager.shared
    @State private var newLabel = ""
    @State private var newFrequency = ""
    @State private var newColor: WaterfallMarker.MarkerColor = .yellow
    @State private var showingAddSheet = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Markers")
                    .font(.headline)

                Spacer()

                Toggle("Show", isOn: $markerManager.showMarkers)
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }

            if markerManager.markers.isEmpty {
                Text("No markers")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                ForEach(markerManager.markers) { marker in
                    HStack {
                        Circle()
                            .fill(marker.color.swiftUIColor)
                            .frame(width: 8, height: 8)

                        Text(marker.label)
                            .font(.caption)
                            .lineLimit(1)

                        Spacer()

                        Text(FrequencyFormatter.format(marker.frequency))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button {
                            markerManager.removeMarker(marker)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .sheet(isPresented: $showingAddSheet) {
            AddMarkerSheet(
                label: $newLabel,
                frequency: $newFrequency,
                color: $newColor
            ) {
                if let freq = Double(newFrequency.replacingOccurrences(of: ",", with: "")) {
                    markerManager.addMarker(at: freq * 1_000_000, label: newLabel)
                    newLabel = ""
                    newFrequency = ""
                    showingAddSheet = false
                }
            }
        }
    }
}

struct AddMarkerSheet: View {
    @Binding var label: String
    @Binding var frequency: String
    @Binding var color: WaterfallMarker.MarkerColor

    var onAdd: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Marker")
                .font(.headline)

            TextField("Label", text: $label)
                .textFieldStyle(.roundedBorder)

            HStack {
                TextField("Frequency (MHz)", text: $frequency)
                    .textFieldStyle(.roundedBorder)
                Text("MHz")
            }

            Picker("Color", selection: $color) {
                ForEach(WaterfallMarker.MarkerColor.allCases, id: \.self) { c in
                    HStack {
                        Circle().fill(c.swiftUIColor).frame(width: 12, height: 12)
                        Text(c.rawValue.capitalized)
                    }.tag(c)
                }
            }

            HStack {
                Button("Cancel") {
                    label = ""
                    frequency = ""
                }
                .keyboardShortcut(.escape)

                Button("Add") {
                    onAdd()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 300)
    }
}

// MARK: - Scroll Wheel Zoom Handler

public struct ZoomableView<Content: View>: NSViewRepresentable {
    let content: Content
    let onZoom: (CGFloat, CGPoint) -> Void
    let onPan: (CGFloat) -> Void

    public init(
        @ViewBuilder content: () -> Content,
        onZoom: @escaping (CGFloat, CGPoint) -> Void,
        onPan: @escaping (CGFloat) -> Void
    ) {
        self.content = content()
        self.onZoom = onZoom
        self.onPan = onPan
    }

    public func makeNSView(context: Context) -> ZoomableNSView<Content> {
        let view = ZoomableNSView<Content>(onZoom: onZoom, onPan: onPan)
        return view
    }

    public func updateNSView(_ nsView: ZoomableNSView<Content>, context: Context) {}
}

public class ZoomableNSView<Content: View>: NSView {
    var onZoom: (CGFloat, CGPoint) -> Void
    var onPan: (CGFloat) -> Void

    init(onZoom: @escaping (CGFloat, CGPoint) -> Void, onPan: @escaping (CGFloat) -> Void) {
        self.onZoom = onZoom
        self.onPan = onPan
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            // Zoom with Cmd+scroll
            let delta = event.scrollingDeltaY
            let location = convert(event.locationInWindow, from: nil)
            onZoom(delta, location)
        } else if event.modifierFlags.contains(.shift) {
            // Pan with Shift+scroll
            let delta = event.scrollingDeltaX + event.scrollingDeltaY
            onPan(delta)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

// AVFoundation imports for video recording
import AVFoundation
