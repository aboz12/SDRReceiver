import Foundation
import SwiftUI

// MARK: - Theme Colors

public struct ThemeColors: Codable {
    public var background: CodableColor
    public var surface: CodableColor
    public var primary: CodableColor
    public var secondary: CodableColor
    public var accent: CodableColor
    public var text: CodableColor
    public var textSecondary: CodableColor
    public var success: CodableColor
    public var warning: CodableColor
    public var error: CodableColor

    // Spectrum colors
    public var spectrumFill: CodableColor
    public var spectrumStroke: CodableColor
    public var spectrumGrid: CodableColor

    // Signal colors
    public var signalWeak: CodableColor
    public var signalMedium: CodableColor
    public var signalStrong: CodableColor
}

public struct CodableColor: Codable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    public init(_ color: Color) {
        // Extract components (simplified)
        self.red = 0.5
        self.green = 0.5
        self.blue = 0.5
        self.opacity = 1.0
    }

    public var color: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}

// MARK: - Theme

public struct Theme: Identifiable, Codable {
    public var id: UUID
    public var name: String
    public var isBuiltIn: Bool
    public var colors: ThemeColors
    public var fontScale: Double
    public var cornerRadius: Double
    public var glassOpacity: Double
    public var animationsEnabled: Bool
    public var waterfallColorScheme: WaterfallColorScheme

    public init(
        id: UUID = UUID(),
        name: String,
        isBuiltIn: Bool = false,
        colors: ThemeColors,
        fontScale: Double = 1.0,
        cornerRadius: Double = 12,
        glassOpacity: Double = 0.8,
        animationsEnabled: Bool = true,
        waterfallColorScheme: WaterfallColorScheme = .default
    ) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.colors = colors
        self.fontScale = fontScale
        self.cornerRadius = cornerRadius
        self.glassOpacity = glassOpacity
        self.animationsEnabled = animationsEnabled
        self.waterfallColorScheme = waterfallColorScheme
    }
}

// MARK: - Waterfall Color Schemes

public enum WaterfallColorScheme: String, Codable, CaseIterable {
    case `default` = "Default"
    case classic = "Classic"
    case plasma = "Plasma"
    case viridis = "Viridis"
    case fire = "Fire"
    case ice = "Ice"
    case greenScale = "Green Scale"
    case grayScale = "Gray Scale"

    public func colorForMagnitude(_ magnitude: Float) -> Color {
        let n = Double(max(0, min(1, (magnitude + 120) / 120)))

        switch self {
        case .default:
            return defaultWaterfallColor(n)
        case .classic:
            return classicWaterfallColor(n)
        case .plasma:
            return plasmaWaterfallColor(n)
        case .viridis:
            return viridisWaterfallColor(n)
        case .fire:
            return fireWaterfallColor(n)
        case .ice:
            return iceWaterfallColor(n)
        case .greenScale:
            return greenScaleWaterfallColor(n)
        case .grayScale:
            return grayScaleWaterfallColor(n)
        }
    }

    private func defaultWaterfallColor(_ n: Double) -> Color {
        if n < 0.15 {
            let t = n / 0.15
            return Color(red: 0, green: t * 0.1, blue: 0.05 + t * 0.35)
        } else if n < 0.3 {
            let t = (n - 0.15) / 0.15
            return Color(red: 0, green: 0.1 + t * 0.7, blue: 0.4 + t * 0.6)
        } else if n < 0.45 {
            let t = (n - 0.3) / 0.15
            return Color(red: 0, green: 0.8 + t * 0.2, blue: 1.0 - t * 0.7)
        } else if n < 0.6 {
            let t = (n - 0.45) / 0.15
            return Color(red: t, green: 1.0, blue: 0.3 - t * 0.3)
        } else if n < 0.8 {
            let t = (n - 0.6) / 0.2
            return Color(red: 1.0, green: 1.0 - t * 0.8, blue: 0)
        } else {
            let t = (n - 0.8) / 0.2
            return Color(red: 1.0, green: 0.2 + t * 0.8, blue: t)
        }
    }

