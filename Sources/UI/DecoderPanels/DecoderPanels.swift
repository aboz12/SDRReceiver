import SwiftUI
import MapKit

// MARK: - Decoder Panel Protocol

public protocol DecoderPanelView: View {
    var title: String { get }
    var icon: String { get }
}

// MARK: - ADS-B Map Panel

public struct ADSBMapPanel: View, DecoderPanelView {
    public var title = "ADS-B Aircraft"
    public var icon = "airplane"

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 5, longitudeDelta: 5)
    )

    @State private var aircraft: [AircraftPosition] = []
    @State private var selectedAircraft: AircraftPosition?
    @State private var showingList = false

    public var body: some View {
        HSplitView {
            // Map
            ZStack {
                Map(coordinateRegion: $region, annotationItems: aircraft) { ac in
                    MapAnnotation(coordinate: ac.coordinate) {
                        AircraftAnnotationView(aircraft: ac, isSelected: selectedAircraft?.id == ac.id)
                            .onTapGesture {
                                selectedAircraft = ac
                            }
                    }
                }

                // Info overlay
                VStack {
                    HStack {
                        Text("\(aircraft.count) aircraft")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial)
                            .cornerRadius(6)

                        Spacer()

                        Button {
                            showingList.toggle()
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()

                    Spacer()
                }
            }

            // Aircraft details / list
            if showingList || selectedAircraft != nil {
                VStack(spacing: 0) {
                    if let ac = selectedAircraft {
                        AircraftDetailView(aircraft: ac)
                            .frame(height: 200)
                    }

                    // Aircraft list
                    List(aircraft) { ac in
                        AircraftListRow(aircraft: ac, isSelected: selectedAircraft?.id == ac.id)
                            .onTapGesture {
                                selectedAircraft = ac
                                withAnimation {
                                    region.center = ac.coordinate
                                }
                            }
                    }
                    .listStyle(.inset)
                }
                .frame(minWidth: 250, maxWidth: 350)
            }
        }
    }
}

struct AircraftPosition: Identifiable {
    let id: String  // ICAO hex
    var callsign: String?
    var coordinate: CLLocationCoordinate2D
    var altitude: Int  // feet
    var speed: Int     // knots
    var heading: Int   // degrees
    var verticalRate: Int  // ft/min
    var squawk: String?
    var lastSeen: Date
    var isOnGround: Bool

    var formattedAltitude: String {
        if altitude > 0 {
            return "\(altitude / 100 * 100) ft"
        }
        return "GND"
    }
}

struct AircraftAnnotationView: View {
    let aircraft: AircraftPosition
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "airplane")
                .font(.system(size: 16))
                .foregroundColor(isSelected ? .yellow : .cyan)
                .rotationEffect(.degrees(Double(aircraft.heading)))

            if isSelected {
                Text(aircraft.callsign ?? aircraft.id)
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.7))
                    .cornerRadius(3)
            }
        }
    }
}

struct AircraftDetailView: View {
    let aircraft: AircraftPosition

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(aircraft.callsign ?? "Unknown")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Text(aircraft.id)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                DetailItem(label: "Altitude", value: aircraft.formattedAltitude)
                DetailItem(label: "Speed", value: "\(aircraft.speed) kts")
                DetailItem(label: "Heading", value: "\(aircraft.heading)°")
                DetailItem(label: "V/S", value: "\(aircraft.verticalRate) fpm")
                DetailItem(label: "Squawk", value: aircraft.squawk ?? "-")
                DetailItem(label: "Last Seen", value: aircraft.lastSeen.formatted(date: .omitted, time: .standard))
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

struct DetailItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, design: .monospaced))
        }
    }
}

struct AircraftListRow: View {
    let aircraft: AircraftPosition
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(aircraft.callsign ?? aircraft.id)
                    .font(.system(size: 13, weight: .medium))
                Text(aircraft.formattedAltitude)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("\(aircraft.speed) kts")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.cyan)
        }
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
    }
}

// MARK: - APRS Map Panel

public struct APRSMapPanel: View, DecoderPanelView {
    public var title = "APRS Stations"
    public var icon = "location.circle"

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 2, longitudeDelta: 2)
    )

    @State private var stations: [APRSStationUI] = []
    @State private var selectedStation: APRSStationUI?
    @State private var messages: [APRSMessage] = []

    public var body: some View {
        HSplitView {
            // Map
            Map(coordinateRegion: $region, annotationItems: stations) { station in
                MapAnnotation(coordinate: station.coordinate) {
                    APRSAnnotationView(station: station, isSelected: selectedStation?.id == station.id)
                        .onTapGesture {
                            selectedStation = station
                        }
                }
            }

            // Station list and messages
            VStack(spacing: 0) {
                // Station details
                if let station = selectedStation {
                    APRSStationDetailView(station: station)
                }

                // Messages
                List(messages) { message in
                    APRSMessageRow(message: message)
                }
                .listStyle(.inset)
            }
            .frame(minWidth: 250, maxWidth: 350)
        }
    }
}

