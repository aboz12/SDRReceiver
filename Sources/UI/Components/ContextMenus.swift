import SwiftUI
import AppKit

// MARK: - Spectrum Context Menu

public struct SpectrumContextMenu: View {
    let frequency: Double
    let signalStrength: Float
    let onTune: (Double) -> Void
    let onAddBookmark: (Double) -> Void
    let onAddMarker: (Double) -> Void
    let onCopyFrequency: (Double) -> Void

    public init(
        frequency: Double,
        signalStrength: Float = -120,
        onTune: @escaping (Double) -> Void,
        onAddBookmark: @escaping (Double) -> Void,
        onAddMarker: @escaping (Double) -> Void,
        onCopyFrequency: @escaping (Double) -> Void
    ) {
        self.frequency = frequency
        self.signalStrength = signalStrength
        self.onTune = onTune
        self.onAddBookmark = onAddBookmark
        self.onAddMarker = onAddMarker
        self.onCopyFrequency = onCopyFrequency
    }

    public var body: some View {
        Group {
            Text(FrequencyFormatter.format(frequency))
                .font(.headline)

            if signalStrength > -120 {
                Text(String(format: "%.1f dBm", signalStrength))
                    .foregroundColor(.secondary)
            }

            Divider()

            Button {
                onTune(frequency)
            } label: {
                Label("Tune to Frequency", systemImage: "antenna.radiowaves.left.and.right")
            }

            Button {
                onAddBookmark(frequency)
            } label: {
                Label("Add Bookmark", systemImage: "bookmark.fill")
            }

            Button {
                onAddMarker(frequency)
            } label: {
                Label("Add Marker", systemImage: "mappin")
            }

            Button {
                onCopyFrequency(frequency)
            } label: {
                Label("Copy Frequency", systemImage: "doc.on.doc")
            }

            Divider()

            Menu("Tune to Mode") {
                ForEach(DemodulationMode.allCases, id: \.self) { mode in
                    Button(mode.rawValue) {
                        SDREngine.shared.frequency = frequency
                        SDREngine.shared.dspEngine.demodulationMode = mode
                    }
                }
            }
        }
    }
}

// MARK: - Waterfall Context Menu

public struct WaterfallContextMenu: View {
    let frequency: Double
    let timestamp: Date?
    let onTune: (Double) -> Void
    let onAddMarker: (Double) -> Void
    let onSetCenter: (Double) -> Void

    public init(
        frequency: Double,
        timestamp: Date? = nil,
        onTune: @escaping (Double) -> Void,
        onAddMarker: @escaping (Double) -> Void,
        onSetCenter: @escaping (Double) -> Void
    ) {
        self.frequency = frequency
        self.timestamp = timestamp
        self.onTune = onTune
        self.onAddMarker = onAddMarker
        self.onSetCenter = onSetCenter
    }

    public var body: some View {
        Group {
            Text(FrequencyFormatter.format(frequency))
                .font(.headline)

            if let ts = timestamp {
                Text(ts, style: .time)
                    .foregroundColor(.secondary)
            }

            Divider()

            Button {
                onTune(frequency)
            } label: {
                Label("Tune Here", systemImage: "antenna.radiowaves.left.and.right")
            }

            Button {
                onSetCenter(frequency)
            } label: {
                Label("Center on Frequency", systemImage: "arrow.left.and.right")
            }

            Button {
                onAddMarker(frequency)
            } label: {
                Label("Add Marker", systemImage: "mappin")
            }

            Divider()

            Button {
                WaterfallZoomManager.shared.zoomIn()
            } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }

            Button {
                WaterfallZoomManager.shared.zoomOut()
            } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }

            Button {
                WaterfallZoomManager.shared.reset()
            } label: {
                Label("Reset Zoom", systemImage: "arrow.up.left.and.arrow.down.right")
            }

            Divider()

            Button {
                if let url = ExportManager.shared.captureSpectrumData(
                    SDREngine.shared.dspEngine.spectrumData?.magnitudes ?? []
                ) {
                    NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                }
            } label: {
                Label("Export Spectrum Data", systemImage: "square.and.arrow.up")
            }
        }
    }
}

// MARK: - Frequency Display Context Menu

