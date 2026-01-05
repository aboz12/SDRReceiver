import SwiftUI
import Foundation

// MARK: - Band Plan

public struct BandAllocation: Identifiable {
    public let id = UUID()
    public let name: String
    public let startFreq: Double
    public let endFreq: Double
    public let color: Color
    public let category: BandCategory

    public enum BandCategory: String, CaseIterable {
        case amateur = "Amateur"
        case broadcast = "Broadcast"
        case aviation = "Aviation"
        case marine = "Marine"
        case satellite = "Satellite"
        case ism = "ISM"
        case government = "Government"
        case other = "Other"
    }
}

public struct BandPlanManager {
    public static let shared = BandPlanManager()

    public let bands: [BandAllocation] = [
        // LF/MF Amateur
        BandAllocation(name: "160m", startFreq: 1_800_000, endFreq: 2_000_000, color: .purple, category: .amateur),
        BandAllocation(name: "80m", startFreq: 3_500_000, endFreq: 4_000_000, color: .purple, category: .amateur),
        BandAllocation(name: "60m", startFreq: 5_330_500, endFreq: 5_406_400, color: .purple, category: .amateur),
        BandAllocation(name: "40m", startFreq: 7_000_000, endFreq: 7_300_000, color: .purple, category: .amateur),
        BandAllocation(name: "30m", startFreq: 10_100_000, endFreq: 10_150_000, color: .purple, category: .amateur),
        BandAllocation(name: "20m", startFreq: 14_000_000, endFreq: 14_350_000, color: .purple, category: .amateur),
        BandAllocation(name: "17m", startFreq: 18_068_000, endFreq: 18_168_000, color: .purple, category: .amateur),
        BandAllocation(name: "15m", startFreq: 21_000_000, endFreq: 21_450_000, color: .purple, category: .amateur),
        BandAllocation(name: "12m", startFreq: 24_890_000, endFreq: 24_990_000, color: .purple, category: .amateur),
        BandAllocation(name: "10m", startFreq: 28_000_000, endFreq: 29_700_000, color: .purple, category: .amateur),
        BandAllocation(name: "6m", startFreq: 50_000_000, endFreq: 54_000_000, color: .purple, category: .amateur),
        BandAllocation(name: "2m", startFreq: 144_000_000, endFreq: 148_000_000, color: .purple, category: .amateur),
        BandAllocation(name: "1.25m", startFreq: 222_000_000, endFreq: 225_000_000, color: .purple, category: .amateur),
        BandAllocation(name: "70cm", startFreq: 420_000_000, endFreq: 450_000_000, color: .purple, category: .amateur),
        BandAllocation(name: "23cm", startFreq: 1_240_000_000, endFreq: 1_300_000_000, color: .purple, category: .amateur),

        // Broadcast
        BandAllocation(name: "AM BC", startFreq: 530_000, endFreq: 1_700_000, color: .green, category: .broadcast),
        BandAllocation(name: "FM BC", startFreq: 87_500_000, endFreq: 108_000_000, color: .green, category: .broadcast),
        BandAllocation(name: "DAB", startFreq: 174_000_000, endFreq: 230_000_000, color: .green, category: .broadcast),

        // Aviation
        BandAllocation(name: "Air VHF", startFreq: 118_000_000, endFreq: 137_000_000, color: .cyan, category: .aviation),
        BandAllocation(name: "ADS-B", startFreq: 1_090_000_000, endFreq: 1_090_000_000, color: .cyan, category: .aviation),

        // Marine
        BandAllocation(name: "Marine VHF", startFreq: 156_000_000, endFreq: 162_000_000, color: .blue, category: .marine),

        // ISM Bands
        BandAllocation(name: "ISM 433", startFreq: 433_050_000, endFreq: 434_790_000, color: .orange, category: .ism),
        BandAllocation(name: "ISM 868", startFreq: 868_000_000, endFreq: 870_000_000, color: .orange, category: .ism),
        BandAllocation(name: "ISM 915", startFreq: 902_000_000, endFreq: 928_000_000, color: .orange, category: .ism),

        // Satellite
        BandAllocation(name: "GPS L1", startFreq: 1_575_420_000, endFreq: 1_575_420_000, color: .yellow, category: .satellite),
        BandAllocation(name: "Inmarsat", startFreq: 1_525_000_000, endFreq: 1_559_000_000, color: .yellow, category: .satellite),
        BandAllocation(name: "Iridium", startFreq: 1_616_000_000, endFreq: 1_626_500_000, color: .yellow, category: .satellite),
    ]

