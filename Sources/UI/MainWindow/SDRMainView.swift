import SwiftUI
import MetalKit

/// Main SDR application view with liquid glass interface
struct SDRMainView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var sdrEngine: SDREngine
    @ObservedObject var themeManager = ThemeManager.shared
    @ObservedObject var signalDetector = SignalDetector.shared
    @ObservedObject var frequencyHistory = FrequencyHistory.shared
    @ObservedObject var peakHold = PeakHoldManager.shared
    @ObservedObject var zoomManager = WaterfallZoomManager.shared
    @ObservedObject var audioProcessor = AudioProcessor.shared
    @ObservedObject var vfoManager = SplitVFOManager.shared
    @ObservedObject var remoteServer = RemoteControlServer.shared

    @State private var showingMemoryBank = false
    @State private var showingScanner = false
    @State private var showingRecording = false
    @State private var showingSettings = false
    @State private var showingDecoders = false
    @State private var showingStreaming = false
    @State private var showingPresets = true
    @State private var showingSignalPanel = false
    @State private var showingMiniMode = false
    @State private var showBandPlan = true
    @State private var showingDirectInput = false
    @State private var showingAudioProcessing = false
    @State private var showingRemoteControl = false
    @State private var showingSplitVFO = false
    @State private var bottomPanelHeight: CGFloat = 250

    var body: some View {
        ZStack {
            // Animated background
            if themeManager.currentTheme.animationsEnabled {
                LiquidGlassBackground(primaryColor: .blue, secondaryColor: .purple)
            } else {
                themeManager.currentTheme.colors.background.color
                    .ignoresSafeArea()
            }

            // Main content
            HSplitView {
                // Left sidebar - Glass control panel
                GlassSidebarView(
                    showingMemoryBank: $showingMemoryBank,
                    showingScanner: $showingScanner,
                    showingRecording: $showingRecording,
                    showingSettings: $showingSettings,
                    showingAudioProcessing: $showingAudioProcessing,
                    showingSplitVFO: $showingSplitVFO
                )
                .frame(minWidth: 280, maxWidth: 350)

                // Main content area
                VStack(spacing: 0) {
                    // VFO Bar with history navigation
                    HStack(spacing: 12) {
                        // History navigation
                        FrequencyHistoryNav { entry in
                            sdrEngine.tuneTo(entry.frequency)
                            if let mode = DemodulationMode(rawValue: entry.mode) {
                                sdrEngine.dspEngine.demodulationMode = mode
                            }
                        }

                        // Split VFO selector
                        if showingSplitVFO {
                            CompactSplitVFOSelector()
                        }

                        MultiVFOView()

                        Spacer()

                        // Remote control indicator
                        if remoteServer.isRunning {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 6, height: 6)
                                Text("Remote")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial.opacity(0.5))
                            .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Frequency bar
                    GlassFrequencyBar()
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    // Frequency presets bar
                    if showingPresets {
                        FrequencyPresetsView { preset in
                            sdrEngine.tuneTo(preset.frequency)
                            if let mode = DemodulationMode(rawValue: preset.mode) {
                                sdrEngine.dspEngine.demodulationMode = mode
                            }
                            sdrEngine.dspEngine.filterBandwidth = preset.bandwidth
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                    }

                    // Spectrum and Waterfall
                    GeometryReader { geometry in
                        VSplitView {
                            VStack(spacing: 0) {
                                // Band plan overlay
                                if showBandPlan {
                                    BandPlanOverlay(
                                        visibleRange: sdrEngine.visibleFrequencyRange,
                                        width: geometry.size.width - 32
                                    )
                                    .padding(.horizontal, 16)
                                }

                                VStack(spacing: 12) {
                                    // Spectrum display
                                    if appState.showSpectrum {
                                        ZStack(alignment: .topTrailing) {
                                            ZStack {
                                                InteractiveSpectrumView(dspEngine: sdrEngine.dspEngine)
                                                    .sdrContextMenu(
                                                        frequency: sdrEngine.frequency,
                                                        signalStrength: sdrEngine.dspEngine.signalStrength
                                                    )

                                                // Peak hold overlay
                                                if peakHold.enabled, let spectrum = sdrEngine.dspEngine.spectrumData {
                                                    EnhancedSpectrumOverlay(
                                                        centerFrequency: sdrEngine.frequency,
                                                        sampleRate: sdrEngine.sampleRate,
                                                        spectrumData: spectrum.magnitudes
                                                    )
                                                }
                                            }
                                            .background {
                                                GlassPanel(cornerRadius: 16, tintColor: .green) {
                                                    Color.clear
                                                }
                                            }

                                            // Spectrum controls overlay
                                            VStack(alignment: .trailing, spacing: 8) {
                                                HStack(spacing: 8) {
                                                    Toggle("Band Plan", isOn: $showBandPlan)
                                                        .toggleStyle(.checkbox)
                                                        .font(.system(size: 10))

                                                    SampleRatePicker()
                                                }
                                                .padding(8)
                                                .background(.ultraThinMaterial)
                                                .cornerRadius(8)

                                                HStack(spacing: 8) {
                                                    PeakHoldControlsView()
                                                    ZoomControlsView()
                                                }
                                            }
                                            .padding(8)
                                        }
                                        .frame(height: geometry.size.height * 0.35)
                                    }

                                    // Waterfall display
                                    if appState.showWaterfall {
                                        InteractiveWaterfallView(dspEngine: sdrEngine.dspEngine)
                                            .background {
                                                GlassPanel(cornerRadius: 16, tintColor: .blue) {
                                                    Color.clear
                                                }
                                            }
                                    }
                                }
                                .padding(16)
                            }

                            // Bottom panel (decoders, scanner, etc.)
                            if showingDecoders || showingScanner || showingRecording {
                                BottomPanelView(
                                    showingDecoders: $showingDecoders,
                                    showingScanner: $showingScanner,
                                    showingRecording: $showingRecording
                                )
                                .frame(minHeight: 200, maxHeight: 400)
                            }
                        }
                    }

                    // Bottom status bar
                    GlassStatusBar()
                }

                // Right sidebar (memory bank)
                if showingMemoryBank {
                    MemoryBankView()
                        .frame(minWidth: 250, maxWidth: 350)
                        .background(.ultraThinMaterial.opacity(0.3))
                }
            }
        }
        .toolbar(content: {
            GlassToolbar(
                showingDecoders: $showingDecoders,
                showingScanner: $showingScanner,
                showingRecording: $showingRecording,
                showingStreaming: $showingStreaming,
                showingSettings: $showingSettings
            )
        })
        .sheet(isPresented: $showingSettings) {
            SDRSettingsView()
        }
        .sheet(isPresented: $showingStreaming) {
            NetworkStreamingView()
                .frame(width: 400, height: 350)
        }
        .sheet(isPresented: $showingDirectInput) {
            DirectFrequencyInput(isPresented: $showingDirectInput) { frequency in
                sdrEngine.tuneTo(frequency)
                frequencyHistory.recordFrequency(frequency, mode: sdrEngine.dspEngine.demodulationMode.rawValue)
            }
        }
        .sheet(isPresented: $showingAudioProcessing) {
            AudioProcessingPanel()
                .frame(width: 400, height: 500)
        }
        .sheet(isPresented: $showingRemoteControl) {
            RemoteControlSettingsView()
                .frame(width: 450, height: 550)
        }
        .sheet(isPresented: $showingSplitVFO) {
            SplitVFOView()
                .frame(width: 450, height: 200)
        }
        .withSDRKeyboardShortcuts()
        .onAppear {
            // Restore session on startup
            SessionManager.shared.restoreSession(to: sdrEngine, appState: appState)
        }
        .onDisappear {
            // Save session on close
            SessionManager.shared.saveSession(from: sdrEngine, appState: appState)
        }
        .onChange(of: sdrEngine.frequency) { _, newFreq in
            // Record frequency changes to history
            frequencyHistory.recordFrequency(newFreq, mode: sdrEngine.dspEngine.demodulationMode.rawValue)
            // Sync VFO state
            vfoManager.syncFromEngine()
        }
        .onChange(of: sdrEngine.dspEngine.spectrumData?.magnitudes) { _, newMagnitudes in
            // Update peak hold
            if let magnitudes = newMagnitudes {
                peakHold.update(with: magnitudes)
            }
        }
    }
}