struct APRSStationUI: Identifiable {
    let id: String  // Callsign
    var coordinate: CLLocationCoordinate2D
    var symbol: String
    var comment: String?
    var lastHeard: Date
    var path: String?
    var speed: Double?
    var course: Int?
    var altitude: Int?
}

struct APRSMessage: Identifiable {
    let id = UUID()
    let from: String
    let to: String
    let message: String
    let timestamp: Date
}

struct APRSAnnotationView: View {
    let station: APRSStationUI
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            Circle()
                .fill(isSelected ? Color.yellow : Color.green)
                .frame(width: 12, height: 12)

            if isSelected {
                Text(station.id)
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.7))
                    .cornerRadius(3)
            }
        }
    }
}

struct APRSStationDetailView: View {
    let station: APRSStationUI

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(station.id)
                .font(.system(size: 16, weight: .bold))

            if let comment = station.comment {
                Text(comment)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            HStack {
                if let speed = station.speed {
                    Text("\(Int(speed)) mph")
                        .font(.system(size: 11))
                }
                if let altitude = station.altitude {
                    Text("\(altitude) ft")
                        .font(.system(size: 11))
                }
            }

            Text("Last: \(station.lastHeard, style: .relative)")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }
}

struct APRSMessageRow: View {
    let message: APRSMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.from)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.cyan)
                Image(systemName: "arrow.right")
                    .font(.system(size: 9))
                Text(message.to)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(message.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Text(message.message)
                .font(.system(size: 12))
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Message Log Panel

public struct MessageLogPanel: View, DecoderPanelView {
    public var title = "Decoder Log"
    public var icon = "list.bullet.rectangle"

    @State private var messages: [DecodedMessage] = []
    @State private var filterPlugin: String = "All"
    @State private var searchText = ""
    @State private var autoScroll = true

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                // Filter by plugin
                Picker("Plugin", selection: $filterPlugin) {
                    Text("All").tag("All")
                    Text("POCSAG").tag("POCSAG")
                    Text("ACARS").tag("ACARS")
                    Text("ADS-B").tag("ADS-B")
                    Text("FT8").tag("FT8")
                }
                .pickerStyle(.segmented)
                .frame(width: 300)

                Spacer()

                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 150)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .cornerRadius(6)

                Toggle(isOn: $autoScroll) {
                    Image(systemName: "arrow.down.to.line")
                }
                .toggleStyle(.button)
                .help("Auto-scroll")

                Button {
                    messages.removeAll()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
            }
            .padding(10)
            .background(.ultraThinMaterial.opacity(0.5))

            // Message list
            ScrollViewReader { proxy in
                List(filteredMessages) { message in
                    DecodedMessageRow(message: message)
                        .id(message.id)
                }
                .listStyle(.inset)
                .onChange(of: messages.count) { _, _ in
                    if autoScroll, let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var filteredMessages: [DecodedMessage] {
        messages.filter { message in
            let matchesPlugin = filterPlugin == "All" || message.plugin == filterPlugin
            let matchesSearch = searchText.isEmpty ||
                message.content.localizedCaseInsensitiveContains(searchText)
            return matchesPlugin && matchesSearch
        }
    }
}

struct DecodedMessageRow: View {
    let message: DecodedMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.plugin)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(pluginColor.opacity(0.2))
                    .foregroundColor(pluginColor)
                    .cornerRadius(4)

                if message.frequency > 0 {
                    Text(FrequencyFormatter.formatShort(message.frequency))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.cyan)
                }

                if let snr = message.snr {
                    Text(String(format: "%.1f dB", snr))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(message.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Text(message.content)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)

            if !message.metadata.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(message.metadata.keys.sorted()), id: \.self) { key in
                        Text("\(key): \(message.metadata[key] ?? "")")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var pluginColor: Color {
        switch message.plugin {
        case "POCSAG": return .orange
        case "ACARS": return .blue
        case "ADS-B": return .cyan
        case "FT8": return .green
        case "DMR": return .purple
        default: return .gray
        }
    }
}

// MARK: - Decoder Panel Container

public struct DecoderPanelContainer: View {
    @State private var selectedPanel: String = "log"

    public var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                DecoderTabButton(title: "Log", icon: "list.bullet.rectangle", id: "log", selectedId: $selectedPanel)
                DecoderTabButton(title: "ADS-B", icon: "airplane", id: "adsb", selectedId: $selectedPanel)
                DecoderTabButton(title: "APRS", icon: "location.circle", id: "aprs", selectedId: $selectedPanel)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)

            // Panel content
            Group {
                switch selectedPanel {
                case "log":
                    MessageLogPanel()
                case "adsb":
                    ADSBMapPanel()
                case "aprs":
                    APRSMapPanel()
                default:
                    MessageLogPanel()
                }
            }
        }
    }
}

struct DecoderTabButton: View {
    let title: String
    let icon: String
    let id: String
    @Binding var selectedId: String

    var body: some View {
        Button {
            selectedId = id
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 11, weight: selectedId == id ? .semibold : .regular))
            }
            .foregroundColor(selectedId == id ? .accentColor : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                if selectedId == id {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.15))
                }
            }
        }
        .buttonStyle(.plain)
    }
}