    public func bandsInRange(_ range: ClosedRange<Double>) -> [BandAllocation] {
        bands.filter { band in
            band.endFreq >= range.lowerBound && band.startFreq <= range.upperBound
        }
    }
}

// MARK: - Band Plan Overlay View

public struct BandPlanOverlay: View {
    let visibleRange: ClosedRange<Double>
    let width: CGFloat
    var showLabels: Bool = true

    private let bandPlan = BandPlanManager.shared

    public var body: some View {
        ZStack(alignment: .top) {
            ForEach(bandPlan.bandsInRange(visibleRange)) { band in
                let startX = frequencyToX(band.startFreq)
                let endX = frequencyToX(band.endFreq)
                let bandWidth = max(2, endX - startX)

                VStack(spacing: 0) {
                    Rectangle()
                        .fill(band.color.opacity(0.3))
                        .frame(width: bandWidth)

                    if showLabels && bandWidth > 30 {
                        Text(band.name)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(band.color)
                            .frame(width: bandWidth)
                            .lineLimit(1)
                    }
                }
                .position(x: startX + bandWidth / 2, y: 0)
            }
        }
        .frame(height: 20)
    }

    private func frequencyToX(_ freq: Double) -> CGFloat {
        let span = visibleRange.upperBound - visibleRange.lowerBound
        let offset = freq - visibleRange.lowerBound
        return CGFloat(offset / span) * width
    }
}

// MARK: - Signal History

@MainActor
public final class SignalHistoryManager: ObservableObject {
    public static let shared = SignalHistoryManager()

    @Published public var history: [SignalSample] = []
    @Published public var isRecording = false
    @Published public var maxSamples = 300  // 5 minutes at 1 sample/sec

    private var timer: Timer?

    public struct SignalSample: Identifiable {
        public let id = UUID()
        public let timestamp: Date
        public let frequency: Double
        public let strength: Float
        public let squelchOpen: Bool
    }

    private init() {}

    public func startRecording(sdrEngine: SDREngine) {
        isRecording = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordSample(sdrEngine: sdrEngine)
            }
        }
    }

    public func stopRecording() {
        isRecording = false
        timer?.invalidate()
        timer = nil
    }

    private func recordSample(sdrEngine: SDREngine) {
        let sample = SignalSample(
            timestamp: Date(),
            frequency: sdrEngine.frequency,
            strength: sdrEngine.dspEngine.signalStrength,
            squelchOpen: sdrEngine.dspEngine.signalStrength > sdrEngine.dspEngine.squelchLevel
        )

        history.append(sample)

        if history.count > maxSamples {
            history.removeFirst()
        }
    }

    public func clear() {
        history.removeAll()
    }

    public func exportToCSV() -> String {
        var csv = "Timestamp,Frequency,Strength_dB,Squelch_Open\n"
        let formatter = ISO8601DateFormatter()

        for sample in history {
            csv += "\(formatter.string(from: sample.timestamp)),"
            csv += "\(sample.frequency),"
            csv += "\(sample.strength),"
            csv += "\(sample.squelchOpen)\n"
        }

        return csv
    }
}

public struct SignalHistoryView: View {
    @ObservedObject var manager = SignalHistoryManager.shared
    @EnvironmentObject var sdrEngine: SDREngine

    public var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Signal History")
                    .font(.system(size: 12, weight: .medium))

                Spacer()

                Button {
                    if manager.isRecording {
                        manager.stopRecording()
                    } else {
                        manager.startRecording(sdrEngine: sdrEngine)
                    }
                } label: {
                    Image(systemName: manager.isRecording ? "stop.circle.fill" : "record.circle")
                        .foregroundColor(manager.isRecording ? .red : .green)
                }
                .buttonStyle(.plain)