// MARK: - Bottom Panel

struct BottomPanelView: View {
    @Binding var showingDecoders: Bool
    @Binding var showingScanner: Bool
    @Binding var showingRecording: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                if showingDecoders {
                    BottomPanelTab(title: "Decoders", icon: "waveform.path.ecg", isActive: true) {
                        showingDecoders = false
                    }
                }
                if showingScanner {
                    BottomPanelTab(title: "Scanner", icon: "magnifyingglass", isActive: true) {
                        showingScanner = false
                    }
                }
                if showingRecording {
                    BottomPanelTab(title: "Recording", icon: "record.circle", isActive: true) {
                        showingRecording = false
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial.opacity(0.7))

            // Content
            Group {
                if showingDecoders {
                    DecoderPanelContainer()
                } else if showingScanner {
                    ScannerView()
                } else if showingRecording {
                    VStack(spacing: 12) {
                        IQRecordingView()
                        AudioRecordingView()
                    }
                    .padding()
                }
            }
            .background(.ultraThinMaterial.opacity(0.3))
        }
    }
}

struct BottomPanelTab: View {
    let title: String
    let icon: String
    let isActive: Bool
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(title)
                .font(.system(size: 11, weight: .medium))

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(isActive ? .accentColor : .secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        }
    }
}

