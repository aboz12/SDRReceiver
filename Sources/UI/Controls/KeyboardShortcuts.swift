import SwiftUI
import AppKit

// MARK: - Keyboard Shortcut Manager

@MainActor
public final class KeyboardShortcutManager: ObservableObject {
    public static let shared = KeyboardShortcutManager()

    // Frequency tuning
    @Published public var tuneUpSmall: KeyboardShortcut = KeyboardShortcut(.upArrow)
    @Published public var tuneDownSmall: KeyboardShortcut = KeyboardShortcut(.downArrow)
    @Published public var tuneUpMedium: KeyboardShortcut = KeyboardShortcut(.upArrow, modifiers: .shift)
    @Published public var tuneDownMedium: KeyboardShortcut = KeyboardShortcut(.downArrow, modifiers: .shift)
    @Published public var tuneUpLarge: KeyboardShortcut = KeyboardShortcut(.upArrow, modifiers: .command)
    @Published public var tuneDownLarge: KeyboardShortcut = KeyboardShortcut(.downArrow, modifiers: .command)

    // Step sizes
    @Published public var smallStep: Double = 1000       // 1 kHz
    @Published public var mediumStep: Double = 10000     // 10 kHz
    @Published public var largeStep: Double = 100000     // 100 kHz

    // Mode shortcuts
    @Published public var modeAM: KeyboardShortcut = KeyboardShortcut("1")
    @Published public var modeFM: KeyboardShortcut = KeyboardShortcut("2")
    @Published public var modeWFM: KeyboardShortcut = KeyboardShortcut("3")
    @Published public var modeLSB: KeyboardShortcut = KeyboardShortcut("4")
    @Published public var modeUSB: KeyboardShortcut = KeyboardShortcut("5")
    @Published public var modeCW: KeyboardShortcut = KeyboardShortcut("6")

    // VFO shortcuts
    @Published public var vfoA: KeyboardShortcut = KeyboardShortcut("a", modifiers: .command)
    @Published public var vfoB: KeyboardShortcut = KeyboardShortcut("b", modifiers: .command)
    @Published public var vfoSwap: KeyboardShortcut = KeyboardShortcut("x", modifiers: .command)

    // Recording
    @Published public var recordIQ: KeyboardShortcut = KeyboardShortcut("r", modifiers: .command)
    @Published public var recordAudio: KeyboardShortcut = KeyboardShortcut("r", modifiers: [.command, .shift])

    // Scanner
    @Published public var startScan: KeyboardShortcut = KeyboardShortcut("s", modifiers: .command)
    @Published public var stopScan: KeyboardShortcut = KeyboardShortcut(.escape)

    // Memory
    @Published public var addMemory: KeyboardShortcut = KeyboardShortcut("m", modifiers: .command)
    @Published public var quickMemory1: KeyboardShortcut = KeyboardShortcut("1", modifiers: .option)
    @Published public var quickMemory2: KeyboardShortcut = KeyboardShortcut("2", modifiers: .option)
    @Published public var quickMemory3: KeyboardShortcut = KeyboardShortcut("3", modifiers: .option)

    // Gain
    @Published public var gainUp: KeyboardShortcut = KeyboardShortcut(.rightArrow)
    @Published public var gainDown: KeyboardShortcut = KeyboardShortcut(.leftArrow)
    @Published public var agcToggle: KeyboardShortcut = KeyboardShortcut("g", modifiers: .command)

    // Volume
    @Published public var volumeUp: KeyboardShortcut = KeyboardShortcut(.rightArrow, modifiers: .shift)
    @Published public var volumeDown: KeyboardShortcut = KeyboardShortcut(.leftArrow, modifiers: .shift)
    @Published public var mute: KeyboardShortcut = KeyboardShortcut("m", modifiers: .option)

    // Zoom/Pan
    @Published public var zoomIn: KeyboardShortcut = KeyboardShortcut("+", modifiers: .command)
    @Published public var zoomOut: KeyboardShortcut = KeyboardShortcut("-", modifiers: .command)
    @Published public var zoomFit: KeyboardShortcut = KeyboardShortcut("0", modifiers: .command)

