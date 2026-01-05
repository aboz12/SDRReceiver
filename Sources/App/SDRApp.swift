import SwiftUI

@main
struct SDRApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var sdrEngine = SDREngine.shared

    var body: some Scene {
        WindowGroup {
            SDRMainView()
                .environmentObject(appState)
                .environmentObject(sdrEngine)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1400, height: 900)
        .commands {
            // File Menu
            CommandGroup(replacing: .newItem) {
                Button("Start Receiving") {
                    Task {
                        try? await sdrEngine.start()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(sdrEngine.isRunning)

                Button("Stop Receiving") {
                    sdrEngine.stop()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!sdrEngine.isRunning)

                Divider()

                Button("Record I/Q") {
                    sdrEngine.toggleRecording()
                }
                .keyboardShortcut("k", modifiers: [.command])
            }

            // Frequency Menu
            CommandMenu("Frequency") {
                Button("Tune Up 1 kHz") {
                    sdrEngine.tuneBy(1000)
                }
                .keyboardShortcut(.upArrow, modifiers: [])

                Button("Tune Down 1 kHz") {
                    sdrEngine.tuneBy(-1000)
                }
                .keyboardShortcut(.downArrow, modifiers: [])

                Button("Tune Up 10 kHz") {
                    sdrEngine.tuneBy(10000)
                }
                .keyboardShortcut(.upArrow, modifiers: [.shift])

                Button("Tune Down 10 kHz") {
                    sdrEngine.tuneBy(-10000)
                }
                .keyboardShortcut(.downArrow, modifiers: [.shift])

                Divider()

                Button("Enter Frequency...") {
                    appState.showFrequencyEntry = true
                }
                .keyboardShortcut("f", modifiers: [.command])
            }

            // Mode Menu
            CommandMenu("Mode") {
                ForEach(DemodulationMode.allCases, id: \.self) { mode in
                    Button(mode.rawValue) {
                        sdrEngine.dspEngine.demodulationMode = mode
                    }
                    .keyboardShortcut(mode.shortcut, modifiers: [.command])
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(sdrEngine)
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var sdrEngine: SDREngine

    var body: some View {
        TabView {
            DeviceSettingsView()
                .tabItem {
                    Label("Device", systemImage: "antenna.radiowaves.left.and.right")
                }

            DSPSettingsView()
                .tabItem {
                    Label("DSP", systemImage: "waveform")
                }

            AudioSettingsView()
                .tabItem {
                    Label("Audio", systemImage: "speaker.wave.3")
                }
        }
        .frame(width: 500, height: 400)
    }
}

struct DeviceSettingsView: View {
    @EnvironmentObject var sdrEngine: SDREngine
    @State private var selectedDevice: String = ""
    @State private var sampleRate: Double = 2_400_000
    @State private var ppmCorrection: Int = 0

    var body: some View {
        Form {
            Section("SDR Device") {
                Picker("Device", selection: $selectedDevice) {
                    Text("Auto-detect").tag("")
                    ForEach(sdrEngine.availableDevices, id: \.self) { device in
                        Text(device).tag(device)
                    }
                }

                Picker("Sample Rate", selection: $sampleRate) {
                    Text("1.024 MHz").tag(1_024_000.0)
                    Text("2.048 MHz").tag(2_048_000.0)
                    Text("2.4 MHz").tag(2_400_000.0)
                    Text("2.8 MHz").tag(2_800_000.0)
                    Text("3.2 MHz").tag(3_200_000.0)
                }

                Stepper("PPM Correction: \(ppmCorrection)", value: $ppmCorrection, in: -100...100)
            }

            Section("RTL-SDR") {
                Toggle("Direct Sampling", isOn: .constant(false))
                Toggle("Bias Tee", isOn: .constant(false))
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct DSPSettingsView: View {
    @AppStorage("fftSize") private var fftSize = 4096
    @AppStorage("averagingCount") private var averagingCount = 4
    @AppStorage("windowFunction") private var windowFunction = "Blackman-Harris"

    var body: some View {
        Form {
            Section("FFT") {
                Picker("FFT Size", selection: $fftSize) {
                    Text("1024").tag(1024)
                    Text("2048").tag(2048)
                    Text("4096").tag(4096)
                    Text("8192").tag(8192)
                    Text("16384").tag(16384)
                }

                Picker("Window Function", selection: $windowFunction) {
                    Text("Rectangular").tag("Rectangular")
                    Text("Hamming").tag("Hamming")
                    Text("Hanning").tag("Hanning")
                    Text("Blackman-Harris").tag("Blackman-Harris")
                }

                Stepper("Averaging: \(averagingCount)", value: $averagingCount, in: 1...16)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AudioSettingsView: View {
    @AppStorage("audioDevice") private var audioDevice = "Default"
    @AppStorage("audioSampleRate") private var audioSampleRate = 48000

    var body: some View {
        Form {
            Section("Audio Output") {
                Picker("Output Device", selection: $audioDevice) {
                    Text("System Default").tag("Default")
                }

                Picker("Sample Rate", selection: $audioSampleRate) {
                    Text("44.1 kHz").tag(44100)
                    Text("48 kHz").tag(48000)
                }
            }

            Section("Squelch") {
                Toggle("Enable Squelch", isOn: .constant(true))
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