public struct FrequencyDisplayContextMenu: View {
    let frequency: Double
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onDirectInput: () -> Void
    let onAddToHistory: () -> Void

    public init(
        frequency: Double,
        onCopy: @escaping () -> Void,
        onPaste: @escaping () -> Void,
        onDirectInput: @escaping () -> Void,
        onAddToHistory: @escaping () -> Void
    ) {
        self.frequency = frequency
        self.onCopy = onCopy
        self.onPaste = onPaste
        self.onDirectInput = onDirectInput
        self.onAddToHistory = onAddToHistory
    }

    public var body: some View {
        Group {
            Button {
                onCopy()
            } label: {
                Label("Copy Frequency", systemImage: "doc.on.doc")
            }

            Button {
                onPaste()
            } label: {
                Label("Paste Frequency", systemImage: "doc.on.clipboard")
            }

            Divider()

            Button {
                onDirectInput()
            } label: {
                Label("Enter Frequency...", systemImage: "keyboard")
            }

            Divider()

            Button {
                onAddToHistory()
            } label: {
                Label("Add to Bookmarks", systemImage: "bookmark.fill")
            }

            Menu("Quick Tune") {
                Button("FM Broadcast (98.1 MHz)") {
                    SDREngine.shared.frequency = 98_100_000
                }
                Button("Air Band (118.0 MHz)") {
                    SDREngine.shared.frequency = 118_000_000
                }
                Button("2m Amateur (144.2 MHz)") {
                    SDREngine.shared.frequency = 144_200_000
                }
                Button("70cm Amateur (432.1 MHz)") {
                    SDREngine.shared.frequency = 432_100_000
                }
            }
        }
    }
}

// MARK: - Bookmark Context Menu

public struct BookmarkContextMenu: View {
    let bookmark: QuickBookmark
    let onTune: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onCopy: () -> Void

    public init(
        bookmark: QuickBookmark,
        onTune: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onCopy: @escaping () -> Void
    ) {
        self.bookmark = bookmark
        self.onTune = onTune
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onCopy = onCopy
    }

    public var body: some View {
        Group {
            Text(bookmark.label)
                .font(.headline)

            Text(FrequencyFormatter.format(bookmark.frequency))
                .foregroundColor(.secondary)

            Divider()

            Button {
                onTune()
            } label: {
                Label("Tune to Frequency", systemImage: "antenna.radiowaves.left.and.right")
            }

            Button {
                onEdit()
            } label: {
                Label("Edit Bookmark", systemImage: "pencil")
            }

            Button {
                onCopy()
            } label: {
                Label("Copy Frequency", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Bookmark", systemImage: "trash")
            }
        }
    }
}

// MARK: - Mode Button Context Menu

public struct ModeContextMenu: View {
    let currentMode: DemodulationMode
    let onSelectMode: (DemodulationMode) -> Void

    public init(
        currentMode: DemodulationMode,
        onSelectMode: @escaping (DemodulationMode) -> Void
    ) {
        self.currentMode = currentMode
        self.onSelectMode = onSelectMode
    }

    public var body: some View {
        Group {
            Text("Demodulation Mode")
                .font(.headline)

            Divider()

            Section("Analog") {
                modeButton(.am, description: "Amplitude Modulation")
                modeButton(.fm, description: "Narrow FM (12.5 kHz)")
                modeButton(.wfm, description: "Wide FM (Broadcast)")
            }

            Section("SSB") {
                modeButton(.lsb, description: "Lower Sideband")
                modeButton(.usb, description: "Upper Sideband")
            }

            Section("Other") {
                modeButton(.cw, description: "Continuous Wave (Morse)")
                modeButton(.raw, description: "Raw I/Q (No demodulation)")
            }
        }
    }