    private init() {}
}

// MARK: - Keyboard Handler View Modifier

public struct KeyboardShortcutsModifier: ViewModifier {
    @ObservedObject var shortcuts = KeyboardShortcutManager.shared
    @EnvironmentObject var sdrEngine: SDREngine

    public func body(content: Content) -> some View {
        content
            // Frequency tuning
            .keyboardShortcut(.upArrow, modifiers: []) { tuneFrequency(by: shortcuts.smallStep) }
            .keyboardShortcut(.downArrow, modifiers: []) { tuneFrequency(by: -shortcuts.smallStep) }
            .keyboardShortcut(.upArrow, modifiers: .shift) { tuneFrequency(by: shortcuts.mediumStep) }
            .keyboardShortcut(.downArrow, modifiers: .shift) { tuneFrequency(by: -shortcuts.mediumStep) }
            .keyboardShortcut(.upArrow, modifiers: .command) { tuneFrequency(by: shortcuts.largeStep) }
            .keyboardShortcut(.downArrow, modifiers: .command) { tuneFrequency(by: -shortcuts.largeStep) }

            // Modes
            .keyboardShortcut("1", modifiers: []) { setMode(.am) }
            .keyboardShortcut("2", modifiers: []) { setMode(.fm) }
            .keyboardShortcut("3", modifiers: []) { setMode(.wfm) }
            .keyboardShortcut("4", modifiers: []) { setMode(.lsb) }
            .keyboardShortcut("5", modifiers: []) { setMode(.usb) }
            .keyboardShortcut("6", modifiers: []) { setMode(.cw) }

            // VFO
            .keyboardShortcut("a", modifiers: .command) { selectVFO(0) }
            .keyboardShortcut("b", modifiers: .command) { selectVFO(1) }
            .keyboardShortcut("x", modifiers: .command) { swapVFO() }

            // Recording
            .keyboardShortcut("r", modifiers: .command) { toggleIQRecording() }
            .keyboardShortcut("r", modifiers: [.command, .shift]) { toggleAudioRecording() }

            // Scanner
            .keyboardShortcut("s", modifiers: .command) { toggleScanner() }

            // Gain
            .keyboardShortcut(.rightArrow, modifiers: []) { adjustGain(by: 1) }
            .keyboardShortcut(.leftArrow, modifiers: []) { adjustGain(by: -1) }

            // Zoom
            .keyboardShortcut("+", modifiers: .command) { zoomSpectrum(factor: 0.8) }
            .keyboardShortcut("-", modifiers: .command) { zoomSpectrum(factor: 1.25) }
            .keyboardShortcut("0", modifiers: .command) { resetZoom() }
    }

    private func tuneFrequency(by delta: Double) {
        let newFreq = sdrEngine.frequency + delta
        sdrEngine.tuneTo(newFreq)
        MultiVFOManager.shared.updateActiveVFO(frequency: newFreq)
    }

    private func setMode(_ mode: DemodulationMode) {
        sdrEngine.dspEngine.demodulationMode = mode
        MultiVFOManager.shared.updateActiveVFO(mode: mode.rawValue)
    }

    private func selectVFO(_ index: Int) {
        let manager = MultiVFOManager.shared
        manager.selectVFO(at: index)
        manager.applyVFOToSDR(sdrEngine, vfoIndex: index)
    }

    private func swapVFO() {
        MultiVFOManager.shared.swapVFOs()
    }

    private func toggleIQRecording() {
        let recorder = IQRecorder.shared
        if recorder.isRecording {
            recorder.stopRecording()
        } else {
            try? recorder.startRecording(
                frequency: sdrEngine.frequency,
                sampleRate: 2_048_000,
                format: .float32,
                gain: sdrEngine.gain
            )
        }
    }

    private func toggleAudioRecording() {
        let recorder = AudioRecorder.shared
        if recorder.isRecording {
            recorder.stopRecording()
        } else {
            try? recorder.startRecording(
                frequency: sdrEngine.frequency,
                mode: sdrEngine.dspEngine.demodulationMode.rawValue,
                format: .wav
            )
        }
    }