    private func classicWaterfallColor(_ n: Double) -> Color {
        // Blue -> Green -> Yellow -> Red
        if n < 0.33 {
            let t = n / 0.33
            return Color(red: 0, green: t, blue: 1 - t)
        } else if n < 0.66 {
            let t = (n - 0.33) / 0.33
            return Color(red: t, green: 1, blue: 0)
        } else {
            let t = (n - 0.66) / 0.34
            return Color(red: 1, green: 1 - t, blue: 0)
        }
    }

    private func plasmaWaterfallColor(_ n: Double) -> Color {
        // Dark purple -> Purple -> Orange -> Yellow
        if n < 0.25 {
            let t = n / 0.25
            return Color(red: 0.05 + t * 0.25, green: 0, blue: 0.3 + t * 0.4)
        } else if n < 0.5 {
            let t = (n - 0.25) / 0.25
            return Color(red: 0.3 + t * 0.4, green: t * 0.2, blue: 0.7 - t * 0.3)
        } else if n < 0.75 {
            let t = (n - 0.5) / 0.25
            return Color(red: 0.7 + t * 0.3, green: 0.2 + t * 0.4, blue: 0.4 - t * 0.4)
        } else {
            let t = (n - 0.75) / 0.25
            return Color(red: 1, green: 0.6 + t * 0.4, blue: t * 0.3)
        }
    }

    private func viridisWaterfallColor(_ n: Double) -> Color {
        // Dark purple -> Blue -> Green -> Yellow
        if n < 0.25 {
            let t = n / 0.25
            return Color(red: 0.27 + t * 0.01, green: 0.0 + t * 0.21, blue: 0.33 + t * 0.21)
        } else if n < 0.5 {
            let t = (n - 0.25) / 0.25
            return Color(red: 0.28 - t * 0.06, green: 0.21 + t * 0.31, blue: 0.54 - t * 0.08)
        } else if n < 0.75 {
            let t = (n - 0.5) / 0.25
            return Color(red: 0.22 + t * 0.31, green: 0.52 + t * 0.24, blue: 0.46 - t * 0.22)
        } else {
            let t = (n - 0.75) / 0.25
            return Color(red: 0.53 + t * 0.47, green: 0.76 + t * 0.14, blue: 0.24 - t * 0.11)
        }
    }

    private func fireWaterfallColor(_ n: Double) -> Color {
        // Black -> Red -> Orange -> Yellow -> White
        if n < 0.25 {
            let t = n / 0.25
            return Color(red: t * 0.5, green: 0, blue: 0)
        } else if n < 0.5 {
            let t = (n - 0.25) / 0.25
            return Color(red: 0.5 + t * 0.5, green: t * 0.3, blue: 0)
        } else if n < 0.75 {
            let t = (n - 0.5) / 0.25
            return Color(red: 1, green: 0.3 + t * 0.7, blue: 0)
        } else {
            let t = (n - 0.75) / 0.25
            return Color(red: 1, green: 1, blue: t)
        }
    }

    private func iceWaterfallColor(_ n: Double) -> Color {
        // Black -> Dark blue -> Cyan -> White
        if n < 0.33 {
            let t = n / 0.33
            return Color(red: 0, green: 0, blue: t * 0.5)
        } else if n < 0.66 {
            let t = (n - 0.33) / 0.33
            return Color(red: 0, green: t * 0.8, blue: 0.5 + t * 0.5)
        } else {
            let t = (n - 0.66) / 0.34
            return Color(red: t, green: 0.8 + t * 0.2, blue: 1)
        }
    }

    private func greenScaleWaterfallColor(_ n: Double) -> Color {
        // Black -> Dark green -> Bright green
        return Color(red: 0, green: n, blue: n * 0.2)
    }

    private func grayScaleWaterfallColor(_ n: Double) -> Color {
        return Color(red: n, green: n, blue: n)
    }
}

// MARK: - Theme Manager

@MainActor
public final class ThemeManager: ObservableObject {
    public static let shared = ThemeManager()

    @Published public var currentTheme: Theme
    @Published public var themes: [Theme] = []

    private let saveKey = "SDRThemes"
    private let currentThemeKey = "SDRCurrentTheme"

    private init() {
        // Initialize with dark theme first
        currentTheme = ThemeManager.createDarkTheme()

        loadThemes()
        loadCurrentTheme()
    }

    // MARK: - Built-in Themes

