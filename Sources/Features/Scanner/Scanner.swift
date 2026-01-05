import Foundation
import SwiftUI
import Combine

// MARK: - Scanner Mode

public enum ScanMode: String, CaseIterable {
    case range = "Range"
    case memory = "Memory"
    case priority = "Priority"

    var icon: String {
        switch self {
        case .range: return "arrow.left.arrow.right"
        case .memory: return "list.bullet"
        case .priority: return "star.fill"
        }
    }
}

public enum ScanDirection: String {
    case up = "Up"
    case down = "Down"
}

// MARK: - Scanner Settings

public struct ScannerSettings: Codable {
    public var squelchLevel: Float = -100
    public var holdTime: TimeInterval = 2.0     // Seconds to hold on active signal
    public var resumeDelay: TimeInterval = 3.0  // Seconds after squelch closes before resuming
    public var stepSize: Double = 12_500        // Hz
    public var scanSpeed: TimeInterval = 0.1    // Seconds per step
    public var lockoutEnabled: Bool = true
}

// MARK: - Scanner Entry

public struct ScanEntry: Identifiable, Codable, Hashable {
    public var id: UUID
    public var frequency: Double
    public var mode: String
    public var isLocked: Bool
    public var hitCount: Int
    public var lastActive: Date?
    public var label: String?

    public init(
        id: UUID = UUID(),
        frequency: Double,
        mode: String = "FM",
        isLocked: Bool = false,
        label: String? = nil
    ) {
        self.id = id
        self.frequency = frequency
        self.mode = mode
        self.isLocked = isLocked
        self.hitCount = 0
        self.lastActive = nil
        self.label = label
    }

    public var formattedFrequency: String {
        FrequencyFormatter.format(frequency)
    }
}

// MARK: - Scanner State

public enum ScannerState {
    case idle
    case scanning
    case holding(frequency: Double)
    case paused
}

// MARK: - Scanner

@MainActor
public final class Scanner: ObservableObject {
    public static let shared = Scanner()

    @Published public var state: ScannerState = .idle
    @Published public var mode: ScanMode = .range
    @Published public var direction: ScanDirection = .up
    @Published public var settings = ScannerSettings()

    // Range scan
    @Published public var startFrequency: Double = 144_000_000
    @Published public var endFrequency: Double = 148_000_000

    // Memory scan
    @Published public var memoryList: [ScanEntry] = []
    @Published public var currentIndex: Int = 0

    // Priority channels
    @Published public var priorityChannels: [ScanEntry] = []
    @Published public var priorityInterval: Int = 5  // Check priority every N steps

    // Lockout list
    @Published public var lockoutList: Set<Double> = []

    // Activity log
    @Published public var activityLog: [ScanActivity] = []

    // Statistics
    @Published public var currentFrequency: Double = 0
    @Published public var signalStrength: Float = -120
    @Published public var activeFrequencies: [ScanEntry] = []

    private var scanTask: Task<Void, Never>?
    private var holdTimer: Timer?
    private var priorityCounter = 0
    private let saveKey = "ScannerData"

    private init() {
        loadData()
    }

    // MARK: - Scan Control

    public func startScan(sdrEngine: SDREngine) {
        guard case .idle = state else { return }

        state = .scanning
        currentFrequency = mode == .range ? startFrequency : (memoryList.first?.frequency ?? 0)

        scanTask = Task {
            await runScanLoop(sdrEngine: sdrEngine)
        }
    }