    private func toggleScanner() {
        let scanner = Scanner.shared
        if case .idle = scanner.state {
            scanner.startScan(sdrEngine: sdrEngine)
        } else {
            scanner.stopScan()
        }
    }

    private func adjustGain(by delta: Double) {
        let newGain = max(0, min(50, sdrEngine.gain + delta))
        sdrEngine.gain = newGain
        MultiVFOManager.shared.updateActiveVFO(gain: newGain)
    }

    private func zoomSpectrum(factor: Double) {
        // Update zoom level in DSP engine or spectrum view
        let currentBW = sdrEngine.dspEngine.filterBandwidth
        sdrEngine.dspEngine.filterBandwidth = currentBW * factor
    }

    private func resetZoom() {
        sdrEngine.dspEngine.filterBandwidth = sdrEngine.dspEngine.demodulationMode.defaultBandwidth
    }
}

extension View {
    public func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers, action: @escaping () -> Void) -> some View {
        self.background {
            Button("") { action() }
                .keyboardShortcut(key, modifiers: modifiers)
                .hidden()
        }
    }

    public func withSDRKeyboardShortcuts() -> some View {
        self.modifier(KeyboardShortcutsModifier())
    }
}

// MARK: - Keyboard Shortcuts Settings View

public struct KeyboardShortcutsSettingsView: View {
    @ObservedObject var shortcuts = KeyboardShortcutManager.shared

    public var body: some View {
        Form {
            Section("Frequency Tuning") {
                HStack {
                    Text("Small Step")
                    Spacer()
                    TextField("Hz", value: $shortcuts.smallStep, format: .number)
                        .frame(width: 100)
                        .textFieldStyle(.roundedBorder)
                    Text("Hz")
                }

                HStack {
                    Text("Medium Step")
                    Spacer()
                    TextField("Hz", value: $shortcuts.mediumStep, format: .number)
                        .frame(width: 100)
                        .textFieldStyle(.roundedBorder)
                    Text("Hz")
                }

                HStack {
                    Text("Large Step")
                    Spacer()
                    TextField("Hz", value: $shortcuts.largeStep, format: .number)
                        .frame(width: 100)
                        .textFieldStyle(.roundedBorder)
                    Text("Hz")
                }
            }

            Section("Shortcuts Reference") {
                ShortcutReferenceRow(action: "Tune Up/Down (Small)", shortcut: "↑/↓")
                ShortcutReferenceRow(action: "Tune Up/Down (Medium)", shortcut: "Shift + ↑/↓")
                ShortcutReferenceRow(action: "Tune Up/Down (Large)", shortcut: "⌘ + ↑/↓")
                ShortcutReferenceRow(action: "AM Mode", shortcut: "1")
                ShortcutReferenceRow(action: "FM Mode", shortcut: "2")
                ShortcutReferenceRow(action: "WFM Mode", shortcut: "3")
                ShortcutReferenceRow(action: "LSB Mode", shortcut: "4")
                ShortcutReferenceRow(action: "USB Mode", shortcut: "5")
                ShortcutReferenceRow(action: "CW Mode", shortcut: "6")
                ShortcutReferenceRow(action: "Select VFO-A", shortcut: "⌘ + A")
                ShortcutReferenceRow(action: "Select VFO-B", shortcut: "⌘ + B")
                ShortcutReferenceRow(action: "Swap VFOs", shortcut: "⌘ + X")
                ShortcutReferenceRow(action: "Record I/Q", shortcut: "⌘ + R")
                ShortcutReferenceRow(action: "Record Audio", shortcut: "⌘ + Shift + R")
                ShortcutReferenceRow(action: "Start/Stop Scan", shortcut: "⌘ + S")
                ShortcutReferenceRow(action: "Adjust Gain", shortcut: "←/→")
                ShortcutReferenceRow(action: "Zoom In/Out", shortcut: "⌘ + +/-")
                ShortcutReferenceRow(action: "Reset Zoom", shortcut: "⌘ + 0")
            }
        }
    }
}

struct ShortcutReferenceRow: View {
    let action: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(action)
            Spacer()
            Text(shortcut)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(4)
        }
    }
}