    public static func createDarkTheme() -> Theme {
        Theme(
            name: "Dark",
            isBuiltIn: true,
            colors: ThemeColors(
                background: CodableColor(red: 0.05, green: 0.05, blue: 0.08),
                surface: CodableColor(red: 0.1, green: 0.1, blue: 0.13),
                primary: CodableColor(red: 0.0, green: 0.8, blue: 1.0),
                secondary: CodableColor(red: 0.5, green: 0.5, blue: 0.6),
                accent: CodableColor(red: 0.6, green: 0.4, blue: 1.0),
                text: CodableColor(red: 1.0, green: 1.0, blue: 1.0),
                textSecondary: CodableColor(red: 0.6, green: 0.6, blue: 0.7),
                success: CodableColor(red: 0.2, green: 0.9, blue: 0.4),
                warning: CodableColor(red: 1.0, green: 0.8, blue: 0.0),
                error: CodableColor(red: 1.0, green: 0.3, blue: 0.3),
                spectrumFill: CodableColor(red: 0.0, green: 0.6, blue: 1.0, opacity: 0.4),
                spectrumStroke: CodableColor(red: 0.0, green: 0.8, blue: 1.0),
                spectrumGrid: CodableColor(red: 0.3, green: 0.3, blue: 0.4, opacity: 0.5),
                signalWeak: CodableColor(red: 0.3, green: 0.5, blue: 1.0),
                signalMedium: CodableColor(red: 0.2, green: 0.9, blue: 0.4),
                signalStrong: CodableColor(red: 1.0, green: 0.3, blue: 0.3)
            )
        )
    }

    public static func createLightTheme() -> Theme {
        Theme(
            name: "Light",
            isBuiltIn: true,
            colors: ThemeColors(
                background: CodableColor(red: 0.95, green: 0.95, blue: 0.97),
                surface: CodableColor(red: 1.0, green: 1.0, blue: 1.0),
                primary: CodableColor(red: 0.0, green: 0.5, blue: 0.8),
                secondary: CodableColor(red: 0.4, green: 0.4, blue: 0.45),
                accent: CodableColor(red: 0.5, green: 0.3, blue: 0.9),
                text: CodableColor(red: 0.1, green: 0.1, blue: 0.1),
                textSecondary: CodableColor(red: 0.4, green: 0.4, blue: 0.45),
                success: CodableColor(red: 0.1, green: 0.7, blue: 0.3),
                warning: CodableColor(red: 0.9, green: 0.7, blue: 0.0),
                error: CodableColor(red: 0.9, green: 0.2, blue: 0.2),
                spectrumFill: CodableColor(red: 0.0, green: 0.5, blue: 0.9, opacity: 0.3),
                spectrumStroke: CodableColor(red: 0.0, green: 0.4, blue: 0.8),
                spectrumGrid: CodableColor(red: 0.7, green: 0.7, blue: 0.75, opacity: 0.5),
                signalWeak: CodableColor(red: 0.2, green: 0.4, blue: 0.9),
                signalMedium: CodableColor(red: 0.1, green: 0.7, blue: 0.3),
                signalStrong: CodableColor(red: 0.9, green: 0.2, blue: 0.2)
            ),
            glassOpacity: 0.6
        )
    }

    public static func createMidnightTheme() -> Theme {
        Theme(
            name: "Midnight",
            isBuiltIn: true,
            colors: ThemeColors(
                background: CodableColor(red: 0.0, green: 0.0, blue: 0.05),
                surface: CodableColor(red: 0.05, green: 0.05, blue: 0.1),
                primary: CodableColor(red: 0.4, green: 0.6, blue: 1.0),
                secondary: CodableColor(red: 0.3, green: 0.3, blue: 0.5),
                accent: CodableColor(red: 0.8, green: 0.4, blue: 1.0),
                text: CodableColor(red: 0.8, green: 0.85, blue: 1.0),
                textSecondary: CodableColor(red: 0.5, green: 0.5, blue: 0.7),
                success: CodableColor(red: 0.3, green: 1.0, blue: 0.5),
                warning: CodableColor(red: 1.0, green: 0.9, blue: 0.3),
                error: CodableColor(red: 1.0, green: 0.4, blue: 0.4),
                spectrumFill: CodableColor(red: 0.3, green: 0.5, blue: 1.0, opacity: 0.3),
                spectrumStroke: CodableColor(red: 0.4, green: 0.6, blue: 1.0),
                spectrumGrid: CodableColor(red: 0.2, green: 0.2, blue: 0.4, opacity: 0.5),
                signalWeak: CodableColor(red: 0.3, green: 0.4, blue: 0.8),
                signalMedium: CodableColor(red: 0.3, green: 0.9, blue: 0.5),
                signalStrong: CodableColor(red: 1.0, green: 0.4, blue: 0.4)
            ),
            waterfallColorScheme: .plasma
        )
    }

