import SwiftUI
import Foundation

// MARK: - VFO State

public struct VFOState: Identifiable, Codable {
    public let id: UUID
    public var frequency: Double
    public var mode: String
    public var filterBandwidth: Double
    public var label: String
    public var isActive: Bool

    public init(
        frequency: Double = 100_000_000,
        mode: String = "FM",
        filterBandwidth: Double = 12500,
        label: String = "VFO",
        isActive: Bool = false
    ) {
        self.id = UUID()
        self.frequency = frequency
        self.mode = mode
        self.filterBandwidth = filterBandwidth
        self.label = label
        self.isActive = isActive
    }
}

// MARK: - Split VFO Manager

@MainActor
public final class SplitVFOManager: ObservableObject {
    public static let shared = SplitVFOManager()

    @Published public var vfoA: VFOState
    @Published public var vfoB: VFOState
    @Published public var activeVFO: VFOSelector = .a
    @Published public var splitEnabled: Bool = false
    @Published public var linkVFOs: Bool = false // Link tuning between VFOs

    public enum VFOSelector: String, CaseIterable {
        case a = "A"
        case b = "B"
    }

    private let saveKey = "SplitVFOState"

    private init() {
        self.vfoA = VFOState(frequency: 100_000_000, mode: "FM", label: "VFO A", isActive: true)
        self.vfoB = VFOState(frequency: 144_200_000, mode: "USB", label: "VFO B", isActive: false)
        loadState()
    }

    public var currentVFO: VFOState {
        get { activeVFO == .a ? vfoA : vfoB }
        set {
            if activeVFO == .a {
                vfoA = newValue
            } else {
                vfoB = newValue
            }
        }
    }

    public func selectVFO(_ vfo: VFOSelector) {
        // Deactivate current
        if activeVFO == .a {
            vfoA.isActive = false
        } else {
            vfoB.isActive = false
        }

        activeVFO = vfo

        // Activate new
        if vfo == .a {
            vfoA.isActive = true
            applyVFO(vfoA)
        } else {
            vfoB.isActive = true
            applyVFO(vfoB)
        }

        saveState()
    }

    public func swapVFOs() {
        let temp = vfoA
        vfoA = vfoB
        vfoB = temp

        // Preserve labels
        vfoA.label = "VFO A"
        vfoB.label = "VFO B"

        // Update active state
        if activeVFO == .a {
            vfoA.isActive = true
            vfoB.isActive = false
            applyVFO(vfoA)
        } else {
            vfoA.isActive = false
            vfoB.isActive = true
            applyVFO(vfoB)
        }

        saveState()
    }

    public func copyAtoB() {
        vfoB.frequency = vfoA.frequency
        vfoB.mode = vfoA.mode
        vfoB.filterBandwidth = vfoA.filterBandwidth
        saveState()
    }

    public func copyBtoA() {
        vfoA.frequency = vfoB.frequency
        vfoA.mode = vfoB.mode
        vfoA.filterBandwidth = vfoB.filterBandwidth
        saveState()
    }

    public func updateCurrentVFO(frequency: Double? = nil, mode: String? = nil, filterBandwidth: Double? = nil) {
        if activeVFO == .a {
            if let freq = frequency { vfoA.frequency = freq }
            if let m = mode { vfoA.mode = m }
            if let bw = filterBandwidth { vfoA.filterBandwidth = bw }

            if linkVFOs, let freq = frequency {
                let offset = vfoB.frequency - vfoA.frequency
                vfoB.frequency = freq + offset
            }
        } else {
            if let freq = frequency { vfoB.frequency = freq }
            if let m = mode { vfoB.mode = m }
            if let bw = filterBandwidth { vfoB.filterBandwidth = bw }

            if linkVFOs, let freq = frequency {
                let offset = vfoA.frequency - vfoB.frequency
                vfoA.frequency = freq + offset
            }
        }

        saveState()
    }

    public func syncFromEngine() {
        let engine = SDREngine.shared
        if activeVFO == .a {
            vfoA.frequency = engine.frequency
            vfoA.mode = engine.dspEngine.demodulationMode.rawValue
            vfoA.filterBandwidth = engine.dspEngine.filterBandwidth
        } else {
            vfoB.frequency = engine.frequency
            vfoB.mode = engine.dspEngine.demodulationMode.rawValue
            vfoB.filterBandwidth = engine.dspEngine.filterBandwidth
        }
    }

    private func applyVFO(_ vfo: VFOState) {
        let engine = SDREngine.shared
        engine.frequency = vfo.frequency
        if let mode = DemodulationMode(rawValue: vfo.mode) {
            engine.dspEngine.demodulationMode = mode
        }
        engine.dspEngine.filterBandwidth = vfo.filterBandwidth
    }

