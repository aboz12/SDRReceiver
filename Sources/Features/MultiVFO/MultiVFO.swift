import Foundation
import SwiftUI

// MARK: - VFO Model

public struct VFO: Identifiable, Codable {
    public var id: UUID
    public var name: String
    public var frequency: Double
    public var mode: String
    public var bandwidth: Double
    public var squelch: Float
    public var gain: Double
    public var isActive: Bool
    public var color: String

    public init(
        id: UUID = UUID(),
        name: String = "VFO-A",
        frequency: Double = 100_000_000,
        mode: String = "FM",
        bandwidth: Double = 12500,
        squelch: Float = -100,
        gain: Double = 30,
        isActive: Bool = true,
        color: String = "cyan"
    ) {
        self.id = id
        self.name = name
        self.frequency = frequency
        self.mode = mode
        self.bandwidth = bandwidth
        self.squelch = squelch
        self.gain = gain
        self.isActive = isActive
        self.color = color
    }

    public var formattedFrequency: String {
        FrequencyFormatter.format(frequency)
    }
}

// MARK: - Multi-VFO Manager

@MainActor
public final class MultiVFOManager: ObservableObject {
    public static let shared = MultiVFOManager()

    @Published public var vfos: [VFO] = []
    @Published public var activeVFOIndex: Int = 0
    @Published public var splitMode: Bool = false
    @Published public var lockVFO: Bool = false

    public var activeVFO: VFO? {
        guard activeVFOIndex < vfos.count else { return nil }
        return vfos[activeVFOIndex]
    }

    public var maxVFOs: Int = 4

    private let saveKey = "SDRMultiVFO"

    private init() {
        loadVFOs()
        if vfos.isEmpty {
            createDefaultVFOs()
        }
    }

    // MARK: - VFO Operations

    public func addVFO() {
        guard vfos.count < maxVFOs else { return }

        let names = ["VFO-A", "VFO-B", "VFO-C", "VFO-D"]
        let colors = ["cyan", "green", "orange", "purple"]
        let index = vfos.count

        let vfo = VFO(
            name: names[index],
            isActive: vfos.isEmpty,
            color: colors[index]
        )
        vfos.append(vfo)
        saveVFOs()
    }

    public func removeVFO(at index: Int) {
        guard vfos.count > 1, index < vfos.count else { return }

        vfos.remove(at: index)
        if activeVFOIndex >= vfos.count {
            activeVFOIndex = vfos.count - 1
        }
        saveVFOs()
    }

    public func selectVFO(at index: Int) {
        guard index < vfos.count else { return }

        // Deactivate current
        if activeVFOIndex < vfos.count {
            vfos[activeVFOIndex].isActive = false
        }

        activeVFOIndex = index
        vfos[index].isActive = true
        saveVFOs()
    }

    public func updateActiveVFO(frequency: Double? = nil, mode: String? = nil, bandwidth: Double? = nil, squelch: Float? = nil, gain: Double? = nil) {
        guard activeVFOIndex < vfos.count else { return }

        if let freq = frequency {
            vfos[activeVFOIndex].frequency = freq
        }
        if let m = mode {
            vfos[activeVFOIndex].mode = m
        }
        if let bw = bandwidth {
            vfos[activeVFOIndex].bandwidth = bw
        }
        if let sq = squelch {
            vfos[activeVFOIndex].squelch = sq
        }
        if let g = gain {
            vfos[activeVFOIndex].gain = g
        }

        saveVFOs()
    }

    public func swapVFOs() {
        guard vfos.count >= 2 else { return }

        let temp = vfos[0]
        vfos[0] = vfos[1]
        vfos[1] = temp

        // Keep names and colors
        let name0 = vfos[0].name
        let color0 = vfos[0].color
        vfos[0].name = vfos[1].name
        vfos[0].color = vfos[1].color
        vfos[1].name = name0
        vfos[1].color = color0

        saveVFOs()
    }

    public func copyActiveToVFO(at index: Int) {
        guard activeVFOIndex < vfos.count, index < vfos.count, index != activeVFOIndex else { return }

        vfos[index].frequency = vfos[activeVFOIndex].frequency
        vfos[index].mode = vfos[activeVFOIndex].mode
        vfos[index].bandwidth = vfos[activeVFOIndex].bandwidth
        vfos[index].squelch = vfos[activeVFOIndex].squelch
        vfos[index].gain = vfos[activeVFOIndex].gain

        saveVFOs()
    }

    public func applyVFOToSDR(_ sdrEngine: SDREngine, vfoIndex: Int? = nil) {
        let index = vfoIndex ?? activeVFOIndex
        guard index < vfos.count else { return }

        let vfo = vfos[index]
        sdrEngine.tuneTo(vfo.frequency)
        if let mode = DemodulationMode(rawValue: vfo.mode) {
            sdrEngine.dspEngine.demodulationMode = mode
        }
        sdrEngine.dspEngine.filterBandwidth = vfo.bandwidth
        sdrEngine.dspEngine.squelchLevel = vfo.squelch
        sdrEngine.gain = vfo.gain
    }

    public func saveCurrentToVFO(from sdrEngine: SDREngine, vfoIndex: Int? = nil) {
        let index = vfoIndex ?? activeVFOIndex
        guard index < vfos.count else { return }

        vfos[index].frequency = sdrEngine.frequency
        vfos[index].mode = sdrEngine.dspEngine.demodulationMode.rawValue
        vfos[index].bandwidth = sdrEngine.dspEngine.filterBandwidth
        vfos[index].squelch = sdrEngine.dspEngine.squelchLevel
        vfos[index].gain = sdrEngine.gain

        saveVFOs()
    }