    public static func createRetroTheme() -> Theme {
        Theme(
            name: "Retro Green",
            isBuiltIn: true,
            colors: ThemeColors(
                background: CodableColor(red: 0.0, green: 0.05, blue: 0.0),
                surface: CodableColor(red: 0.0, green: 0.08, blue: 0.0),
                primary: CodableColor(red: 0.0, green: 1.0, blue: 0.3),
                secondary: CodableColor(red: 0.0, green: 0.5, blue: 0.2),
                accent: CodableColor(red: 0.3, green: 1.0, blue: 0.5),
                text: CodableColor(red: 0.0, green: 1.0, blue: 0.3),
                textSecondary: CodableColor(red: 0.0, green: 0.6, blue: 0.2),
                success: CodableColor(red: 0.0, green: 1.0, blue: 0.3),
                warning: CodableColor(red: 0.8, green: 1.0, blue: 0.0),
                error: CodableColor(red: 1.0, green: 0.3, blue: 0.0),
                spectrumFill: CodableColor(red: 0.0, green: 0.8, blue: 0.2, opacity: 0.4),
                spectrumStroke: CodableColor(red: 0.0, green: 1.0, blue: 0.3),
                spectrumGrid: CodableColor(red: 0.0, green: 0.3, blue: 0.1, opacity: 0.5),
                signalWeak: CodableColor(red: 0.0, green: 0.4, blue: 0.1),
                signalMedium: CodableColor(red: 0.0, green: 0.7, blue: 0.2),
                signalStrong: CodableColor(red: 0.0, green: 1.0, blue: 0.3)
            ),
            waterfallColorScheme: .greenScale
        )
    }

    // MARK: - Theme Management

    public func setTheme(_ theme: Theme) {
        currentTheme = theme
        saveCurrentTheme()
    }

    public func createTheme(name: String, baseTheme: Theme) -> Theme {
        var newTheme = baseTheme
        newTheme.id = UUID()
        newTheme.name = name
        newTheme.isBuiltIn = false
        themes.append(newTheme)
        saveThemes()
        return newTheme
    }

    public func updateTheme(_ theme: Theme) {
        if let index = themes.firstIndex(where: { $0.id == theme.id }) {
            themes[index] = theme
            if currentTheme.id == theme.id {
                currentTheme = theme
            }
            saveThemes()
            saveCurrentTheme()
        }
    }

    public func deleteTheme(_ theme: Theme) {
        guard !theme.isBuiltIn else { return }
        themes.removeAll { $0.id == theme.id }
        if currentTheme.id == theme.id {
            currentTheme = themes.first ?? ThemeManager.createDarkTheme()
        }
        saveThemes()
    }

    // MARK: - Persistence

    private func saveThemes() {
        let customThemes = themes.filter { !$0.isBuiltIn }
        if let data = try? JSONEncoder().encode(customThemes) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    private func loadThemes() {
        // Always include built-in themes
        themes = [
            ThemeManager.createDarkTheme(),
            ThemeManager.createLightTheme(),
            ThemeManager.createMidnightTheme(),
            ThemeManager.createRetroTheme()
        ]

        // Load custom themes
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let customThemes = try? JSONDecoder().decode([Theme].self, from: data) {
            themes.append(contentsOf: customThemes)
        }
    }

    private func saveCurrentTheme() {
        if let data = try? JSONEncoder().encode(currentTheme.id) {
            UserDefaults.standard.set(data, forKey: currentThemeKey)
        }
    }

    private func loadCurrentTheme() {
        if let data = UserDefaults.standard.data(forKey: currentThemeKey),
           let themeId = try? JSONDecoder().decode(UUID.self, from: data),
           let theme = themes.first(where: { $0.id == themeId }) {
            currentTheme = theme
        }
    }
}

// MARK: - Theme Settings View

public struct ThemeSettingsView: View {
    @ObservedObject var themeManager = ThemeManager.shared

