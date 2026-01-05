import SwiftUI

// MARK: - Liquid Glass Design System

/// A modern "liquid glass" visual effect panel with blur, tint, and subtle animations
public struct GlassPanel<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = 16
    var opacity: Double = 0.7
    var tintColor: Color = .white
    var borderWidth: CGFloat = 0.5
    var shadowRadius: CGFloat = 10

    public init(
        cornerRadius: CGFloat = 16,
        opacity: Double = 0.7,
        tintColor: Color = .white,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.opacity = opacity
        self.tintColor = tintColor
        self.content = content()
    }

    public var body: some View {
        content
            .background {
                ZStack {
                    // Base blur layer
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)

                    // Gradient overlay for depth
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [
                                    tintColor.opacity(0.15),
                                    tintColor.opacity(0.05),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // Inner highlight
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.4),
                                    .white.opacity(0.1),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: borderWidth
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.2), radius: shadowRadius, x: 0, y: 5)
    }
}

/// Frosted glass card with subtle animation
public struct GlassCard<Content: View>: View {
    let content: Content
    var isHighlighted: Bool = false

    @State private var isHovered = false

    public init(isHighlighted: Bool = false, @ViewBuilder content: () -> Content) {
        self.isHighlighted = isHighlighted
        self.content = content()
    }

    public var body: some View {
        content
            .padding()
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)

                    // Animated gradient on hover
                    if isHovered || isHighlighted {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.accentColor.opacity(0.2),
                                        Color.accentColor.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }

                    // Border
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(isHovered ? 0.5 : 0.3),
                                    .white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }
            }
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

/// Glass button with liquid effect
public struct GlassButton: View {
    let title: String
    let icon: String?
    let action: () -> Void
    var isActive: Bool = false
    var tint: Color = .accentColor

    @State private var isPressed = false
    @State private var isHovered = false

    public init(
        _ title: String,
        icon: String? = nil,
        isActive: Bool = false,
        tint: Color = .accentColor,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isActive = isActive
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(isActive ? .white : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background {
                ZStack {
                    // Background
                    Capsule()
                        .fill(isActive ? tint : Color.clear)

                    // Glass effect when not active
                    if !isActive {
                        Capsule()
                            .fill(.ultraThinMaterial)
                    }

                    // Hover/Press effect
                    if isHovered && !isActive {
                        Capsule()
                            .fill(tint.opacity(0.15))
                    }

                    // Border
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(isActive ? 0.4 : 0.3),
                                    .white.opacity(0.1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                }
            }
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// Glass slider control
public struct GlassSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String
    var icon: String? = nil
    var unit: String = ""
    var tint: Color = .accentColor

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let icon = icon {
                    Image(systemName: icon)
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(value))\(unit)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track background
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .frame(height: 6)

                    // Track border
                    Capsule()
                        .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                        .frame(height: 6)

                    // Fill
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.8), tint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth(in: geometry.size.width), height: 6)

                    // Thumb
                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
                        .offset(x: thumbOffset(in: geometry.size.width))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { gesture in
                                    let fraction = gesture.location.x / geometry.size.width
                                    let newValue = range.lowerBound + Double(fraction) * (range.upperBound - range.lowerBound)
                                    value = min(max(newValue, range.lowerBound), range.upperBound)
                                }
                        )
                }
            }
            .frame(height: 16)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial.opacity(0.5))
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        }
    }

    private func fillWidth(in totalWidth: CGFloat) -> CGFloat {
        let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return CGFloat(fraction) * totalWidth
    }

    private func thumbOffset(in totalWidth: CGFloat) -> CGFloat {
        let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return CGFloat(fraction) * totalWidth - 8
    }
}

/// Glass toggle switch
public struct GlassToggle: View {
    @Binding var isOn: Bool
    let label: String
    var icon: String? = nil

    public var body: some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
            }
            Text(label)
                .font(.system(size: 13, weight: .medium))

            Spacer()

            // Custom toggle
            ZStack {
                Capsule()
                    .fill(isOn ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: 44, height: 24)

                Capsule()
                    .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                    .frame(width: 44, height: 24)

                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                    .offset(x: isOn ? 10 : -10)
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isOn.toggle()
                }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial.opacity(0.5))
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        }
    }
}