                Button {
                    manager.clear()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    exportCSV()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Graph
            GeometryReader { geometry in
                Canvas { context, size in
                    guard !manager.history.isEmpty else { return }

                    let minStrength: Float = -120
                    let maxStrength: Float = -20

                    var path = Path()

                    for (index, sample) in manager.history.enumerated() {
                        let x = CGFloat(index) / CGFloat(max(1, manager.history.count - 1)) * size.width
                        let normalizedStrength = (sample.strength - minStrength) / (maxStrength - minStrength)
                        let y = size.height - CGFloat(normalizedStrength) * size.height

                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }

                    context.stroke(path, with: .color(.cyan), lineWidth: 1.5)

                    // Squelch line
                    let squelchY = size.height - CGFloat((sdrEngine.dspEngine.squelchLevel - minStrength) / (maxStrength - minStrength)) * size.height
                    var squelchPath = Path()
                    squelchPath.move(to: CGPoint(x: 0, y: squelchY))
                    squelchPath.addLine(to: CGPoint(x: size.width, y: squelchY))
                    context.stroke(squelchPath, with: .color(.yellow.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .frame(height: 80)
            .background(Color.black.opacity(0.3))
            .cornerRadius(8)

            // Stats
            if let last = manager.history.last {
                HStack {
                    Text("\(Int(last.strength)) dB")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.cyan)

                    Spacer()

                    Text("\(manager.history.count) samples")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial.opacity(0.5))
        .cornerRadius(8)
    }

    private func exportCSV() {
        let csv = manager.exportToCSV()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "signal_history.csv"

        if panel.runModal() == .OK, let url = panel.url {
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Frequency Presets

public struct FrequencyPreset: Identifiable, Codable {
    public let id: UUID
    public let name: String
    public let frequency: Double
    public let mode: String
    public let bandwidth: Double
    public let category: String
    public let icon: String

    public init(name: String, frequency: Double, mode: String = "FM", bandwidth: Double = 12500, category: String = "General", icon: String = "antenna.radiowaves.left.and.right") {
        self.id = UUID()
        self.name = name
        self.frequency = frequency
        self.mode = mode
        self.bandwidth = bandwidth
        self.category = category
        self.icon = icon
    }
}

@MainActor
public final class FrequencyPresetManager: ObservableObject {
    public static let shared = FrequencyPresetManager()

    @Published public var presets: [FrequencyPreset] = []

    private init() {
        loadDefaults()
    }

    private func loadDefaults() {
        presets = [
            // FM Broadcast
            FrequencyPreset(name: "FM Radio", frequency: 98_000_000, mode: "WFM", bandwidth: 200000, category: "Broadcast", icon: "radio"),

            // Aviation
            FrequencyPreset(name: "Air Emergency", frequency: 121_500_000, mode: "AM", bandwidth: 8000, category: "Aviation", icon: "airplane"),
            FrequencyPreset(name: "Air Traffic", frequency: 118_000_000, mode: "AM", bandwidth: 8000, category: "Aviation", icon: "airplane"),
            FrequencyPreset(name: "ATIS", frequency: 127_000_000, mode: "AM", bandwidth: 8000, category: "Aviation", icon: "airplane"),
            FrequencyPreset(name: "ADS-B", frequency: 1_090_000_000, mode: "RAW", bandwidth: 2000000, category: "Aviation", icon: "airplane"),

            // Amateur
            FrequencyPreset(name: "2m Call", frequency: 146_520_000, mode: "FM", bandwidth: 12500, category: "Amateur", icon: "person.wave.2"),
            FrequencyPreset(name: "2m Repeater", frequency: 146_940_000, mode: "FM", bandwidth: 12500, category: "Amateur", icon: "person.wave.2"),
            FrequencyPreset(name: "70cm Call", frequency: 446_000_000, mode: "FM", bandwidth: 12500, category: "Amateur", icon: "person.wave.2"),
            FrequencyPreset(name: "FT8 20m", frequency: 14_074_000, mode: "USB", bandwidth: 3000, category: "Amateur", icon: "waveform"),
            FrequencyPreset(name: "FT8 40m", frequency: 7_074_000, mode: "USB", bandwidth: 3000, category: "Amateur", icon: "waveform"),

            // Marine
            FrequencyPreset(name: "Marine Ch16", frequency: 156_800_000, mode: "FM", bandwidth: 12500, category: "Marine", icon: "ferry"),
            FrequencyPreset(name: "Marine Distress", frequency: 156_800_000, mode: "FM", bandwidth: 12500, category: "Marine", icon: "ferry"),

            // Weather
            FrequencyPreset(name: "NOAA Weather", frequency: 162_550_000, mode: "FM", bandwidth: 12500, category: "Weather", icon: "cloud.sun"),
            FrequencyPreset(name: "NOAA APT", frequency: 137_620_000, mode: "FM", bandwidth: 40000, category: "Weather", icon: "cloud.sun"),

            // Satellite
            FrequencyPreset(name: "ISS Voice", frequency: 145_800_000, mode: "FM", bandwidth: 12500, category: "Satellite", icon: "sparkles"),
            FrequencyPreset(name: "ISS APRS", frequency: 145_825_000, mode: "FM", bandwidth: 12500, category: "Satellite", icon: "sparkles"),

            // Utility
            FrequencyPreset(name: "POCSAG", frequency: 153_350_000, mode: "FM", bandwidth: 12500, category: "Utility", icon: "bell"),
            FrequencyPreset(name: "LoRa 433", frequency: 433_775_000, mode: "RAW", bandwidth: 125000, category: "Utility", icon: "wifi"),
        ]
    }

    public var categories: [String] {
        Array(Set(presets.map { $0.category })).sorted()
    }

    public func presets(for category: String) -> [FrequencyPreset] {
        presets.filter { $0.category == category }
    }
}

public struct FrequencyPresetsView: View {
    @ObservedObject var manager = FrequencyPresetManager.shared
    var onSelect: (FrequencyPreset) -> Void

    @State private var selectedCategory: String?

    public var body: some View {
        VStack(spacing: 8) {
            // Category tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(manager.categories, id: \.self) { category in
                        Button {
                            selectedCategory = (selectedCategory == category) ? nil : category
                        } label: {
                            Text(category)
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(selectedCategory == category ? Color.cyan : Color.gray.opacity(0.3))
                                .foregroundColor(selectedCategory == category ? .white : .primary)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
            }

            // Presets
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let filteredPresets = selectedCategory.map { manager.presets(for: $0) } ?? manager.presets

                    ForEach(filteredPresets) { preset in
                        PresetButton(preset: preset) {
                            onSelect(preset)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial.opacity(0.3))
    }
}

struct PresetButton: View {
    let preset: FrequencyPreset
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: preset.icon)
                    .font(.system(size: 16))
                    .foregroundColor(.cyan)

                Text(preset.name)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)

                Text(formatFreq(preset.frequency))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? Color.cyan.opacity(0.2) : Color.black.opacity(0.2))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.cyan.opacity(isHovered ? 0.5 : 0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func formatFreq(_ freq: Double) -> String {
        if freq >= 1_000_000_000 {
            return String(format: "%.3f G", freq / 1_000_000_000)
        } else if freq >= 1_000_000 {
            return String(format: "%.3f M", freq / 1_000_000)
        } else {
            return String(format: "%.1f k", freq / 1_000)
        }
    }
}

// MARK: - Notch Filter

@MainActor
public final class NotchFilterManager: ObservableObject {
    public static let shared = NotchFilterManager()

    @Published public var notches: [NotchFilter] = []
    @Published public var isEnabled = true

    public struct NotchFilter: Identifiable {
        public let id = UUID()
        public var frequency: Double
        public var bandwidth: Double
        public var depth: Float  // dB reduction

        public init(frequency: Double, bandwidth: Double = 500, depth: Float = 40) {
            self.frequency = frequency
            self.bandwidth = bandwidth
            self.depth = depth
        }
    }

    private init() {}

    public func addNotch(at frequency: Double, bandwidth: Double = 500) {
        let notch = NotchFilter(frequency: frequency, bandwidth: bandwidth)
        notches.append(notch)
    }

    public func removeNotch(_ notch: NotchFilter) {
        notches.removeAll { $0.id == notch.id }
    }

    public func clearAll() {
        notches.removeAll()
    }
}

// MARK: - Auto Signal Detection

@MainActor
public final class SignalDetector: ObservableObject {
    public static let shared = SignalDetector()

    @Published public var detectedSignals: [DetectedSignal] = []
    @Published public var isScanning = false
    @Published public var threshold: Float = -90  // dB threshold
    @Published public var minBandwidth: Double = 5000  // Hz

    public struct DetectedSignal: Identifiable {
        public let id = UUID()
        public let frequency: Double
        public let strength: Float
        public let bandwidth: Double
        public let timestamp: Date

        public var formattedFrequency: String {
            FrequencyFormatter.format(frequency)
        }
    }

    private init() {}

    public func analyzeSpectrum(_ spectrum: SpectrumData, centerFrequency: Double, sampleRate: Double) {
        guard isScanning else { return }

        var newSignals: [DetectedSignal] = []
        let binWidth = sampleRate / Double(spectrum.magnitudes.count)

        var inSignal = false
        var signalStart = 0
        var peakStrength: Float = -120
        var peakBin = 0

        for (index, magnitude) in spectrum.magnitudes.enumerated() {
            if magnitude > threshold {
                if !inSignal {
                    inSignal = true
                    signalStart = index
                    peakStrength = magnitude
                    peakBin = index
                } else if magnitude > peakStrength {
                    peakStrength = magnitude
                    peakBin = index
                }
            } else if inSignal {
                // End of signal
                let signalWidth = Double(index - signalStart) * binWidth
                if signalWidth >= minBandwidth {
                    let freq = centerFrequency - sampleRate / 2 + Double(peakBin) * binWidth
                    let signal = DetectedSignal(
                        frequency: freq,
                        strength: peakStrength,
                        bandwidth: signalWidth,
                        timestamp: Date()
                    )
                    newSignals.append(signal)
                }
                inSignal = false
            }
        }

        // Merge with existing, remove old
        let cutoff = Date().addingTimeInterval(-10)
        detectedSignals = detectedSignals.filter { $0.timestamp > cutoff }

        for newSignal in newSignals {
            if !detectedSignals.contains(where: { abs($0.frequency - newSignal.frequency) < minBandwidth }) {
                detectedSignals.append(newSignal)
            }
        }

        // Limit count
        if detectedSignals.count > 20 {
            detectedSignals = Array(detectedSignals.suffix(20))
        }
    }
}

public struct DetectedSignalsView: View {
    @ObservedObject var detector = SignalDetector.shared
    var onSelect: (SignalDetector.DetectedSignal) -> Void

    public var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Detected Signals")
                    .font(.system(size: 12, weight: .medium))

                Spacer()

                Toggle("", isOn: $detector.isScanning)
                    .toggleStyle(.switch)
                    .scaleEffect(0.7)
            }

            if detector.detectedSignals.isEmpty {
                Text("No signals detected")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(detector.detectedSignals) { signal in
                            HStack {
                                Circle()
                                    .fill(signalColor(signal.strength))
                                    .frame(width: 8, height: 8)

                                Text(signal.formattedFrequency)
                                    .font(.system(size: 11, design: .monospaced))

                                Spacer()

                                Text("\(Int(signal.strength)) dB")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.2))
                            .cornerRadius(4)
                            .onTapGesture {
                                onSelect(signal)
                            }
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial.opacity(0.5))
        .cornerRadius(8)
    }

    private func signalColor(_ strength: Float) -> Color {
        if strength > -50 { return .red }
        if strength > -70 { return .orange }
        if strength > -90 { return .green }
        return .blue
    }
}

// MARK: - Recording Scheduler

@MainActor
public final class RecordingScheduler: ObservableObject {
    public static let shared = RecordingScheduler()

    @Published public var scheduledRecordings: [ScheduledRecording] = []
    @Published public var isEnabled = true

    public struct ScheduledRecording: Identifiable, Codable {
        public let id: UUID
        public var frequency: Double
        public var mode: String
        public var startTime: Date
        public var duration: TimeInterval  // seconds
        public var repeatDaily: Bool
        public var isActive: Bool

        public init(frequency: Double, mode: String, startTime: Date, duration: TimeInterval, repeatDaily: Bool = false) {
            self.id = UUID()
            self.frequency = frequency
            self.mode = mode
            self.startTime = startTime
            self.duration = duration
            self.repeatDaily = repeatDaily
            self.isActive = true
        }
    }

    private var checkTimer: Timer?

    private init() {
        startMonitoring()
    }

    private func startMonitoring() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkSchedule()
            }
        }
    }

    private func checkSchedule() {
        guard isEnabled else { return }

        let now = Date()

        for recording in scheduledRecordings where recording.isActive {
            let endTime = recording.startTime.addingTimeInterval(recording.duration)

            if now >= recording.startTime && now <= endTime {
                // Should be recording
                startScheduledRecording(recording)
            }
        }
    }

    private func startScheduledRecording(_ recording: ScheduledRecording) {
        // TODO: Implement actual recording trigger
        print("Starting scheduled recording at \(recording.frequency)")
    }

    public func addSchedule(_ recording: ScheduledRecording) {
        scheduledRecordings.append(recording)
    }

    public func removeSchedule(_ recording: ScheduledRecording) {
        scheduledRecordings.removeAll { $0.id == recording.id }
    }
}

// MARK: - Frequency Database

public struct FrequencyDatabaseEntry: Identifiable, Codable {
    public let id: UUID
    public let frequency: Double
    public let name: String
    public let description: String
    public let category: String
    public let location: String?
    public let mode: String

    public init(frequency: Double, name: String, description: String = "", category: String = "Unknown", location: String? = nil, mode: String = "FM") {
        self.id = UUID()
        self.frequency = frequency
        self.name = name
        self.description = description
        self.category = category
        self.location = location
        self.mode = mode
    }
}

@MainActor
public final class FrequencyDatabase: ObservableObject {
    public static let shared = FrequencyDatabase()

    @Published public var entries: [FrequencyDatabaseEntry] = []

    private init() {
        loadDefaults()
    }

    private func loadDefaults() {
        entries = [
            // Some example entries
            FrequencyDatabaseEntry(frequency: 121_500_000, name: "Air Emergency", description: "International air distress frequency", category: "Aviation", mode: "AM"),
            FrequencyDatabaseEntry(frequency: 156_800_000, name: "Marine Ch 16", description: "International distress and calling", category: "Marine", mode: "FM"),
            FrequencyDatabaseEntry(frequency: 146_520_000, name: "2m Simplex", description: "National simplex calling frequency", category: "Amateur", mode: "FM"),
            FrequencyDatabaseEntry(frequency: 162_550_000, name: "NOAA Weather", description: "Weather broadcast", category: "Weather", mode: "FM"),
        ]
    }

    public func lookup(frequency: Double, tolerance: Double = 5000) -> FrequencyDatabaseEntry? {
        entries.first { abs($0.frequency - frequency) <= tolerance }
    }

    public func search(query: String) -> [FrequencyDatabaseEntry] {
        let lowercased = query.lowercased()
        return entries.filter {
            $0.name.lowercased().contains(lowercased) ||
            $0.description.lowercased().contains(lowercased) ||
            $0.category.lowercased().contains(lowercased)
        }
    }
}

// MARK: - Sample Rate Picker

public struct SampleRatePicker: View {
    @EnvironmentObject var sdrEngine: SDREngine

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Visible Bandwidth")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)

            Picker("", selection: $sdrEngine.sampleRate) {
                ForEach(sdrEngine.availableSampleRates, id: \.self) { rate in
                    Text(formatRate(rate)).tag(rate)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)
        }
    }

    private func formatRate(_ rate: Double) -> String {
        if rate >= 1_000_000 {
            return String(format: "%.2f MHz", rate / 1_000_000)
        } else {
            return String(format: "%.0f kHz", rate / 1_000)
        }
    }
}

// MARK: - Mini Mode Window

public struct MiniModeView: View {
    @EnvironmentObject var sdrEngine: SDREngine
    @ObservedObject var bookmarkManager = QuickBookmarkManager.shared