    public func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        holdTimer?.invalidate()
        holdTimer = nil
        state = .idle
    }

    public func pauseScan() {
        guard case .scanning = state else { return }
        state = .paused
    }

    public func resumeScan() {
        guard case .paused = state else { return }
        state = .scanning
    }

    public func skipCurrent(sdrEngine: SDREngine) {
        holdTimer?.invalidate()
        holdTimer = nil
        if case .holding = state {
            state = .scanning
        }
        advanceToNext(sdrEngine: sdrEngine)
    }

    public func lockoutCurrent() {
        lockoutList.insert(currentFrequency)
        saveData()
    }

    public func clearLockout(_ frequency: Double) {
        lockoutList.remove(frequency)
        saveData()
    }

    public func clearAllLockouts() {
        lockoutList.removeAll()
        saveData()
    }

    // MARK: - Scan Loop

    private func runScanLoop(sdrEngine: SDREngine) async {
        while !Task.isCancelled {
            guard case .scanning = state else {
                try? await Task.sleep(nanoseconds: 100_000_000)
                continue
            }

            // Check priority channels periodically
            priorityCounter += 1
            if !priorityChannels.isEmpty && priorityCounter >= priorityInterval {
                priorityCounter = 0
                if await checkPriorityChannels(sdrEngine: sdrEngine) {
                    continue
                }
            }

            // Tune to current frequency
            await MainActor.run {
                sdrEngine.tuneTo(currentFrequency)
            }

            // Wait for signal to settle
            try? await Task.sleep(nanoseconds: UInt64(settings.scanSpeed * 1_000_000_000))

            // Check squelch
            let strength = await MainActor.run { sdrEngine.dspEngine.signalStrength }
            await MainActor.run { signalStrength = strength }

            if strength > settings.squelchLevel && !lockoutList.contains(currentFrequency) {
                // Signal detected!
                await handleSignalDetected(sdrEngine: sdrEngine)
            } else {
                // No signal, advance
                await MainActor.run {
                    advanceToNext(sdrEngine: sdrEngine)
                }
            }
        }
    }

    private func handleSignalDetected(sdrEngine: SDREngine) async {
        let freq = currentFrequency

        await MainActor.run {
            state = .holding(frequency: freq)
            logActivity(.signalDetected, frequency: freq, strength: signalStrength)

            // Update hit count
            updateHitCount(for: freq)
        }

        // Wait while signal is active
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(settings.holdTime * 1_000_000_000))

            let strength = await MainActor.run { sdrEngine.dspEngine.signalStrength }
            await MainActor.run { signalStrength = strength }

            if strength <= settings.squelchLevel {
                // Signal dropped
                await MainActor.run {
                    logActivity(.signalLost, frequency: freq, strength: strength)
                }

                // Resume delay
                try? await Task.sleep(nanoseconds: UInt64(settings.resumeDelay * 1_000_000_000))

                await MainActor.run {
                    state = .scanning
                    advanceToNext(sdrEngine: sdrEngine)
                }
                break
            }
        }
    }

    private func checkPriorityChannels(sdrEngine: SDREngine) async -> Bool {
        for channel in priorityChannels where !channel.isLocked {
            await MainActor.run {
                sdrEngine.tuneTo(channel.frequency)
            }

            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms settle

            let strength = await MainActor.run { sdrEngine.dspEngine.signalStrength }

            if strength > settings.squelchLevel {
                await MainActor.run {
                    currentFrequency = channel.frequency
                }
                await handleSignalDetected(sdrEngine: sdrEngine)
                return true
            }
        }
        return false
    }

    private func advanceToNext(sdrEngine: SDREngine) {
        switch mode {
        case .range:
            if direction == .up {
                currentFrequency += settings.stepSize
                if currentFrequency > endFrequency {
                    currentFrequency = startFrequency
                }
            } else {
                currentFrequency -= settings.stepSize
                if currentFrequency < startFrequency {
                    currentFrequency = endFrequency
                }
            }

        case .memory, .priority:
            let list = mode == .memory ? memoryList : priorityChannels
            guard !list.isEmpty else { return }

            if direction == .up {
                currentIndex = (currentIndex + 1) % list.count
            } else {
                currentIndex = (currentIndex - 1 + list.count) % list.count
            }

            // Skip locked frequencies
            var attempts = 0
            while list[currentIndex].isLocked && attempts < list.count {
                if direction == .up {
                    currentIndex = (currentIndex + 1) % list.count
                } else {
                    currentIndex = (currentIndex - 1 + list.count) % list.count
                }
                attempts += 1
            }

            currentFrequency = list[currentIndex].frequency
        }
    }

    private func updateHitCount(for frequency: Double) {
        if let index = memoryList.firstIndex(where: { abs($0.frequency - frequency) < 100 }) {
            memoryList[index].hitCount += 1
            memoryList[index].lastActive = Date()

            // Add to active frequencies
            if !activeFrequencies.contains(where: { $0.frequency == frequency }) {
                activeFrequencies.insert(memoryList[index], at: 0)
                if activeFrequencies.count > 20 {
                    activeFrequencies.removeLast()
                }
            }
        } else {
            // New frequency discovered
            let entry = ScanEntry(frequency: frequency)
            activeFrequencies.insert(entry, at: 0)
            if activeFrequencies.count > 20 {
                activeFrequencies.removeLast()
            }
        }
    }

    // MARK: - Activity Log

    private func logActivity(_ type: ScanActivityType, frequency: Double, strength: Float) {
        let activity = ScanActivity(
            type: type,
            frequency: frequency,
            signalStrength: strength
        )
        activityLog.insert(activity, at: 0)
        if activityLog.count > 100 {
            activityLog.removeLast()
        }
    }

    // MARK: - Memory Management

    public func addToMemory(_ frequency: Double, mode: String = "FM", label: String? = nil) {
        let entry = ScanEntry(frequency: frequency, mode: mode, label: label)
        memoryList.append(entry)
        saveData()
    }

    public func removeFromMemory(_ entry: ScanEntry) {
        memoryList.removeAll { $0.id == entry.id }
        saveData()
    }

    public func addToPriority(_ entry: ScanEntry) {
        if !priorityChannels.contains(where: { $0.frequency == entry.frequency }) {
            priorityChannels.append(entry)
            saveData()
        }
    }

    public func removeFromPriority(_ entry: ScanEntry) {
        priorityChannels.removeAll { $0.id == entry.id }
        saveData()
    }

    // MARK: - Persistence

    private func saveData() {
        let data = ScannerData(
            memoryList: memoryList,
            priorityChannels: priorityChannels,
            lockoutList: Array(lockoutList),
            settings: settings
        )
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }

    private func loadData() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode(ScannerData.self, from: data) {
            memoryList = decoded.memoryList
            priorityChannels = decoded.priorityChannels
            lockoutList = Set(decoded.lockoutList)
            settings = decoded.settings
        }
    }
}

