import Foundation
import SwiftUI

// MARK: - Memory Channel Model

public struct MemoryChannel: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var frequency: Double
    public var mode: String
    public var bandwidth: Double
    public var squelch: Float
    public var gain: Double
    public var notes: String
    public var tags: [String]
    public var isFavorite: Bool
    public var lastUsed: Date?
    public var useCount: Int

    public init(
        id: UUID = UUID(),
        name: String,
        frequency: Double,
        mode: String = "FM",
        bandwidth: Double = 12500,
        squelch: Float = -100,
        gain: Double = 30,
        notes: String = "",
        tags: [String] = [],
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.frequency = frequency
        self.mode = mode
        self.bandwidth = bandwidth
        self.squelch = squelch
        self.gain = gain
        self.notes = notes
        self.tags = tags
        self.isFavorite = isFavorite
        self.lastUsed = nil
        self.useCount = 0
    }

    public var formattedFrequency: String {
        if frequency >= 1_000_000_000 {
            return String(format: "%.4f GHz", frequency / 1_000_000_000)
        } else if frequency >= 1_000_000 {
            return String(format: "%.4f MHz", frequency / 1_000_000)
        } else {
            return String(format: "%.3f kHz", frequency / 1_000)
        }
    }
}

// MARK: - Memory Bank (Folder)

public struct MemoryBank: Identifiable, Codable {
    public var id: UUID
    public var name: String
    public var icon: String
    public var color: String
    public var channels: [MemoryChannel]
    public var isExpanded: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String = "folder",
        color: String = "blue",
        channels: [MemoryChannel] = []
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.channels = channels
        self.isExpanded = true
    }
}

// MARK: - Memory Manager

@MainActor
public final class MemoryManager: ObservableObject {
    public static let shared = MemoryManager()

    @Published public var banks: [MemoryBank] = []
    @Published public var recentChannels: [MemoryChannel] = []
    @Published public var searchText: String = ""

    private let saveKey = "SDRMemoryBanks"
    private let maxRecent = 20

    private init() {
        loadBanks()
        if banks.isEmpty {
            createDefaultBanks()
        }
    }

    // MARK: - Bank Operations

    public func createBank(name: String, icon: String = "folder", color: String = "blue") {
        let bank = MemoryBank(name: name, icon: icon, color: color)
        banks.append(bank)
        saveBanks()
    }

    public func deleteBank(_ bank: MemoryBank) {
        banks.removeAll { $0.id == bank.id }
        saveBanks()
    }

    public func renameBank(_ bank: MemoryBank, to name: String) {
        if let index = banks.firstIndex(where: { $0.id == bank.id }) {
            banks[index].name = name
            saveBanks()
        }
    }

    // MARK: - Channel Operations

    public func addChannel(_ channel: MemoryChannel, to bankId: UUID) {
        if let index = banks.firstIndex(where: { $0.id == bankId }) {
            banks[index].channels.append(channel)
            saveBanks()
        }
    }

    public func deleteChannel(_ channel: MemoryChannel, from bankId: UUID) {
        if let index = banks.firstIndex(where: { $0.id == bankId }) {
            banks[index].channels.removeAll { $0.id == channel.id }
            saveBanks()
        }
    }

    public func updateChannel(_ channel: MemoryChannel, in bankId: UUID) {
        if let bankIndex = banks.firstIndex(where: { $0.id == bankId }),
           let channelIndex = banks[bankIndex].channels.firstIndex(where: { $0.id == channel.id }) {
            banks[bankIndex].channels[channelIndex] = channel
            saveBanks()
        }
    }

    public func toggleFavorite(_ channel: MemoryChannel, in bankId: UUID) {
        if let bankIndex = banks.firstIndex(where: { $0.id == bankId }),
           let channelIndex = banks[bankIndex].channels.firstIndex(where: { $0.id == channel.id }) {
            banks[bankIndex].channels[channelIndex].isFavorite.toggle()
            saveBanks()
        }
    }

    public func recordUsage(_ channel: MemoryChannel, in bankId: UUID) {
        if let bankIndex = banks.firstIndex(where: { $0.id == bankId }),
           let channelIndex = banks[bankIndex].channels.firstIndex(where: { $0.id == channel.id }) {
            banks[bankIndex].channels[channelIndex].lastUsed = Date()
            banks[bankIndex].channels[channelIndex].useCount += 1

            // Add to recent
            var updated = banks[bankIndex].channels[channelIndex]
            recentChannels.removeAll { $0.id == updated.id }
            recentChannels.insert(updated, at: 0)
            if recentChannels.count > maxRecent {
                recentChannels.removeLast()
            }

            saveBanks()
        }
    }

