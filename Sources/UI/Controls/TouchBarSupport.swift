import SwiftUI
import AppKit

// MARK: - Touch Bar Items

public struct SDRTouchBar: View {
    @EnvironmentObject var sdrEngine: SDREngine
    @ObservedObject var vfoManager = MultiVFOManager.shared
    @ObservedObject var iqRecorder = IQRecorder.shared
    @ObservedObject var audioRecorder = AudioRecorder.shared
    @ObservedObject var scanner = Scanner.shared

    public var body: some View {
        HStack(spacing: 16) {
            // VFO Selector
            ForEach(Array(vfoManager.vfos.prefix(2).enumerated()), id: \.element.id) { index, vfo in
                Button {
                    vfoManager.selectVFO(at: index)
                    vfoManager.applyVFOToSDR(sdrEngine, vfoIndex: index)
                } label: {
                    VStack(spacing: 2) {
                        Text(vfo.name)
                            .font(.system(size: 10))
                        Text(formatFrequencyShort(vfo.frequency))
                            .font(.system(size: 12, design: .monospaced))
                    }
                    .foregroundColor(index == vfoManager.activeVFOIndex ? Color(vfo.color) : .secondary)
                }
            }

            Divider()

            // Mode buttons
            ForEach([DemodulationMode.am, .fm, .usb, .lsb], id: \.self) { mode in
                Button {
                    sdrEngine.dspEngine.demodulationMode = mode
                    vfoManager.updateActiveVFO(mode: mode.rawValue)
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 12, weight: sdrEngine.dspEngine.demodulationMode == mode ? .bold : .regular))
                        .foregroundColor(sdrEngine.dspEngine.demodulationMode == mode ? .cyan : .secondary)
                }
            }

            Divider()

            // Recording buttons
            Button {
                if iqRecorder.isRecording {
                    iqRecorder.stopRecording()
                } else {
                    try? iqRecorder.startRecording(
                        frequency: sdrEngine.frequency,
                        sampleRate: 2_048_000,
                        format: .float32,
                        gain: sdrEngine.gain
                    )
                }
            } label: {
                Image(systemName: iqRecorder.isRecording ? "stop.circle.fill" : "record.circle")
                    .font(.system(size: 20))
                    .foregroundColor(iqRecorder.isRecording ? .red : .white)
            }

            // Scanner
            Button {
                if case .idle = scanner.state {
                    scanner.startScan(sdrEngine: sdrEngine)
                } else {
                    scanner.stopScan()
                }
            } label: {
                let isIdle: Bool = { if case .idle = scanner.state { return true }; return false }()
                Image(systemName: isIdle ? "magnifyingglass" : "stop.fill")
                    .font(.system(size: 18))
            }

            Divider()

            // Tuning slider
            Slider(value: Binding(
                get: { sdrEngine.frequency / 1_000_000 },
                set: { sdrEngine.tuneTo($0 * 1_000_000) }
            ), in: 24...1800)
            .frame(width: 200)
        }
        .padding(.horizontal, 8)
    }

    private func formatFrequencyShort(_ freq: Double) -> String {
        if freq >= 1_000_000 {
            return String(format: "%.3f", freq / 1_000_000)
        }
        return String(format: "%.0f", freq / 1000)
    }
}

// MARK: - Touch Bar Provider

#if os(macOS)
public class TouchBarProvider: NSObject, NSTouchBarDelegate {
    private weak var sdrEngine: SDREngine?

    public init(sdrEngine: SDREngine) {
        self.sdrEngine = sdrEngine
        super.init()
    }

    public func makeTouchBar() -> NSTouchBar {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [
            .vfoSelector,
            .flexibleSpace,
            .modeSelector,
            .flexibleSpace,
            .recordButton,
            .scanButton,
            .flexibleSpace,
            .frequencySlider
        ]
        return touchBar
    }

    public func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case .vfoSelector:
            return makeVFOSelector()
        case .modeSelector:
            return makeModeSelector()
        case .recordButton:
            return makeRecordButton()
        case .scanButton:
            return makeScanButton()
        case .frequencySlider:
            return makeFrequencySlider()
        default:
            return nil
        }
    }

    private func makeVFOSelector() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: .vfoSelector)
        let segmentedControl = NSSegmentedControl(labels: ["A", "B"], trackingMode: .selectOne, target: self, action: #selector(vfoChanged(_:)))
        segmentedControl.selectedSegment = 0
        item.view = segmentedControl
        return item
    }

    private func makeModeSelector() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: .modeSelector)
        let segmentedControl = NSSegmentedControl(labels: ["AM", "FM", "USB", "LSB"], trackingMode: .selectOne, target: self, action: #selector(modeChanged(_:)))
        segmentedControl.selectedSegment = 1
        item.view = segmentedControl
        return item
    }

    private func makeRecordButton() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: .recordButton)
        let button = NSButton(image: NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Record")!, target: self, action: #selector(recordPressed))
        button.bezelColor = .systemRed
        item.view = button
        return item
    }

    private func makeScanButton() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: .scanButton)
        let button = NSButton(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Scan")!, target: self, action: #selector(scanPressed))
        item.view = button
        return item
    }

    private func makeFrequencySlider() -> NSTouchBarItem {
        let item = NSSliderTouchBarItem(identifier: .frequencySlider)
        item.slider.minValue = 24
        item.slider.maxValue = 1800
        item.slider.doubleValue = 100.0  // Default 100 MHz
        item.target = self
        item.action = #selector(frequencyChanged(_:))
        item.label = "MHz"
        return item
    }

    @objc private func vfoChanged(_ sender: NSSegmentedControl) {
        Task { @MainActor in
            let manager = MultiVFOManager.shared
            manager.selectVFO(at: sender.selectedSegment)
            if let engine = sdrEngine {
                manager.applyVFOToSDR(engine, vfoIndex: sender.selectedSegment)
            }
        }
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        let modes: [DemodulationMode] = [.am, .fm, .usb, .lsb]
        guard sender.selectedSegment < modes.count else { return }

        Task { @MainActor in
            sdrEngine?.dspEngine.demodulationMode = modes[sender.selectedSegment]
        }
    }

    @objc private func recordPressed() {
        Task { @MainActor in
            let recorder = IQRecorder.shared
            if recorder.isRecording {
                recorder.stopRecording()
            } else if let engine = sdrEngine {
                try? recorder.startRecording(
                    frequency: engine.frequency,
                    sampleRate: 2_048_000,
                    format: .float32,
                    gain: engine.gain
                )
            }
        }
    }

    @objc private func scanPressed() {
        Task { @MainActor in
            let scanner = Scanner.shared
            if case .idle = scanner.state {
                if let engine = sdrEngine {
                    scanner.startScan(sdrEngine: engine)
                }
            } else {
                scanner.stopScan()
            }
        }
    }

    @objc private func frequencyChanged(_ sender: NSSliderTouchBarItem) {
        let freqMHz = sender.slider.doubleValue
        Task { @MainActor in
            sdrEngine?.tuneTo(freqMHz * 1_000_000)
        }
    }
}

// Touch Bar Item Identifiers
extension NSTouchBarItem.Identifier {
    static let vfoSelector = NSTouchBarItem.Identifier("com.sdr.vfoSelector")
    static let modeSelector = NSTouchBarItem.Identifier("com.sdr.modeSelector")
    static let recordButton = NSTouchBarItem.Identifier("com.sdr.recordButton")
    static let scanButton = NSTouchBarItem.Identifier("com.sdr.scanButton")
    static let frequencySlider = NSTouchBarItem.Identifier("com.sdr.frequencySlider")
}
#endif