    public var body: some View {
        VStack(spacing: 8) {
            // Frequency
            InteractiveFrequencyDisplay(
                frequency: Binding(
                    get: { sdrEngine.frequency },
                    set: { sdrEngine.tuneTo($0) }
                ),
                tint: .cyan,
                onBookmark: {
                    bookmarkManager.addBookmark(
                        frequency: sdrEngine.frequency,
                        mode: sdrEngine.dspEngine.demodulationMode.rawValue
                    )
                }
            )

            // Mode and controls
            HStack(spacing: 12) {
                // Mode picker
                Picker("", selection: $sdrEngine.dspEngine.demodulationMode) {
                    ForEach(DemodulationMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                Spacer()

                // Signal meter
                HStack(spacing: 4) {
                    ForEach(0..<10, id: \.self) { i in
                        let threshold = Float(i) * 10 - 100
                        let isActive = sdrEngine.dspEngine.signalStrength > threshold
                        Rectangle()
                            .fill(isActive ? meterColor(i) : Color.gray.opacity(0.3))
                            .frame(width: 4, height: CGFloat(6 + i))
                    }
                }

                Text("\(Int(sdrEngine.dspEngine.signalStrength)) dB")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.cyan)
                    .frame(width: 50)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    private func meterColor(_ index: Int) -> Color {
        if index < 6 { return .green }
        if index < 8 { return .yellow }
        return .red
    }
}