/// Glass segmented picker
public struct GlassSegmentedPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String, String?)]  // (value, label, icon)
    var tint: Color = .accentColor

    public init(
        selection: Binding<T>,
        options: [(T, String, String?)],
        tint: Color = .accentColor
    ) {
        self._selection = selection
        self.options = options
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isSelected = selection == option.0

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selection = option.0
                    }
                } label: {
                    HStack(spacing: 4) {
                        if let icon = option.2 {
                            Image(systemName: icon)
                                .font(.system(size: 12))
                        }
                        Text(option.1)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(isSelected ? .white : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(tint)
                                .shadow(color: tint.opacity(0.4), radius: 4, x: 0, y: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
        }
    }
}

/// Animated liquid glass background
public struct LiquidGlassBackground: View {
    @State private var animate = false

    var primaryColor: Color = .blue
    var secondaryColor: Color = .purple

    public var body: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                colors: [
                    Color(white: 0.05),
                    Color(white: 0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Animated blobs
            GeometryReader { geometry in
                ZStack {
                    // Blob 1
                    Circle()
                        .fill(primaryColor.opacity(0.3))
                        .frame(width: geometry.size.width * 0.8)
                        .blur(radius: 80)
                        .offset(
                            x: animate ? geometry.size.width * 0.2 : -geometry.size.width * 0.2,
                            y: animate ? -geometry.size.height * 0.1 : geometry.size.height * 0.2
                        )

                    // Blob 2
                    Circle()
                        .fill(secondaryColor.opacity(0.25))
                        .frame(width: geometry.size.width * 0.6)
                        .blur(radius: 60)
                        .offset(
                            x: animate ? -geometry.size.width * 0.3 : geometry.size.width * 0.1,
                            y: animate ? geometry.size.height * 0.3 : -geometry.size.height * 0.2
                        )

                    // Blob 3
                    Circle()
                        .fill(Color.cyan.opacity(0.2))
                        .frame(width: geometry.size.width * 0.5)
                        .blur(radius: 50)
                        .offset(
                            x: animate ? geometry.size.width * 0.1 : -geometry.size.width * 0.15,
                            y: animate ? geometry.size.height * 0.1 : geometry.size.height * 0.35
                        )
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

/// Glass frequency display (static version)
public struct GlassFrequencyDisplay: View {
    let frequency: Double
    var tint: Color = .cyan

    private var formattedFrequency: String {
        if frequency >= 1_000_000_000 {
            return String(format: "%.6f GHz", frequency / 1_000_000_000)
        } else if frequency >= 1_000_000 {
            return String(format: "%.6f MHz", frequency / 1_000_000)
        } else if frequency >= 1_000 {
            return String(format: "%.3f kHz", frequency / 1_000)
        }
        return String(format: "%.0f Hz", frequency)
    }

    public var body: some View {
        Text(formattedFrequency)
            .font(.system(size: 36, weight: .light, design: .monospaced))
            .foregroundStyle(
                LinearGradient(
                    colors: [tint, tint.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: tint.opacity(0.5), radius: 10, x: 0, y: 0)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.black.opacity(0.4))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [tint.opacity(0.5), tint.opacity(0.1)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
            }
    }
}

// MARK: - Interactive Frequency Display with Digit Scroll

/// Interactive frequency display - click on digit and scroll to tune
public struct InteractiveFrequencyDisplay: View {
    @Binding var frequency: Double
    var tint: Color = .cyan
    var onBookmark: (() -> Void)? = nil

    @State private var selectedDigitIndex: Int? = nil
    @State private var isHovered = false
    @State private var showBookmarkConfirm = false

    // Digit positions: GHz, 100MHz, 10MHz, 1MHz, 100kHz, 10kHz, 1kHz, 100Hz, 10Hz, 1Hz
    private let digitMultipliers: [Double] = [
        1_000_000_000,  // GHz
        100_000_000,    // 100 MHz
        10_000_000,     // 10 MHz
        1_000_000,      // 1 MHz
        100_000,        // 100 kHz
        10_000,         // 10 kHz
        1_000,          // 1 kHz
        100,            // 100 Hz
        10,             // 10 Hz
        1               // 1 Hz
    ]

    private var frequencyDigits: [String] {
        let freqHz = Int(frequency)
        let formatted = String(format: "%010d", freqHz)
        return formatted.map { String($0) }
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Bookmark button
            Button {
                onBookmark?()
                showBookmarkConfirm = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    showBookmarkConfirm = false
                }
            } label: {
                Image(systemName: showBookmarkConfirm ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 18))
                    .foregroundColor(showBookmarkConfirm ? .yellow : .secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("Bookmark this frequency")

            // Frequency digits
            HStack(spacing: 0) {
                ForEach(Array(frequencyDigits.enumerated()), id: \.offset) { index, digit in
                    DigitView(
                        digit: digit,
                        isSelected: selectedDigitIndex == index,
                        tint: tint,
                        position: digitPosition(for: index)
                    )
                    .onTapGesture {
                        selectedDigitIndex = (selectedDigitIndex == index) ? nil : index
                    }
                    .onHover { hovering in
                        if hovering && selectedDigitIndex == nil {
                            // Visual feedback on hover
                        }
                    }
                    .onScrollWheel { delta in
                        if selectedDigitIndex == index {
                            adjustFrequency(digitIndex: index, delta: delta)
                        }
                    }

                    // Add separators
                    if index == 0 {
                        Text(".")
                            .font(.system(size: 28, weight: .light, design: .monospaced))
                            .foregroundColor(tint.opacity(0.5))
                    } else if index == 3 {
                        Text(".")
                            .font(.system(size: 28, weight: .light, design: .monospaced))
                            .foregroundColor(tint.opacity(0.5))
                    } else if index == 6 {
                        Text(".")
                            .font(.system(size: 28, weight: .light, design: .monospaced))
                            .foregroundColor(tint.opacity(0.3))
                    }
                }

                // Unit label
                Text(" GHz")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.4))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            LinearGradient(
                                colors: [tint.opacity(0.5), tint.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
        }
        .onTapGesture {
            // Clicking outside digits deselects
        }
    }

    private func digitPosition(for index: Int) -> String {
        switch index {
        case 0: return "GHz"
        case 1: return "100M"
        case 2: return "10M"
        case 3: return "1M"
        case 4: return "100k"
        case 5: return "10k"
        case 6: return "1k"
        case 7: return "100"
        case 8: return "10"
        case 9: return "1"
        default: return ""
        }
    }

    private func adjustFrequency(digitIndex: Int, delta: CGFloat) {
        guard digitIndex < digitMultipliers.count else { return }
        let multiplier = digitMultipliers[digitIndex]
        let step = delta > 0 ? multiplier : -multiplier
        let newFreq = frequency + step

        // Clamp to valid range (1 Hz to 6 GHz)
        frequency = max(1, min(6_000_000_000, newFreq))
    }
}

/// Single digit view for frequency display
struct DigitView: View {
    let digit: String
    let isSelected: Bool
    var tint: Color = .cyan
    let position: String

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 2) {
            // Up arrow (visible when selected)
            if isSelected {
                Image(systemName: "chevron.up")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(tint)
            } else {
                Color.clear.frame(height: 10)
            }

            // Digit
            Text(digit)
                .font(.system(size: 32, weight: isSelected ? .medium : .light, design: .monospaced))
                .foregroundStyle(
                    LinearGradient(
                        colors: isSelected ? [.white, tint] : [tint, tint.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: isSelected ? tint : tint.opacity(0.3), radius: isSelected ? 8 : 4)
                .frame(width: 24)
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(tint.opacity(0.2))
                            .strokeBorder(tint.opacity(0.5), lineWidth: 1)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(tint.opacity(0.1))
                    }
                }

            // Down arrow (visible when selected)
            if isSelected {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(tint)
            } else {
                Color.clear.frame(height: 10)
            }

            // Position label (visible when selected or hovered)
            if isSelected || isHovered {
                Text(position)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)
            } else {
                Color.clear.frame(height: 10)
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

/// Scroll wheel event modifier
struct ScrollWheelModifier: ViewModifier {
    let onScroll: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content.background {
            ScrollWheelReceiver(onScroll: onScroll)
        }
    }
}

struct ScrollWheelReceiver: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let view = ScrollWheelNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onScroll = onScroll
    }
}

class ScrollWheelNSView: NSView {
    var onScroll: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        let delta = event.deltaY
        if abs(delta) > 0.1 {
            onScroll?(delta)
        }
    }
}

extension View {
    func onScrollWheel(_ action: @escaping (CGFloat) -> Void) -> some View {
        modifier(ScrollWheelModifier(onScroll: action))
    }
}

// MARK: - Quick Bookmark Manager

@MainActor
public final class QuickBookmarkManager: ObservableObject {
    public static let shared = QuickBookmarkManager()

    @Published public var bookmarks: [QuickBookmark] = []

    private let saveKey = "QuickBookmarks"
    private let maxBookmarks = 20

    private init() {
        loadBookmarks()
    }

    public func addBookmark(frequency: Double, mode: String = "FM", label: String? = nil) {
        let bookmark = QuickBookmark(
            frequency: frequency,
            mode: mode,
            label: label ?? FrequencyFormatter.format(frequency)
        )

        // Remove duplicate if exists
        bookmarks.removeAll { abs($0.frequency - frequency) < 100 }

        // Add to front
        bookmarks.insert(bookmark, at: 0)

        // Limit count
        if bookmarks.count > maxBookmarks {
            bookmarks.removeLast()
        }

        saveBookmarks()
    }

    public func removeBookmark(_ bookmark: QuickBookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        saveBookmarks()
    }

    public func updateLabel(for bookmark: QuickBookmark, newLabel: String) {
        if let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks[index].label = newLabel
            saveBookmarks()
        }
    }

    private func saveBookmarks() {
        if let encoded = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }

    private func loadBookmarks() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([QuickBookmark].self, from: data) {
            bookmarks = decoded
        }
    }
}

public struct QuickBookmark: Identifiable, Codable, Hashable {
    public let id: UUID
    public let frequency: Double
    public let mode: String
    public var label: String
    public let timestamp: Date

    public init(frequency: Double, mode: String, label: String) {
        self.id = UUID()
        self.frequency = frequency
        self.mode = mode
        self.label = label
        self.timestamp = Date()
    }

    public var formattedFrequency: String {
        FrequencyFormatter.format(frequency)
    }
}

// MARK: - Quick Bookmark Bar

public struct QuickBookmarkBar: View {
    @ObservedObject var manager = QuickBookmarkManager.shared
    var onSelect: (QuickBookmark) -> Void
    var tint: Color = .cyan

    @State private var editingBookmark: QuickBookmark? = nil
    @State private var editLabel = ""

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(manager.bookmarks) { bookmark in
                    BookmarkChip(
                        bookmark: bookmark,
                        tint: tint,
                        onTap: { onSelect(bookmark) },
                        onEdit: {
                            editingBookmark = bookmark
                            editLabel = bookmark.label
                        },
                        onDelete: { manager.removeBookmark(bookmark) }
                    )
                }

                if manager.bookmarks.isEmpty {
                    Text("No bookmarks yet. Click the bookmark icon to save frequencies.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(height: 44)
        .background(.ultraThinMaterial.opacity(0.5))
        .sheet(item: $editingBookmark) { bookmark in
            VStack(spacing: 16) {
                Text("Edit Bookmark")
                    .font(.headline)

                Text(bookmark.formattedFrequency)
                    .font(.system(size: 18, design: .monospaced))
                    .foregroundColor(tint)

                TextField("Label", text: $editLabel)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)

                HStack(spacing: 16) {
                    Button("Cancel") {
                        editingBookmark = nil
                    }

                    Button("Save") {
                        manager.updateLabel(for: bookmark, newLabel: editLabel)
                        editingBookmark = nil
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            .frame(width: 280)
        }
    }
}

struct BookmarkChip: View {
    let bookmark: QuickBookmark
    var tint: Color = .cyan
    var onTap: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(bookmark.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(bookmark.formattedFrequency)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(tint)
            }

            if isHovered {
                HStack(spacing: 4) {
                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                    }
                    .buttonStyle(.plain)

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
                if isHovered {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tint.opacity(0.2))
                }
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(tint.opacity(isHovered ? 0.5 : 0.2), lineWidth: 0.5)
            }
        }
        .onTapGesture {
            onTap()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("Edit Label", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

/// Signal strength meter with glass effect
public struct GlassSignalMeter: View {
    let level: Float  // 0 to 1
    let dB: Float     // Actual dB value
    var tint: Color = .green

    public var body: some View {
        VStack(spacing: 4) {
            // Meter bars
            HStack(spacing: 2) {
                ForEach(0..<20, id: \.self) { index in
                    let threshold = Float(index) / 20.0
                    let isActive = level > threshold
                    let barColor: Color = {
                        if index < 12 { return .green }
                        if index < 16 { return .yellow }
                        return .red
                    }()

                    RoundedRectangle(cornerRadius: 2)
                        .fill(isActive ? barColor : Color.gray.opacity(0.2))
                        .frame(width: 6, height: CGFloat(8 + index))
                }
            }
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.black.opacity(0.4))
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            }

            // dB value
            Text("\(Int(dB)) dB")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
}