// MARK: - Settings View

struct SDRSettingsView: View {
    var body: some View {
        TabView {
            ThemeSettingsView()
                .tabItem {
                    Label("Themes", systemImage: "paintbrush")
                }

            KeyboardShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            AudioProcessingSettingsView()
                .tabItem {
                    Label("Audio", systemImage: "waveform")
                }

            RemoteControlSettingsView()
                .tabItem {
                    Label("Remote", systemImage: "network")
                }

            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
        }
        .frame(width: 550, height: 550)
    }
}

struct AudioProcessingSettingsView: View {
    @ObservedObject var processor = AudioProcessor.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                NoiseReductionView(nr: processor.noiseReduction)
                NoiseBlankerView(nb: processor.noiseBlanker)
                ToneDecoderView(decoder: processor.toneDecoder)
                EqualizerView(eq: processor.equalizer)
            }
            .padding()
        }
    }
}

struct GeneralSettingsView: View {
    @AppStorage("fftSize") private var fftSize = 4096
    @AppStorage("waterfallSpeed") private var waterfallSpeed = 60
    @AppStorage("audioSampleRate") private var audioSampleRate = 48000

    var body: some View {
        Form {
            Section("DSP Settings") {
                Picker("FFT Size", selection: $fftSize) {
                    Text("1024").tag(1024)
                    Text("2048").tag(2048)
                    Text("4096").tag(4096)
                    Text("8192").tag(8192)
                }

                Picker("Audio Sample Rate", selection: $audioSampleRate) {
                    Text("44100 Hz").tag(44100)
                    Text("48000 Hz").tag(48000)
                    Text("96000 Hz").tag(96000)
                }
            }

            Section("Display") {
                Picker("Waterfall Speed", selection: $waterfallSpeed) {
                    Text("30 FPS").tag(30)
                    Text("60 FPS").tag(60)
                    Text("120 FPS").tag(120)
                }
            }
        }
        .padding()
    }
}

// MARK: - Glass Sidebar

struct GlassSidebarView: View {
    @EnvironmentObject var sdrEngine: SDREngine
    @EnvironmentObject var appState: AppState
    @ObservedObject var remoteServer = RemoteControlServer.shared

    @Binding var showingMemoryBank: Bool
    @Binding var showingScanner: Bool
    @Binding var showingRecording: Bool
    @Binding var showingSettings: Bool
    @Binding var showingAudioProcessing: Bool
    @Binding var showingSplitVFO: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Device Card
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Device", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.cyan)