    @State private var showingCreateTheme = false
    @State private var newThemeName = ""

    public var body: some View {
        Form {
            Section("Theme") {
                Picker("Current Theme", selection: $themeManager.currentTheme.id) {
                    ForEach(themeManager.themes) { theme in
                        HStack {
                            Circle()
                                .fill(theme.colors.primary.color)
                                .frame(width: 12, height: 12)
                            Text(theme.name)
                        }
                        .tag(theme.id)
                    }
                }
                .onChange(of: themeManager.currentTheme.id) { _, newId in
                    if let theme = themeManager.themes.first(where: { $0.id == newId }) {
                        themeManager.setTheme(theme)
                    }
                }

                Button("Create Custom Theme") {
                    showingCreateTheme = true
                }
            }

            Section("Waterfall Colors") {
                Picker("Color Scheme", selection: $themeManager.currentTheme.waterfallColorScheme) {
                    ForEach(WaterfallColorScheme.allCases, id: \.self) { scheme in
                        Text(scheme.rawValue).tag(scheme)
                    }
                }
                .onChange(of: themeManager.currentTheme.waterfallColorScheme) { _, _ in
                    themeManager.updateTheme(themeManager.currentTheme)
                }

                // Preview
                WaterfallPreview(colorScheme: themeManager.currentTheme.waterfallColorScheme)
                    .frame(height: 60)
                    .cornerRadius(8)
            }

            Section("Appearance") {
                HStack {
                    Text("Glass Opacity")
                    Slider(value: $themeManager.currentTheme.glassOpacity, in: 0.3...1.0)
                    Text(String(format: "%.0f%%", themeManager.currentTheme.glassOpacity * 100))
                        .frame(width: 45)
                }
                .onChange(of: themeManager.currentTheme.glassOpacity) { _, _ in
                    themeManager.updateTheme(themeManager.currentTheme)
                }

                HStack {
                    Text("Corner Radius")
                    Slider(value: $themeManager.currentTheme.cornerRadius, in: 0...24)
                    Text(String(format: "%.0f", themeManager.currentTheme.cornerRadius))
                        .frame(width: 30)
                }
                .onChange(of: themeManager.currentTheme.cornerRadius) { _, _ in
                    themeManager.updateTheme(themeManager.currentTheme)
                }

                Toggle("Animations", isOn: $themeManager.currentTheme.animationsEnabled)
                    .onChange(of: themeManager.currentTheme.animationsEnabled) { _, _ in
                        themeManager.updateTheme(themeManager.currentTheme)
                    }
            }

            Section("Custom Themes") {
                ForEach(themeManager.themes.filter { !$0.isBuiltIn }) { theme in
                    HStack {
                        Circle()
                            .fill(theme.colors.primary.color)
                            .frame(width: 16, height: 16)
                        Text(theme.name)
                        Spacer()
                        Button(role: .destructive) {
                            themeManager.deleteTheme(theme)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(isPresented: $showingCreateTheme) {
            VStack(spacing: 20) {
                Text("Create Theme")
                    .font(.headline)

                TextField("Theme Name", text: $newThemeName)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Cancel") {
                        showingCreateTheme = false
                        newThemeName = ""
                    }
                    .buttonStyle(.bordered)

                    Button("Create") {
                        _ = themeManager.createTheme(name: newThemeName, baseTheme: themeManager.currentTheme)
                        showingCreateTheme = false
                        newThemeName = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newThemeName.isEmpty)
                }
            }
            .padding(30)
            .frame(width: 300)
        }
    }
}

struct WaterfallPreview: View {
    let colorScheme: WaterfallColorScheme

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(0..<100, id: \.self) { i in
                    let magnitude = Float(i) / 100.0 * 120 - 120
                    Rectangle()
                        .fill(colorScheme.colorForMagnitude(magnitude))
                }
            }
        }
    }
}