    // MARK: - Persistence

    private func saveVFOs() {
        if let data = try? JSONEncoder().encode(vfos) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    private func loadVFOs() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([VFO].self, from: data) {
            vfos = decoded
            activeVFOIndex = vfos.firstIndex(where: { $0.isActive }) ?? 0
        }
    }

    private func createDefaultVFOs() {
        vfos = [
            VFO(name: "VFO-A", frequency: 100_000_000, isActive: true, color: "cyan"),
            VFO(name: "VFO-B", frequency: 144_000_000, isActive: false, color: "green")
        ]
        saveVFOs()
    }
}

// MARK: - Multi-VFO View

public struct MultiVFOView: View {
    @ObservedObject var vfoManager = MultiVFOManager.shared
    @EnvironmentObject var sdrEngine: SDREngine

    public var body: some View {
        VStack(spacing: 8) {
            // VFO Tabs
            HStack(spacing: 4) {
                ForEach(Array(vfoManager.vfos.enumerated()), id: \.element.id) { index, vfo in
                    VFOTab(vfo: vfo, index: index, isActive: index == vfoManager.activeVFOIndex)
                        .onTapGesture {
                            vfoManager.selectVFO(at: index)
                            vfoManager.applyVFOToSDR(sdrEngine, vfoIndex: index)
                        }
                }

                // Add VFO button
                if vfoManager.vfos.count < vfoManager.maxVFOs {
                    Button {
                        vfoManager.addVFO()
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 8)
                }

                Spacer()

                // VFO Operations
                HStack(spacing: 8) {
                    Button {
                        vfoManager.swapVFOs()
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Swap VFO-A and VFO-B")

                    Button {
                        vfoManager.saveCurrentToVFO(from: sdrEngine)
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Save current to active VFO")

                    Toggle(isOn: $vfoManager.lockVFO) {
                        Image(systemName: vfoManager.lockVFO ? "lock.fill" : "lock.open")
                            .font(.system(size: 12))
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .help("Lock VFO")
                }
            }

            // Active VFO Display
            if let activeVFO = vfoManager.activeVFO {
                VFODetailView(vfo: activeVFO)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

struct VFOTab: View {
    let vfo: VFO
    let index: Int
    let isActive: Bool

    @ObservedObject var vfoManager = MultiVFOManager.shared

    var body: some View {
        VStack(spacing: 2) {
            Text(vfo.name)
                .font(.system(size: 10, weight: isActive ? .bold : .regular))

            Text(vfo.formattedFrequency)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(vfo.color))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color(vfo.color).opacity(0.2) : Color.clear)
                .strokeBorder(Color(vfo.color).opacity(isActive ? 0.5 : 0.2), lineWidth: 1)
        }
        .contextMenu {
            Button {
                vfoManager.copyActiveToVFO(at: index)
            } label: {
                Label("Copy from Active", systemImage: "doc.on.doc")
            }

            if vfoManager.vfos.count > 1 {
                Button(role: .destructive) {
                    vfoManager.removeVFO(at: index)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }
}

struct VFODetailView: View {
    let vfo: VFO

    var body: some View {
        HStack(spacing: 16) {
            // Frequency
            VStack(alignment: .leading, spacing: 2) {
                Text("FREQUENCY")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                Text(vfo.formattedFrequency)
                    .font(.system(size: 18, weight: .light, design: .monospaced))
                    .foregroundColor(Color(vfo.color))
            }

            Divider()
                .frame(height: 30)

            // Mode
            VStack(alignment: .leading, spacing: 2) {
                Text("MODE")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                Text(vfo.mode)
                    .font(.system(size: 14, weight: .medium))
            }

            // Bandwidth
            VStack(alignment: .leading, spacing: 2) {
                Text("BW")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                Text(formatBandwidth(vfo.bandwidth))
                    .font(.system(size: 14, design: .monospaced))
            }

            // Squelch
            VStack(alignment: .leading, spacing: 2) {
                Text("SQL")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                Text(String(format: "%.0f", vfo.squelch))
                    .font(.system(size: 14, design: .monospaced))
            }

            Spacer()
        }
    }

    private func formatBandwidth(_ bw: Double) -> String {
        if bw >= 1000 {
            return String(format: "%.1fk", bw / 1000)
        }
        return String(format: "%.0f", bw)
    }
}

// MARK: - Compact VFO Selector

public struct CompactVFOSelector: View {
    @ObservedObject var vfoManager = MultiVFOManager.shared
    @EnvironmentObject var sdrEngine: SDREngine

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(vfoManager.vfos.enumerated()), id: \.element.id) { index, vfo in
                Button {
                    vfoManager.selectVFO(at: index)
                    vfoManager.applyVFOToSDR(sdrEngine, vfoIndex: index)
                } label: {
                    Text(String(vfo.name.last ?? "A"))
                        .font(.system(size: 11, weight: index == vfoManager.activeVFOIndex ? .bold : .regular))
                        .foregroundColor(index == vfoManager.activeVFOIndex ? Color(vfo.color) : .secondary)
                        .frame(width: 24, height: 24)
                        .background {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(index == vfoManager.activeVFOIndex ? Color(vfo.color).opacity(0.2) : Color.clear)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