// MARK: - Supporting Types

public struct ScanActivity: Identifiable {
    public let id = UUID()
    public let type: ScanActivityType
    public let frequency: Double
    public let signalStrength: Float
    public let timestamp: Date

    public init(type: ScanActivityType, frequency: Double, signalStrength: Float) {
        self.type = type
        self.frequency = frequency
        self.signalStrength = signalStrength
        self.timestamp = Date()
    }
}

public enum ScanActivityType {
    case signalDetected
    case signalLost
    case priorityHit
}

private struct ScannerData: Codable {
    let memoryList: [ScanEntry]
    let priorityChannels: [ScanEntry]
    let lockoutList: [Double]
    let settings: ScannerSettings
}

// MARK: - Scanner View

public struct ScannerView: View {
    @ObservedObject var scanner = Scanner.shared
    @EnvironmentObject var sdrEngine: SDREngine

    @State private var showingSettings = false
    @State private var showingAddMemory = false

    public var body: some View {
        VStack(spacing: 0) {
            // Scanner Header
            ScannerHeaderView()

            // Main Display
            HStack(spacing: 16) {
                // Frequency Display
                VStack(alignment: .leading, spacing: 8) {
                    Text("SCANNING")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(scannerStatusColor)

                    Text(FrequencyFormatter.format(scanner.currentFrequency))
                        .font(.system(size: 32, weight: .light, design: .monospaced))
                        .foregroundColor(.cyan)

                    SignalBar(strength: scanner.signalStrength, squelch: scanner.settings.squelchLevel)
                }

                Spacer()

                // Scan Controls
                ScanControlButtons()
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(12)

            // Tabs
            TabView {
                // Active Frequencies
                ActiveFrequenciesView()
                    .tabItem {
                        Label("Active", systemImage: "waveform")
                    }

                // Memory List
                MemoryListView()
                    .tabItem {
                        Label("Memory", systemImage: "list.bullet")
                    }

                // Lockout List
                LockoutListView()
                    .tabItem {
                        Label("Lockout", systemImage: "nosign")
                    }

                // Activity Log
                ActivityLogView()
                    .tabItem {
                        Label("Log", systemImage: "clock")
                    }
            }
            .frame(height: 250)
        }
        .sheet(isPresented: $showingSettings) {
            ScannerSettingsView()
        }
    }

    private var scannerStatusColor: Color {
        switch scanner.state {
        case .idle: return .gray
        case .scanning: return .green
        case .holding: return .orange
        case .paused: return .yellow
        }
    }
}

struct ScannerHeaderView: View {
    @ObservedObject var scanner = Scanner.shared