    // MARK: - Search

    public var filteredBanks: [MemoryBank] {
        guard !searchText.isEmpty else { return banks }

        return banks.compactMap { bank in
            let filteredChannels = bank.channels.filter { channel in
                channel.name.localizedCaseInsensitiveContains(searchText) ||
                channel.formattedFrequency.contains(searchText) ||
                channel.tags.contains { $0.localizedCaseInsensitiveContains(searchText) } ||
                channel.notes.localizedCaseInsensitiveContains(searchText)
            }

            if filteredChannels.isEmpty && !bank.name.localizedCaseInsensitiveContains(searchText) {
                return nil
            }

            var filteredBank = bank
            if !filteredChannels.isEmpty {
                filteredBank.channels = filteredChannels
            }
            return filteredBank
        }
    }

    public var favoriteChannels: [MemoryChannel] {
        banks.flatMap { $0.channels }.filter { $0.isFavorite }
    }

    public var allChannels: [MemoryChannel] {
        banks.flatMap { $0.channels }
    }

    // MARK: - Import/Export

    public func exportToCSV() -> String {
        var csv = "Bank,Name,Frequency,Mode,Bandwidth,Squelch,Gain,Notes,Tags,Favorite\n"

        for bank in banks {
            for channel in bank.channels {
                let tags = channel.tags.joined(separator: ";")
                csv += "\"\(bank.name)\",\"\(channel.name)\",\(channel.frequency),\(channel.mode),\(channel.bandwidth),\(channel.squelch),\(channel.gain),\"\(channel.notes)\",\"\(tags)\",\(channel.isFavorite)\n"
            }
        }

        return csv
    }

    public func importFromCSV(_ csvString: String) throws {
        let lines = csvString.components(separatedBy: .newlines)
        guard lines.count > 1 else { return }

        var newBanks: [String: MemoryBank] = [:]

        for line in lines.dropFirst() where !line.isEmpty {
            let columns = parseCSVLine(line)
            guard columns.count >= 6 else { continue }

            let bankName = columns[0]
            let channel = MemoryChannel(
                name: columns[1],
                frequency: Double(columns[2]) ?? 100_000_000,
                mode: columns.count > 3 ? columns[3] : "FM",
                bandwidth: columns.count > 4 ? Double(columns[4]) ?? 12500 : 12500,
                squelch: columns.count > 5 ? Float(columns[5]) ?? -100 : -100,
                gain: columns.count > 6 ? Double(columns[6]) ?? 30 : 30,
                notes: columns.count > 7 ? columns[7] : "",
                tags: columns.count > 8 ? columns[8].components(separatedBy: ";") : [],
                isFavorite: columns.count > 9 ? columns[9] == "true" : false
            )

            if var bank = newBanks[bankName] {
                bank.channels.append(channel)
                newBanks[bankName] = bank
            } else {
                newBanks[bankName] = MemoryBank(name: bankName, channels: [channel])
            }
        }

        banks.append(contentsOf: newBanks.values)
        saveBanks()
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var columns: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                columns.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        columns.append(current)

        return columns
    }

    // MARK: - Persistence

    private func saveBanks() {
        if let data = try? JSONEncoder().encode(banks) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    private func loadBanks() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([MemoryBank].self, from: data) {
            banks = decoded
        }
    }