                        if let device = sdrEngine.currentDevice {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(device.driver)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Circle()
                                    .fill(.green)
                                    .frame(width: 8, height: 8)
                            }
                        } else {
                            Text("No device connected")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }

                        GlassButton("Scan Devices", icon: "magnifyingglass", tint: .cyan) {
                            sdrEngine.refreshDevices()
                        }
                    }
                }

                // Frequency Card
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Frequency", systemImage: "waveform.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.orange)

                        // Frequency presets
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 8) {
                            FrequencyPresetChip(label: "FM", freq: 98.1, unit: "MHz", frequency: 98_100_000)
                            FrequencyPresetChip(label: "Air", freq: 118, unit: "MHz", frequency: 118_000_000)
                            FrequencyPresetChip(label: "2m", freq: 144, unit: "MHz", frequency: 144_000_000)
                            FrequencyPresetChip(label: "70cm", freq: 432, unit: "MHz", frequency: 432_000_000)
                            FrequencyPresetChip(label: "ADS-B", freq: 1090, unit: "MHz", frequency: 1_090_000_000)
                            FrequencyPresetChip(label: "L-Band", freq: 1542, unit: "MHz", frequency: 1_542_000_000)
                        }
                    }
                }

                // Gain Card
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Gain Control", systemImage: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.green)

                        GlassSegmentedPicker(
                            selection: $sdrEngine.gainMode,
                            options: [
                                (.manual, "Manual", "hand.raised"),
                                (.automatic, "AGC", "wand.and.rays")
                            ],
                            tint: .green
                        )

                        if sdrEngine.gainMode == .manual {
                            GlassSlider(
                                value: $sdrEngine.gain,
                                range: 0...50,
                                label: "RF Gain",
                                icon: "dial.low",
                                unit: " dB",
                                tint: .green
                            )
                        }
                    }
                }

                // Demodulation Card
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Demodulation", systemImage: "waveform.path.ecg")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.purple)

                        // Mode buttons
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 6) {
                            ForEach(DemodulationMode.allCases, id: \.self) { mode in
                                GlassButton(
                                    mode.rawValue,
                                    isActive: sdrEngine.dspEngine.demodulationMode == mode,
                                    tint: .purple
                                ) {
                                    sdrEngine.dspEngine.demodulationMode = mode
                                }
                            }
                        }

                        GlassSlider(
                            value: $sdrEngine.dspEngine.filterBandwidth,
                            range: 500...200000,
                            label: "Filter Bandwidth",
                            icon: "waveform.path",
                            unit: " Hz",
                            tint: .purple
                        )
                    }
                }

                // Audio Card
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Audio", systemImage: "speaker.wave.3")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.pink)

                            Spacer()

                            // Mute button
                            Button {
                                sdrEngine.audioEngine.toggleMute()
                            } label: {
                                Image(systemName: sdrEngine.audioEngine.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(sdrEngine.audioEngine.isMuted ? .red : .pink)
                            }
                            .buttonStyle(.plain)
                            .help(sdrEngine.audioEngine.isMuted ? "Unmute" : "Mute")
                        }

                        // Volume slider
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "speaker.wave.1")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 12))
                                Text("Volume")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(sdrEngine.audioEngine.volume * 100))%")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(sdrEngine.audioEngine.isMuted ? .secondary : .primary)
                            }
                            Slider(value: $sdrEngine.audioEngine.volume, in: 0...1)
                                .tint(sdrEngine.audioEngine.isMuted ? .gray : .pink)
                                .disabled(sdrEngine.audioEngine.isMuted)
                        }
                        .padding(12)
                        .background {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.ultraThinMaterial.opacity(0.5))
                                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                        }

                        GlassToggle(isOn: $sdrEngine.dspEngine.squelchEnabled, label: "Squelch", icon: "speaker.slash")

                        if sdrEngine.dspEngine.squelchEnabled {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "dial.medium")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 12))
                                    Text("Squelch Level")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(Int(sdrEngine.dspEngine.squelchLevel)) dB")
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                }
                                Slider(value: Binding(
                                    get: { Double(sdrEngine.dspEngine.squelchLevel) },
                                    set: { sdrEngine.dspEngine.squelchLevel = Float($0) }
                                ), in: -120...0)
                                .tint(.pink)
                            }
                            .padding(12)
                            .background {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.ultraThinMaterial.opacity(0.5))
                                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                            }
                        }

                        GlassToggle(isOn: $sdrEngine.dspEngine.agcEnabled, label: "Audio AGC", icon: "wand.and.rays")

                        // Audio level meter
                        GlassAudioMeter(level: sdrEngine.audioEngine.isMuted ? 0 : sdrEngine.dspEngine.audioLevel)
                    }
                }

                // Display Settings Card
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Display", systemImage: "display")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.cyan)

                        GlassToggle(isOn: $appState.showSpectrum, label: "Spectrum", icon: "waveform")
                        GlassToggle(isOn: $appState.showWaterfall, label: "Waterfall", icon: "water.waves")
                    }
                }

                // Signal Analysis Card
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Signal Analysis", systemImage: "waveform.path.ecg.rectangle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.mint)

                        SignalHistoryView()

                        Divider()

                        DetectedSignalsView { signal in
                            sdrEngine.tuneTo(signal.frequency)
                        }
                    }
                }

                // Features Card
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Features", systemImage: "star")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.yellow)

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 8) {
                            FeatureButton(title: "Memory", icon: "bookmark.fill", color: .orange, isActive: showingMemoryBank) {
                                showingMemoryBank.toggle()
                            }
                            FeatureButton(title: "Scanner", icon: "magnifyingglass", color: .green, isActive: showingScanner) {
                                showingScanner.toggle()
                            }
                            FeatureButton(title: "Record", icon: "record.circle", color: .red, isActive: showingRecording) {
                                showingRecording.toggle()
                            }
                            FeatureButton(title: "Settings", icon: "gear", color: .gray, isActive: showingSettings) {
                                showingSettings.toggle()
                            }
                        }
                    }
                }

                // Advanced Features Card
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Advanced", systemImage: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.mint)

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 8) {
                            FeatureButton(title: "Audio DSP", icon: "waveform", color: .purple, isActive: showingAudioProcessing) {
                                showingAudioProcessing.toggle()
                            }
                            FeatureButton(title: "Split VFO", icon: "arrow.left.arrow.right", color: .cyan, isActive: showingSplitVFO) {
                                showingSplitVFO.toggle()
                            }
                            FeatureButton(title: "Remote", icon: "network", color: .blue, isActive: remoteServer.isRunning) {
                                if remoteServer.isRunning {
                                    remoteServer.stop()
                                } else {
                                    try? remoteServer.start()
                                }
                            }
                            FeatureButton(title: "Markers", icon: "mappin", color: .yellow, isActive: MarkerManager.shared.showMarkers) {
                                MarkerManager.shared.showMarkers.toggle()
                            }
                        }
                    }
                }

                Spacer(minLength: 20)
            }
            .padding(16)
        }
        .background(.ultraThinMaterial.opacity(0.3))
    }
}