    var body: some View {
        HStack {
            // Mode Picker
            Picker("Mode", selection: $scanner.mode) {
                ForEach(ScanMode.allCases, id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 250)

            Spacer()

            // Direction
            Picker("Direction", selection: $scanner.direction) {
                Text("Up").tag(ScanDirection.up)
                Text("Down").tag(ScanDirection.down)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)

            // Range settings (for range mode)
            if scanner.mode == .range {
                HStack(spacing: 8) {
                    FrequencyInput(label: "Start", value: $scanner.startFrequency)
                    Text("-")
                    FrequencyInput(label: "End", value: $scanner.endFrequency)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial.opacity(0.5))
    }
}

struct ScanControlButtons: View {
    @ObservedObject var scanner = Scanner.shared
    @EnvironmentObject var sdrEngine: SDREngine

    private var isIdle: Bool {
        if case .idle = scanner.state { return true }
        return false
    }

    private var isPaused: Bool {
        if case .paused = scanner.state { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 12) {
            // Start/Stop
            Button {
                if case .idle = scanner.state {
                    scanner.startScan(sdrEngine: sdrEngine)
                } else {
                    scanner.stopScan()
                }
            } label: {
                Image(systemName: isIdle ? "play.fill" : "stop.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(isIdle ? Color.green : Color.red)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            // Pause/Resume
            Button {
                if case .paused = scanner.state {
                    scanner.resumeScan()
                } else {
                    scanner.pauseScan()
                }
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 18))
            }
            .buttonStyle(.bordered)
            .disabled(isIdle)

            // Skip
            Button {
                scanner.skipCurrent(sdrEngine: sdrEngine)
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 18))
            }
            .buttonStyle(.bordered)
            .disabled(isIdle)

            // Lockout
            Button {
                scanner.lockoutCurrent()
            } label: {
                Image(systemName: "nosign")
                    .font(.system(size: 18))
            }
            .buttonStyle(.bordered)
            .disabled(isIdle)
        }
    }
}

struct SignalBar: View {
    let strength: Float
    let squelch: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.3))

                // Signal level
                let normalizedStrength = CGFloat((strength + 120) / 120)
                RoundedRectangle(cornerRadius: 4)
                    .fill(signalColor)
                    .frame(width: geometry.size.width * max(0, min(1, normalizedStrength)))

                // Squelch marker
                let normalizedSquelch = CGFloat((squelch + 120) / 120)
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: 2)
                    .offset(x: geometry.size.width * max(0, min(1, normalizedSquelch)))
            }
        }
        .frame(height: 12)
    }

    private var signalColor: Color {
        if strength > -50 { return .red }
        if strength > -70 { return .orange }
        if strength > -90 { return .green }
        return .blue
    }
}

struct FrequencyInput: View {
    let label: String
    @Binding var value: Double

    @State private var textValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            TextField("MHz", text: $textValue)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
                .onAppear {
                    textValue = String(format: "%.4f", value / 1_000_000)
                }
                .onChange(of: textValue) { _, newValue in
                    if let mhz = Double(newValue) {
                        value = mhz * 1_000_000
                    }
                }
        }
    }
}

struct ActiveFrequenciesView: View {
    @ObservedObject var scanner = Scanner.shared
    @EnvironmentObject var sdrEngine: SDREngine