    private func saveState() {
        let state = SavedVFOState(vfoA: vfoA, vfoB: vfoB, activeVFO: activeVFO.rawValue, splitEnabled: splitEnabled, linkVFOs: linkVFOs)
        if let encoded = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }

    private func loadState() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let state = try? JSONDecoder().decode(SavedVFOState.self, from: data) else {
            return
        }

        vfoA = state.vfoA
        vfoB = state.vfoB
        activeVFO = VFOSelector(rawValue: state.activeVFO) ?? .a
        splitEnabled = state.splitEnabled
        linkVFOs = state.linkVFOs

        // Set active states
        vfoA.isActive = activeVFO == .a
        vfoB.isActive = activeVFO == .b
    }

    private struct SavedVFOState: Codable {
        let vfoA: VFOState
        let vfoB: VFOState
        let activeVFO: String
        let splitEnabled: Bool
        let linkVFOs: Bool
    }
}

// MARK: - Split VFO View

public struct SplitVFOView: View {
    @ObservedObject var vfoManager = SplitVFOManager.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 8) {
            // VFO Selection
            HStack(spacing: 16) {
                VFOCard(vfo: vfoManager.vfoA, isActive: vfoManager.activeVFO == .a) {
                    vfoManager.selectVFO(.a)
                }

                VFOCard(vfo: vfoManager.vfoB, isActive: vfoManager.activeVFO == .b) {
                    vfoManager.selectVFO(.b)
                }
            }

            // Controls
            HStack(spacing: 12) {
                Button {
                    vfoManager.swapVFOs()
                } label: {
                    Label("A<>B", systemImage: "arrow.left.arrow.right")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    vfoManager.copyAtoB()
                } label: {
                    Text("A>B")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    vfoManager.copyBtoA()
                } label: {
                    Text("A<B")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Toggle("Split", isOn: $vfoManager.splitEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Toggle("Link", isOn: $vfoManager.linkVFOs)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

struct VFOCard: View {
    let vfo: VFOState
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(vfo.label)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if isActive {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                    }
                }

                Text(FrequencyFormatter.format(vfo.frequency))
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(isActive ? .cyan : .primary)

                HStack {
                    Text(vfo.mode)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isActive ? .cyan.opacity(0.2) : .gray.opacity(0.2))
                        .cornerRadius(4)

                    Text(formatBandwidth(vfo.filterBandwidth))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(isActive ? .blue.opacity(0.1) : .clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? .cyan : .gray.opacity(0.3), lineWidth: isActive ? 2 : 1)
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func formatBandwidth(_ bw: Double) -> String {
        if bw >= 1000 {
            return String(format: "%.1f kHz", bw / 1000)
        }
        return String(format: "%.0f Hz", bw)
    }
}

// MARK: - Compact Split VFO Selector

public struct CompactSplitVFOSelector: View {
    @ObservedObject var vfoManager = SplitVFOManager.shared

    public init() {}

    public var body: some View {
        HStack(spacing: 4) {
            Button {
                vfoManager.selectVFO(.a)
            } label: {
                Text("A")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(vfoManager.activeVFO == .a ? .white : .cyan)
                    .frame(width: 22, height: 18)
                    .background(vfoManager.activeVFO == .a ? .cyan : .clear)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)

            Button {
                vfoManager.selectVFO(.b)
            } label: {
                Text("B")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(vfoManager.activeVFO == .b ? .white : .cyan)
                    .frame(width: 22, height: 18)
                    .background(vfoManager.activeVFO == .b ? .cyan : .clear)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)

            Button {
                vfoManager.swapVFOs()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial.opacity(0.5))
        .cornerRadius(6)
    }
}

// MARK: - Mini VFO Display

public struct MiniVFODisplay: View {
    @ObservedObject var vfoManager = SplitVFOManager.shared
    let showInactive: Bool

    public init(showInactive: Bool = true) {
        self.showInactive = showInactive
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Active VFO
            HStack(spacing: 4) {
                Text(vfoManager.activeVFO == .a ? "A" : "B")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.green)

                Text(FrequencyFormatter.format(vfoManager.currentVFO.frequency))
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.cyan)

                Text(vfoManager.currentVFO.mode)
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            }

            // Inactive VFO (smaller)
            if showInactive {
                let inactive = vfoManager.activeVFO == .a ? vfoManager.vfoB : vfoManager.vfoA
                HStack(spacing: 4) {
                    Text(vfoManager.activeVFO == .a ? "B" : "A")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.gray)

                    Text(FrequencyFormatter.format(inactive.frequency))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.gray)

                    Text(inactive.mode)
                        .font(.system(size: 8))
                        .foregroundColor(.gray.opacity(0.7))
                }
            }
        }
    }
}