struct FeatureButton: View {
    let title: String
    let icon: String
    let color: Color
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isActive ? .white : color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? color : Color.clear)

                if !isActive {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                }

                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(color.opacity(0.3), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

struct FrequencyPresetChip: View {
    @EnvironmentObject var sdrEngine: SDREngine

    let label: String
    let freq: Double
    let unit: String
    let frequency: Double

    var isActive: Bool {
        abs(sdrEngine.frequency - frequency) < 100000
    }

    var body: some View {
        Button {
            sdrEngine.tuneTo(frequency)
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                Text("\(Int(freq))")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Color.orange : Color.clear)

                if !isActive {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                }

                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
            }
            .foregroundColor(isActive ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct GlassAudioMeter: View {
    let level: Float

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<20, id: \.self) { i in
                let threshold = Float(i) / 20.0
                let isActive = level > threshold
                let color: Color = {
                    if i < 12 { return .green }
                    if i < 16 { return .yellow }
                    return .red
                }()

                RoundedRectangle(cornerRadius: 1)
                    .fill(isActive ? color : Color.gray.opacity(0.2))
                    .frame(height: 8)
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(.black.opacity(0.3))
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        }
    }
}

// MARK: - Glass Frequency Bar

struct GlassFrequencyBar: View {
    @EnvironmentObject var sdrEngine: SDREngine
    @ObservedObject var bookmarkManager = QuickBookmarkManager.shared
    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Main frequency bar
            GlassPanel(cornerRadius: 20, tintColor: .cyan) {
                HStack(spacing: 20) {
                    // Tune down buttons
                    HStack(spacing: 4) {
                        TuneButton(label: "-100k", offset: -100000, tint: .red)
                        TuneButton(label: "-10k", offset: -10000, tint: .orange)
                        TuneButton(label: "-1k", offset: -1000, tint: .yellow)
                    }

                    Spacer()

                    // Interactive frequency display with digit scroll
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

                    Spacer()

                    // Tune up buttons
                    HStack(spacing: 4) {
                        TuneButton(label: "+1k", offset: 1000, tint: .yellow)
                        TuneButton(label: "+10k", offset: 10000, tint: .orange)
                        TuneButton(label: "+100k", offset: 100000, tint: .red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

            // Quick bookmark bar
            QuickBookmarkBar(
                manager: bookmarkManager,
                onSelect: { bookmark in
                    sdrEngine.tuneTo(bookmark.frequency)
                    if let mode = DemodulationMode(rawValue: bookmark.mode) {
                        sdrEngine.dspEngine.demodulationMode = mode
                    }
                },
                tint: .cyan
            )
            .cornerRadius(12)
        }
        .sheet(isPresented: $isEditing) {
            FrequencyEditSheet(frequency: $editText) {
                if let freq = Double(editText) {
                    sdrEngine.tuneTo(freq)
                }
                isEditing = false
            }
        }
    }
}

struct TuneButton: View {
    @EnvironmentObject var sdrEngine: SDREngine

    let label: String
    let offset: Double
    let tint: Color

    @State private var isPressed = false

    var body: some View {
        Button {
            sdrEngine.tuneBy(offset)
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(.black.opacity(0.3))
                        .strokeBorder(tint.opacity(0.5), lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.95 : 1.0)
    }
}

struct FrequencyEditSheet: View {
    @Binding var frequency: String
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Enter Frequency")
                .font(.headline)

            TextField("Frequency (Hz)", text: $frequency)
                .textFieldStyle(.roundedBorder)
                .font(.system(.title2, design: .monospaced))
                .frame(width: 300)

            HStack {
                Button("Cancel") {
                    onSubmit()
                }
                .buttonStyle(.bordered)

                Button("Tune") {
                    onSubmit()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
    }
}

// MARK: - Glass Spectrum View

struct GlassSpectrumView: View {
    @EnvironmentObject var sdrEngine: SDREngine

    var body: some View {
        GlassPanel(cornerRadius: 16, tintColor: .green) {
            GeometryReader { geometry in
                ZStack {
                    // Grid
                    SpectrumGridOverlay(size: geometry.size)

                    // Spectrum line with glow
                    if let spectrum = sdrEngine.dspEngine.spectrumData, !spectrum.isEmpty {
                        // Glow layer
                        SpectrumPath(magnitudes: spectrum.magnitudes, size: geometry.size)
                            .stroke(
                                LinearGradient(
                                    colors: [.cyan.opacity(0.8), .green.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                            )
                            .blur(radius: 4)

                        // Main line
                        SpectrumPath(magnitudes: spectrum.magnitudes, size: geometry.size)
                            .stroke(
                                LinearGradient(
                                    colors: [.cyan, .green],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                            )

                        // Fill under curve
                        SpectrumFillPath(magnitudes: spectrum.magnitudes, size: geometry.size)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .cyan.opacity(0.3),
                                        .green.opacity(0.1),
                                        .clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }

                    // Center marker
                    Rectangle()
                        .fill(.red.opacity(0.6))
                        .frame(width: 1)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                    // dB labels
                    VStack {
                        HStack {
                            Text("0 dB")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.gray)
                            Spacer()
                        }
                        Spacer()
                        HStack {
                            Text("-120 dB")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.gray)
                            Spacer()
                        }
                    }
                    .padding(8)
                }
            }
            .padding(2)
        }
    }
}

struct SpectrumGridOverlay: View {
    let size: CGSize

    var body: some View {
        Canvas { context, canvasSize in
            // Horizontal lines
            for i in 0...6 {
                let y = canvasSize.height * CGFloat(i) / 6
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: canvasSize.width, y: y))
                context.stroke(path, with: .color(.white.opacity(0.1)), lineWidth: 0.5)
            }

            // Vertical lines
            for i in 0...10 {
                let x = canvasSize.width * CGFloat(i) / 10
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                context.stroke(path, with: .color(.white.opacity(0.1)), lineWidth: 0.5)
            }
        }
    }
}

struct SpectrumPath: Shape {
    let magnitudes: [Float]
    let size: CGSize

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard magnitudes.count > 1 else { return path }

        let stepX = size.width / CGFloat(magnitudes.count - 1)
        let minDb: Float = -120
        let maxDb: Float = 0
        let range = maxDb - minDb

        let firstNormalized = (magnitudes[0] - minDb) / range
        let firstY = size.height * (1 - CGFloat(max(0, min(1, firstNormalized))))
        path.move(to: CGPoint(x: 0, y: firstY))

        for (index, magnitude) in magnitudes.enumerated() {
            let x = CGFloat(index) * stepX
            let normalized = (magnitude - minDb) / range
            let y = size.height * (1 - CGFloat(max(0, min(1, normalized))))
            path.addLine(to: CGPoint(x: x, y: y))
        }

        return path
    }
}

struct SpectrumFillPath: Shape {
    let magnitudes: [Float]
    let size: CGSize

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard magnitudes.count > 1 else { return path }

        let stepX = size.width / CGFloat(magnitudes.count - 1)
        let minDb: Float = -120
        let maxDb: Float = 0
        let range = maxDb - minDb

        // Start at bottom left
        path.move(to: CGPoint(x: 0, y: size.height))

        // Draw up to first point
        let firstNormalized = (magnitudes[0] - minDb) / range
        let firstY = size.height * (1 - CGFloat(max(0, min(1, firstNormalized))))
        path.addLine(to: CGPoint(x: 0, y: firstY))

        // Draw the spectrum line
        for (index, magnitude) in magnitudes.enumerated() {
            let x = CGFloat(index) * stepX
            let normalized = (magnitude - minDb) / range
            let y = size.height * (1 - CGFloat(max(0, min(1, normalized))))
            path.addLine(to: CGPoint(x: x, y: y))
        }

        // Close back to bottom
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()

        return path
    }
}

// MARK: - Glass Waterfall View

struct GlassWaterfallView: View {
    @EnvironmentObject var sdrEngine: SDREngine
    @State private var waterfallLines: [[Float]] = []
    private let maxLines = 400

    var body: some View {
        GlassPanel(cornerRadius: 16, tintColor: .blue) {
            GeometryReader { geometry in
                ZStack {
                    // Waterfall canvas
                    Canvas { context, size in
                        let lineHeight = max(1, size.height / CGFloat(maxLines))

                        for (lineIndex, magnitudes) in waterfallLines.enumerated() {
                            guard !magnitudes.isEmpty else { continue }

                            let y = CGFloat(lineIndex) * lineHeight
                            let pixelWidth = size.width / CGFloat(magnitudes.count)

                            for (i, magnitude) in magnitudes.enumerated() {
                                let x = CGFloat(i) * pixelWidth
                                let color = waterfallColor(for: magnitude)
                                context.fill(
                                    Path(CGRect(x: x, y: y, width: pixelWidth + 1, height: lineHeight + 1)),
                                    with: .color(color)
                                )
                            }
                        }
                    }

                    // Center frequency marker
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.red.opacity(0), .red.opacity(0.5), .red.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 2)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                    // Time scale on right edge
                    VStack {
                        Text("now")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                    }
                    .padding(4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(2)
        }
        .onChange(of: sdrEngine.dspEngine.waterfallLine?.id) { _, _ in
            if let line = sdrEngine.dspEngine.waterfallLine {
                waterfallLines.insert(line.magnitudes, at: 0)
                if waterfallLines.count > maxLines {
                    waterfallLines.removeLast()
                }
            }
        }
    }

    private func waterfallColor(for magnitude: Float) -> Color {
        let normalized = (magnitude + 120) / 120  // -120 to 0 dB -> 0 to 1
        let m = Double(max(0, min(1, normalized)))

        // Enhanced color palette: black -> deep blue -> cyan -> green -> yellow -> red -> white
        if m < 0.15 {
            let t = m / 0.15
            return Color(red: 0, green: t * 0.1, blue: 0.05 + t * 0.35)
        } else if m < 0.3 {
            let t = (m - 0.15) / 0.15
            return Color(red: 0, green: 0.1 + t * 0.7, blue: 0.4 + t * 0.6)
        } else if m < 0.45 {
            let t = (m - 0.3) / 0.15
            return Color(red: 0, green: 0.8 + t * 0.2, blue: 1.0 - t * 0.7)
        } else if m < 0.6 {
            let t = (m - 0.45) / 0.15
            return Color(red: t, green: 1.0, blue: 0.3 - t * 0.3)
        } else if m < 0.8 {
            let t = (m - 0.6) / 0.2
            return Color(red: 1.0, green: 1.0 - t * 0.8, blue: 0)
        } else {
            let t = (m - 0.8) / 0.2
            return Color(red: 1.0, green: 0.2 + t * 0.8, blue: t)
        }
    }
}

// MARK: - Glass Status Bar

struct GlassStatusBar: View {
    @EnvironmentObject var sdrEngine: SDREngine

    var body: some View {
        HStack(spacing: 16) {
            // Connection status
            HStack(spacing: 6) {
                Circle()
                    .fill(sdrEngine.isRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: sdrEngine.isRunning ? .green : .red, radius: 4)

                Text(sdrEngine.isRunning ? "Running" : "Stopped")
                    .font(.system(size: 11, weight: .medium))
            }

            Divider()
                .frame(height: 16)

            // Signal strength
            HStack(spacing: 4) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 10))
                Text("\(Int(sdrEngine.dspEngine.signalStrength)) dBm")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }

            Divider()
                .frame(height: 16)

            // Mode
            Text(sdrEngine.dspEngine.demodulationMode.rawValue)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                    Capsule()
                        .fill(.purple.opacity(0.3))
                }

            Spacer()

            // FFT size indicator
            Text("FFT: 4096")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)

            // Error message
            if let error = sdrEngine.lastError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial.opacity(0.5))
    }
}