    var body: some View {
        List {
            ForEach(scanner.activeFrequencies) { entry in
                HStack {
                    VStack(alignment: .leading) {
                        Text(entry.formattedFrequency)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.cyan)
                        if let label = entry.label {
                            Text(label)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Text("\(entry.hitCount) hits")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    if let lastActive = entry.lastActive {
                        Text(lastActive, style: .relative)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .contextMenu {
                    Button {
                        sdrEngine.tuneTo(entry.frequency)
                    } label: {
                        Label("Tune", systemImage: "antenna.radiowaves.left.and.right")
                    }

                    Button {
                        scanner.addToMemory(entry.frequency, label: entry.label)
                    } label: {
                        Label("Add to Memory", systemImage: "plus")
                    }

                    Button {
                        scanner.lockoutList.insert(entry.frequency)
                    } label: {
                        Label("Lockout", systemImage: "nosign")
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}

struct MemoryListView: View {
    @ObservedObject var scanner = Scanner.shared

    var body: some View {
        List {
            ForEach(scanner.memoryList) { entry in
                HStack {
                    Image(systemName: entry.isLocked ? "lock.fill" : "antenna.radiowaves.left.and.right")
                        .foregroundColor(entry.isLocked ? .red : .green)
                        .frame(width: 20)

                    VStack(alignment: .leading) {
                        Text(entry.formattedFrequency)
                            .font(.system(size: 13, design: .monospaced))
                        if let label = entry.label {
                            Text(label)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Text(entry.mode)
                        .font(.system(size: 10))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.3))
                        .cornerRadius(4)
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    scanner.memoryList.remove(at: index)
                }
            }
        }
        .listStyle(.inset)
    }
}

struct LockoutListView: View {
    @ObservedObject var scanner = Scanner.shared

    var body: some View {
        VStack {
            if scanner.lockoutList.isEmpty {
                Text("No lockouts")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                List {
                    ForEach(Array(scanner.lockoutList).sorted(), id: \.self) { freq in
                        HStack {
                            Text(FrequencyFormatter.format(freq))
                                .font(.system(size: 13, design: .monospaced))

                            Spacer()

                            Button {
                                scanner.clearLockout(freq)
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.inset)

                Button("Clear All Lockouts") {
                    scanner.clearAllLockouts()
                }
                .buttonStyle(.bordered)
                .padding()
            }
        }
    }
}

struct ActivityLogView: View {
    @ObservedObject var scanner = Scanner.shared

    var body: some View {
        List {
            ForEach(scanner.activityLog) { activity in
                HStack {
                    Image(systemName: activity.type == .signalDetected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .foregroundColor(activity.type == .signalDetected ? .green : .gray)

                    Text(FrequencyFormatter.format(activity.frequency))
                        .font(.system(size: 12, design: .monospaced))

                    Text(String(format: "%.0f dB", activity.signalStrength))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(activity.timestamp, style: .time)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.inset)
    }
}

struct ScannerSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var scanner = Scanner.shared

    var body: some View {
        Form {
            Section("Squelch") {
                HStack {
                    Text("Level")
                    Slider(value: $scanner.settings.squelchLevel, in: -120...0)
                    Text(String(format: "%.0f dB", scanner.settings.squelchLevel))
                        .frame(width: 60)
                }
            }

            Section("Timing") {
                HStack {
                    Text("Hold Time")
                    Slider(value: $scanner.settings.holdTime, in: 0.5...10)
                    Text(String(format: "%.1f s", scanner.settings.holdTime))
                        .frame(width: 60)
                }

                HStack {
                    Text("Resume Delay")
                    Slider(value: $scanner.settings.resumeDelay, in: 0.5...10)
                    Text(String(format: "%.1f s", scanner.settings.resumeDelay))
                        .frame(width: 60)
                }

                HStack {
                    Text("Scan Speed")
                    Slider(value: $scanner.settings.scanSpeed, in: 0.05...1.0)
                    Text(String(format: "%.2f s", scanner.settings.scanSpeed))
                        .frame(width: 60)
                }
            }

            Section("Range Scan") {
                HStack {
                    Text("Step Size")
                    TextField("Hz", value: $scanner.settings.stepSize, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Text("Hz")
                }
            }

            Section("Priority") {
                HStack {
                    Text("Check Interval")
                    Stepper("\(scanner.priorityInterval) steps", value: $scanner.priorityInterval, in: 1...20)
                }
            }
        }
        .padding()
        .frame(width: 400, height: 400)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}