    private func createDefaultBanks() {
        // Aviation
        var aviation = MemoryBank(name: "Aviation", icon: "airplane", color: "blue")
        aviation.channels = [
            MemoryChannel(name: "Guard", frequency: 121_500_000, mode: "AM", tags: ["emergency"]),
            MemoryChannel(name: "ATIS Example", frequency: 127_850_000, mode: "AM"),
            MemoryChannel(name: "ADS-B", frequency: 1_090_000_000, mode: "RAW", tags: ["adsb"]),
        ]

        // Amateur
        var amateur = MemoryBank(name: "Amateur Radio", icon: "antenna.radiowaves.left.and.right", color: "green")
        amateur.channels = [
            MemoryChannel(name: "2m Calling", frequency: 146_520_000, mode: "FM"),
            MemoryChannel(name: "70cm Calling", frequency: 446_000_000, mode: "FM"),
            MemoryChannel(name: "FT8 20m", frequency: 14_074_000, mode: "USB", bandwidth: 3000),
            MemoryChannel(name: "FT8 40m", frequency: 7_074_000, mode: "USB", bandwidth: 3000),
        ]

        // Broadcast
        var broadcast = MemoryBank(name: "Broadcast", icon: "radio", color: "orange")
        broadcast.channels = [
            MemoryChannel(name: "FM Example", frequency: 98_100_000, mode: "WFM", bandwidth: 200000),
        ]

        // Weather
        var weather = MemoryBank(name: "Weather", icon: "cloud.sun", color: "cyan")
        weather.channels = [
            MemoryChannel(name: "NOAA 15", frequency: 137_620_000, mode: "FM", bandwidth: 34000, tags: ["apt", "satellite"]),
            MemoryChannel(name: "NOAA 18", frequency: 137_912_500, mode: "FM", bandwidth: 34000, tags: ["apt", "satellite"]),
            MemoryChannel(name: "NOAA 19", frequency: 137_100_000, mode: "FM", bandwidth: 34000, tags: ["apt", "satellite"]),
        ]

        // L-Band
        var lband = MemoryBank(name: "L-Band Satellite", icon: "globe", color: "purple")
        lband.channels = [
            MemoryChannel(name: "Inmarsat 4F3", frequency: 1_545_600_000, mode: "RAW", tags: ["inmarsat"]),
            MemoryChannel(name: "Iridium", frequency: 1_626_000_000, mode: "RAW", bandwidth: 41667, tags: ["iridium"]),
        ]

        banks = [aviation, amateur, broadcast, weather, lband]
        saveBanks()
    }
}

// MARK: - Memory Bank View

public struct MemoryBankView: View {
    @ObservedObject var memoryManager = MemoryManager.shared
    @EnvironmentObject var sdrEngine: SDREngine

    @State private var showingAddBank = false
    @State private var showingAddChannel = false
    @State private var selectedBankId: UUID?
    @State private var showingImport = false
    @State private var showingExport = false

    public var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search frequencies...", text: $memoryManager.searchText)
                    .textFieldStyle(.plain)
                if !memoryManager.searchText.isEmpty {
                    Button {
                        memoryManager.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.ultraThinMaterial)

            // Quick access
            if memoryManager.searchText.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // Favorites
                        QuickAccessChip(
                            title: "Favorites",
                            icon: "star.fill",
                            count: memoryManager.favoriteChannels.count,
                            color: .yellow
                        ) {
                            // Show favorites
                        }

                        // Recent
                        QuickAccessChip(
                            title: "Recent",
                            icon: "clock",
                            count: memoryManager.recentChannels.count,
                            color: .blue
                        ) {
                            // Show recent
                        }

                        Divider()
                            .frame(height: 24)

                        // Bank chips
                        ForEach(memoryManager.banks) { bank in
                            QuickAccessChip(
                                title: bank.name,
                                icon: bank.icon,
                                count: bank.channels.count,
                                color: Color(bank.color)
                            ) {
                                selectedBankId = bank.id
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .background(.ultraThinMaterial.opacity(0.5))
            }

            // Bank list
            List {
                ForEach(memoryManager.filteredBanks) { bank in
                    MemoryBankSection(bank: bank, selectedBankId: $selectedBankId)
                }
            }
            .listStyle(.sidebar)

            // Bottom toolbar
            HStack {
                Button {
                    showingAddBank = true
                } label: {
                    Label("New Bank", systemImage: "folder.badge.plus")
                }

                Spacer()

                Menu {
                    Button {
                        showingImport = true
                    } label: {
                        Label("Import CSV", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        showingExport = true
                    } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            .padding(12)
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showingAddBank) {
            AddBankSheet()
        }
        .sheet(isPresented: $showingAddChannel) {
            if let bankId = selectedBankId {
                AddChannelSheet(bankId: bankId)
            }
        }
    }
}

struct QuickAccessChip: View {
    let title: String
    let icon: String
    let count: Int
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.3))
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .strokeBorder(color.opacity(0.3), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

struct MemoryBankSection: View {
    let bank: MemoryBank
    @Binding var selectedBankId: UUID?
    @EnvironmentObject var sdrEngine: SDREngine
    @ObservedObject var memoryManager = MemoryManager.shared

    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(bank.channels) { channel in
                MemoryChannelRow(channel: channel, bankId: bank.id)
                    .contextMenu {
                        Button {
                            tuneToChannel(channel)
                        } label: {
                            Label("Tune", systemImage: "antenna.radiowaves.left.and.right")
                        }

                        Button {
                            memoryManager.toggleFavorite(channel, in: bank.id)
                        } label: {
                            Label(
                                channel.isFavorite ? "Remove Favorite" : "Add Favorite",
                                systemImage: channel.isFavorite ? "star.slash" : "star"
                            )
                        }

                        Divider()

                        Button(role: .destructive) {
                            memoryManager.deleteChannel(channel, from: bank.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }

            Button {
                selectedBankId = bank.id
            } label: {
                Label("Add Channel", systemImage: "plus")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
        } label: {
            HStack {
                Image(systemName: bank.icon)
                    .foregroundColor(Color(bank.color))
                Text(bank.name)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(bank.channels.count)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func tuneToChannel(_ channel: MemoryChannel) {
        sdrEngine.tuneTo(channel.frequency)
        if let mode = DemodulationMode(rawValue: channel.mode) {
            sdrEngine.dspEngine.demodulationMode = mode
        }
        sdrEngine.dspEngine.filterBandwidth = channel.bandwidth
        sdrEngine.dspEngine.squelchLevel = channel.squelch
        sdrEngine.gain = channel.gain
        memoryManager.recordUsage(channel, in: bank.id)
    }
}

struct MemoryChannelRow: View {
    let channel: MemoryChannel
    let bankId: UUID
    @EnvironmentObject var sdrEngine: SDREngine
    @ObservedObject var memoryManager = MemoryManager.shared

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(channel.name)
                        .font(.system(size: 12, weight: .medium))
                    if channel.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.yellow)
                    }
                }
                Text(channel.formattedFrequency)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.cyan)
            }

            Spacer()

            Text(channel.mode)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.purple.opacity(0.2))
                .cornerRadius(4)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            tuneToChannel()
        }
    }