    @ViewBuilder
    private func modeButton(_ mode: DemodulationMode, description: String) -> some View {
        Button {
            onSelectMode(mode)
        } label: {
            HStack {
                if mode == currentMode {
                    Image(systemName: "checkmark")
                }
                Text(mode.rawValue)
                Spacer()
                Text(description)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Gain Context Menu

public struct GainContextMenu: View {
    let currentGain: Double
    let gainMode: GainMode
    let onSetGain: (Double) -> Void
    let onSetGainMode: (GainMode) -> Void

    public init(
        currentGain: Double,
        gainMode: GainMode,
        onSetGain: @escaping (Double) -> Void,
        onSetGainMode: @escaping (GainMode) -> Void
    ) {
        self.currentGain = currentGain
        self.gainMode = gainMode
        self.onSetGain = onSetGain
        self.onSetGainMode = onSetGainMode
    }

    @ViewBuilder
    public var body: some View {
        Text("Gain Control")
            .font(.headline)

        Text(String(format: "%.1f dB", currentGain))
            .foregroundColor(.secondary)

        Divider()

        Menu("Gain Mode") {
            Button {
                onSetGainMode(.automatic)
            } label: {
                HStack {
                    if gainMode == .automatic {
                        Image(systemName: "checkmark")
                    }
                    Text("Automatic")
                }
            }

            Button {
                onSetGainMode(.manual)
            } label: {
                HStack {
                    if gainMode == .manual {
                        Image(systemName: "checkmark")
                    }
                    Text("Manual")
                }
            }
        }

        Divider()

        Menu("Presets") {
            Button("Low (10 dB)") { onSetGain(10) }
            Button("Medium (25 dB)") { onSetGain(25) }
            Button("High (40 dB)") { onSetGain(40) }
            Button("Maximum (49.6 dB)") { onSetGain(49.6) }
        }
    }
}

// MARK: - Detected Signal Context Menu

public struct DetectedSignalContextMenu: View {
    let signal: SignalDetector.DetectedSignal
    let onTune: () -> Void
    let onAddBookmark: () -> Void
    let onAddMarker: () -> Void
    let onCopy: () -> Void

    public init(
        signal: SignalDetector.DetectedSignal,
        onTune: @escaping () -> Void,
        onAddBookmark: @escaping () -> Void,
        onAddMarker: @escaping () -> Void,
        onCopy: @escaping () -> Void
    ) {
        self.signal = signal
        self.onTune = onTune
        self.onAddBookmark = onAddBookmark
        self.onAddMarker = onAddMarker
        self.onCopy = onCopy
    }

    @ViewBuilder
    public var body: some View {
        Text("Detected Signal")
            .font(.headline)

        Text(FrequencyFormatter.format(signal.frequency))
        Text(String(format: "%.1f dBm", signal.strength))
            .foregroundColor(.secondary)

        Divider()

        Button {
            onTune()
        } label: {
            Label("Tune to Signal", systemImage: "antenna.radiowaves.left.and.right")
        }

        Button {
            onAddBookmark()
        } label: {
            Label("Add Bookmark", systemImage: "bookmark.fill")
        }

        Button {
            onAddMarker()
        } label: {
            Label("Add Marker", systemImage: "mappin")
        }

        Button {
            onCopy()
        } label: {
            Label("Copy Frequency", systemImage: "doc.on.doc")
        }
    }
}

// MARK: - Context Menu Modifier

@MainActor
public struct SDRContextMenuModifier: ViewModifier {
    let frequency: Double
    let signalStrength: Float
    @ObservedObject var bookmarkManager = QuickBookmarkManager.shared
    @ObservedObject var markerManager = MarkerManager.shared

    public func body(content: Content) -> some View {
        content
            .contextMenu {
                SpectrumContextMenu(
                    frequency: frequency,
                    signalStrength: signalStrength,
                    onTune: { freq in
                        SDREngine.shared.frequency = freq
                    },
                    onAddBookmark: { freq in
                        bookmarkManager.addBookmark(
                            frequency: freq,
                            mode: SDREngine.shared.dspEngine.demodulationMode.rawValue,
                            label: FrequencyFormatter.format(freq)
                        )
                    },
                    onAddMarker: { freq in
                        markerManager.addMarker(at: freq)
                    },
                    onCopyFrequency: { freq in
                        FrequencyClipboard.copy(freq)
                    }
                )
            }
    }
}

extension View {
    public func sdrContextMenu(frequency: Double, signalStrength: Float = -120) -> some View {
        modifier(SDRContextMenuModifier(frequency: frequency, signalStrength: signalStrength))
    }
}
