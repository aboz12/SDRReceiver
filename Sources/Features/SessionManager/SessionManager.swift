import SwiftUI
import Foundation

// MARK: - Frequency History

@MainActor
public final class FrequencyHistory: ObservableObject {
    public static let shared = FrequencyHistory()

    @Published public private(set) var history: [FrequencyHistoryEntry] = []
    @Published public var currentIndex: Int = -1
    @Published public var maxHistory: Int = 100

    public struct FrequencyHistoryEntry: Identifiable, Codable {
        public let id: UUID
        public let frequency: Double
        public let mode: String
        public let timestamp: Date

        public init(frequency: Double, mode: String) {
            self.id = UUID()
            self.frequency = frequency
            self.mode = mode
            self.timestamp = Date()
        }
    }

    private var lastFrequency: Double = 0
    private var debounceTimer: Timer?

    private init() {}

    public func recordFrequency(_ frequency: Double, mode: String) {
        // Debounce rapid changes (e.g., during tuning)
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.addEntry(frequency: frequency, mode: mode)
            }
        }
    }

    private func addEntry(frequency: Double, mode: String) {
        // Don't add if same as last entry
        if let last = history.last, abs(last.frequency - frequency) < 1000 {
            return
        }

        // Remove forward history if we're not at the end
        if currentIndex < history.count - 1 {
            history = Array(history.prefix(currentIndex + 1))
        }

        let entry = FrequencyHistoryEntry(frequency: frequency, mode: mode)
        history.append(entry)
        currentIndex = history.count - 1

        // Limit history size
        if history.count > maxHistory {
            history.removeFirst()
            currentIndex -= 1
        }

        lastFrequency = frequency
    }

    public var canGoBack: Bool {
        currentIndex > 0
    }

    public var canGoForward: Bool {
        currentIndex < history.count - 1
    }

    public func goBack() -> FrequencyHistoryEntry? {
        guard canGoBack else { return nil }
        currentIndex -= 1
        return history[currentIndex]
    }

    public func goForward() -> FrequencyHistoryEntry? {
        guard canGoForward else { return nil }
        currentIndex += 1
        return history[currentIndex]
    }

    public func clear() {
        history.removeAll()
        currentIndex = -1
    }
}

// MARK: - Session Manager

@MainActor
public final class SessionManager: ObservableObject {
    public static let shared = SessionManager()

    private let defaults = UserDefaults.standard
    private let sessionKey = "SDRSession"

    public struct SessionData: Codable {
        var frequency: Double
        var mode: String
        var gain: Double
        var gainMode: String
        var sampleRate: Double
        var filterBandwidth: Double
        var squelchLevel: Float
        var squelchEnabled: Bool
        var agcEnabled: Bool
        var volume: Float
        var showSpectrum: Bool
        var showWaterfall: Bool
        var theme: String
        var windowFrame: WindowFrame?
        var lastDevice: String?

        struct WindowFrame: Codable {
            var x: Double
            var y: Double
            var width: Double
            var height: Double
        }
    }

    private init() {}

    public func saveSession(from sdrEngine: SDREngine, appState: AppState) {
        let session = SessionData(
            frequency: sdrEngine.frequency,
            mode: sdrEngine.dspEngine.demodulationMode.rawValue,
            gain: sdrEngine.gain,
            gainMode: sdrEngine.gainMode.rawValue,
            sampleRate: sdrEngine.sampleRate,
            filterBandwidth: sdrEngine.dspEngine.filterBandwidth,
            squelchLevel: sdrEngine.dspEngine.squelchLevel,
            squelchEnabled: sdrEngine.dspEngine.squelchEnabled,
            agcEnabled: sdrEngine.dspEngine.agcEnabled,
            volume: 1.0,
            showSpectrum: appState.showSpectrum,
            showWaterfall: appState.showWaterfall,
            theme: ThemeManager.shared.currentTheme.name,
            windowFrame: nil,
            lastDevice: sdrEngine.currentDevice?.name
        )

        if let encoded = try? JSONEncoder().encode(session) {
            defaults.set(encoded, forKey: sessionKey)
        }
    }