    private func tuneToChannel() {
        sdrEngine.tuneTo(channel.frequency)
        if let mode = DemodulationMode(rawValue: channel.mode) {
            sdrEngine.dspEngine.demodulationMode = mode
        }
        memoryManager.recordUsage(channel, in: bankId)
    }
}

struct AddBankSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var memoryManager = MemoryManager.shared

    @State private var name = ""
    @State private var icon = "folder"
    @State private var color = "blue"

    let icons = ["folder", "antenna.radiowaves.left.and.right", "airplane", "radio", "globe", "cloud.sun", "bolt", "star"]
    let colors = ["blue", "green", "orange", "purple", "cyan", "red", "yellow", "pink"]

    var body: some View {
        VStack(spacing: 20) {
            Text("New Memory Bank")
                .font(.headline)

            TextField("Bank Name", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("Icon:")
                Picker("", selection: $icon) {
                    ForEach(icons, id: \.self) { iconName in
                        Image(systemName: iconName).tag(iconName)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Text("Color:")
                Picker("", selection: $color) {
                    ForEach(colors, id: \.self) { colorName in
                        Circle()
                            .fill(Color(colorName))
                            .frame(width: 16, height: 16)
                            .tag(colorName)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Create") {
                    memoryManager.createBank(name: name, icon: icon, color: color)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding(30)
        .frame(width: 400)
    }
}

struct AddChannelSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var sdrEngine: SDREngine
    @ObservedObject var memoryManager = MemoryManager.shared

    let bankId: UUID

    @State private var name = ""
    @State private var frequency = ""
    @State private var mode = "FM"
    @State private var bandwidth = "12500"
    @State private var notes = ""
    @State private var tags = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Channel")
                .font(.headline)

            Form {
                TextField("Name", text: $name)
                TextField("Frequency (Hz)", text: $frequency)

                Picker("Mode", selection: $mode) {
                    ForEach(DemodulationMode.allCases, id: \.rawValue) { mode in
                        Text(mode.rawValue).tag(mode.rawValue)
                    }
                }

                TextField("Bandwidth (Hz)", text: $bandwidth)
                TextField("Tags (comma separated)", text: $tags)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3)
            }

            HStack {
                Button("Use Current") {
                    frequency = String(format: "%.0f", sdrEngine.frequency)
                    mode = sdrEngine.dspEngine.demodulationMode.rawValue
                    bandwidth = String(format: "%.0f", sdrEngine.dspEngine.filterBandwidth)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Add") {
                    let channel = MemoryChannel(
                        name: name,
                        frequency: Double(frequency) ?? 100_000_000,
                        mode: mode,
                        bandwidth: Double(bandwidth) ?? 12500,
                        notes: notes,
                        tags: tags.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    )
                    memoryManager.addChannel(channel, to: bankId)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || frequency.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 450, height: 400)
    }
}

// Color extension for string-based colors
extension Color {
    init(_ name: String) {
        switch name {
        case "blue": self = .blue
        case "green": self = .green
        case "orange": self = .orange
        case "purple": self = .purple
        case "cyan": self = .cyan
        case "red": self = .red
        case "yellow": self = .yellow
        case "pink": self = .pink
        default: self = .blue
        }
    }
}