// MARK: - Glass Toolbar

struct GlassToolbar: ToolbarContent {
    @EnvironmentObject var sdrEngine: SDREngine
    @ObservedObject var iqRecorder = IQRecorder.shared
    @ObservedObject var scanner = Scanner.shared

    @Binding var showingDecoders: Bool
    @Binding var showingScanner: Bool
    @Binding var showingRecording: Bool
    @Binding var showingStreaming: Bool
    @Binding var showingSettings: Bool

    private var scannerIsIdle: Bool {
        if case .idle = scanner.state { return true }
        return false
    }

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // Start/Stop button
            Button {
                if sdrEngine.isRunning {
                    sdrEngine.stop()
                } else {
                    Task {
                        try? await sdrEngine.start()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: sdrEngine.isRunning ? "stop.fill" : "play.fill")
                    Text(sdrEngine.isRunning ? "Stop" : "Start")
                }
                .foregroundColor(sdrEngine.isRunning ? .red : .green)
            }

            Divider()

            // Record button
            Button {
                if iqRecorder.isRecording {
                    iqRecorder.stopRecording()
                } else {
                    try? iqRecorder.startRecording(
                        frequency: sdrEngine.frequency,
                        sampleRate: 2_048_000,  // Default sample rate
                        format: .float32,
                        gain: sdrEngine.gain
                    )
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: iqRecorder.isRecording ? "record.circle.fill" : "record.circle")
                    Text(iqRecorder.isRecording ? "Stop Rec" : "Record")
                }
                .foregroundStyle(iqRecorder.isRecording ? .red : .primary)
            }

            // Scanner button
            Button {
                if scannerIsIdle {
                    scanner.startScan(sdrEngine: sdrEngine)
                } else {
                    scanner.stopScan()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: scannerIsIdle ? "magnifyingglass" : "magnifyingglass.circle.fill")
                    Text(scannerIsIdle ? "Scan" : "Scanning")
                }
                .foregroundColor(scannerIsIdle ? .primary : .green)
            }

            Divider()

            // Quick mode picker
            Menu {
                ForEach(DemodulationMode.allCases, id: \.self) { mode in
                    Button(mode.rawValue) {
                        sdrEngine.dspEngine.demodulationMode = mode
                        MultiVFOManager.shared.updateActiveVFO(mode: mode.rawValue)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "waveform")
                    Text(sdrEngine.dspEngine.demodulationMode.rawValue)
                }
            }

            Divider()

            // Panel toggles
            Button {
                showingDecoders.toggle()
            } label: {
                Image(systemName: "waveform.path.ecg")
            }
            .help("Decoders")

            Button {
                showingStreaming.toggle()
            } label: {
                Image(systemName: "network")
            }
            .help("Network Streaming")

            Button {
                showingSettings.toggle()
            } label: {
                Image(systemName: "gear")
            }
            .help("Settings")
        }
    }
}

// MARK: - Spectrum Grid (Legacy compatibility)

struct SpectrumGrid: Shape {
    let size: CGSize

    func path(in rect: CGRect) -> Path {
        var path = Path()

        for i in 0...10 {
            let y = size.height * CGFloat(i) / 10
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }

        for i in 0...10 {
            let x = size.width * CGFloat(i) / 10
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }

        return path
    }
}