    public func restoreSession(to sdrEngine: SDREngine, appState: AppState) {
        guard let data = defaults.data(forKey: sessionKey),
              let session = try? JSONDecoder().decode(SessionData.self, from: data) else {
            return
        }

        // Restore frequency and mode
        sdrEngine.frequency = session.frequency
        if let mode = DemodulationMode(rawValue: session.mode) {
            sdrEngine.dspEngine.demodulationMode = mode
        }

        // Restore gain
        sdrEngine.gain = session.gain
        if let gainMode = GainMode(rawValue: session.gainMode) {
            sdrEngine.gainMode = gainMode
        }

        // Restore sample rate
        sdrEngine.sampleRate = session.sampleRate

        // Restore DSP settings
        sdrEngine.dspEngine.filterBandwidth = session.filterBandwidth
        sdrEngine.dspEngine.squelchLevel = session.squelchLevel
        sdrEngine.dspEngine.squelchEnabled = session.squelchEnabled
        sdrEngine.dspEngine.agcEnabled = session.agcEnabled

        // Restore display settings
        appState.showSpectrum = session.showSpectrum
        appState.showWaterfall = session.showWaterfall

        // Restore theme
        if let theme = ThemeManager.shared.themes.first(where: { $0.name == session.theme }) {
            ThemeManager.shared.currentTheme = theme
        }
    }

    public func clearSession() {
        defaults.removeObject(forKey: sessionKey)
    }
}

// MARK: - History Navigation View

public struct FrequencyHistoryNav: View {
    @ObservedObject var history = FrequencyHistory.shared
    var onNavigate: (FrequencyHistory.FrequencyHistoryEntry) -> Void

    public var body: some View {
        HStack(spacing: 4) {
            Button {
                if let entry = history.goBack() {
                    onNavigate(entry)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(!history.canGoBack)
            .foregroundColor(history.canGoBack ? .cyan : .gray)

            Button {
                if let entry = history.goForward() {
                    onNavigate(entry)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(!history.canGoForward)
            .foregroundColor(history.canGoForward ? .cyan : .gray)

            if !history.history.isEmpty {
                Menu {
                    ForEach(Array(history.history.enumerated().reversed().prefix(20)), id: \.element.id) { index, entry in
                        Button {
                            history.currentIndex = index
                            onNavigate(entry)
                        } label: {
                            HStack {
                                if index == history.currentIndex {
                                    Image(systemName: "checkmark")
                                }
                                Text(FrequencyFormatter.format(entry.frequency))
                                Text(entry.mode)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Divider()

                    Button("Clear History") {
                        history.clear()
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial.opacity(0.5))
        .cornerRadius(8)
    }
}

// MARK: - Direct Frequency Input

public struct DirectFrequencyInput: View {
    @Binding var isPresented: Bool
    @State private var inputText = ""
    @State private var unit: FrequencyUnit = .mhz
    var onSubmit: (Double) -> Void

    enum FrequencyUnit: String, CaseIterable {
        case hz = "Hz"
        case khz = "kHz"
        case mhz = "MHz"
        case ghz = "GHz"

        var multiplier: Double {
            switch self {
            case .hz: return 1
            case .khz: return 1_000
            case .mhz: return 1_000_000
            case .ghz: return 1_000_000_000
            }
        }
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("Enter Frequency")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("Frequency", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                    .onSubmit { submit() }

                Picker("", selection: $unit) {
                    ForEach(FrequencyUnit.allCases, id: \.self) { u in
                        Text(u.rawValue).tag(u)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            // Quick presets
            HStack(spacing: 8) {
                ForEach(["98.1", "118.0", "144.0", "432.0"], id: \.self) { preset in
                    Button(preset) {
                        inputText = preset
                        unit = .mhz
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack(spacing: 16) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Button("Tune") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private func submit() {
        guard let value = Double(inputText) else { return }
        let frequency = value * unit.multiplier
        onSubmit(frequency)
        isPresented = false
    }
}

// MARK: - Clipboard Support

public struct FrequencyClipboard {
    public static func copy(_ frequency: Double) {
        let formatted = FrequencyFormatter.format(frequency)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(formatted, forType: .string)
        NSPasteboard.general.setString(String(format: "%.0f", frequency), forType: .init("public.plain-text"))
    }

    public static func paste() -> Double? {
        guard let string = NSPasteboard.general.string(forType: .string) else { return nil }

        // Try to parse as number
        let cleaned = string.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()

        // Check for units
        if cleaned.hasSuffix("ghz") || cleaned.hasSuffix("g") {
            if let value = Double(cleaned.dropLast(cleaned.hasSuffix("ghz") ? 3 : 1)) {
                return value * 1_000_000_000
            }
        } else if cleaned.hasSuffix("mhz") || cleaned.hasSuffix("m") {
            if let value = Double(cleaned.dropLast(cleaned.hasSuffix("mhz") ? 3 : 1)) {
                return value * 1_000_000
            }
        } else if cleaned.hasSuffix("khz") || cleaned.hasSuffix("k") {
            if let value = Double(cleaned.dropLast(cleaned.hasSuffix("khz") ? 3 : 1)) {
                return value * 1_000
            }
        } else if cleaned.hasSuffix("hz") {
            if let value = Double(cleaned.dropLast(2)) {
                return value
            }
        }

        // Try as raw number
        return Double(cleaned)
    }
}
