import Foundation
import SwiftUI

/// Manages loading, enabling, and lifecycle of decoder plugins
@MainActor
public final class PluginManager: ObservableObject {
    public static let shared = PluginManager()

    @Published public private(set) var availablePlugins: [any DecoderPlugin] = []
    @Published public private(set) var enabledPlugins: Set<String> = []
    @Published public private(set) var activePlugin: (any DecoderPlugin)?
    @Published public private(set) var decodedMessages: [DecodedMessage] = []

    private var loadedBundles: [String: Bundle] = [:]
    private let maxMessages = 1000

    private init() {
        loadBundledPlugins()
    }

    /// Load all bundled plugins
    public func loadBundledPlugins() {
        // Analog modes
        register(AMPlugin())
        register(FMPlugin())
        register(WFMPlugin())
        register(SSBPlugin())
        register(CWPlugin())

        // Voice digital
        register(DMRPlugin())
        register(DStarPlugin())
        register(P25Plugin())
        register(NXDNPlugin())
        register(YSFPlugin())

        // Paging
        register(POCSAGPlugin())
        register(FLEXPlugin())

        // Aviation
        register(ADSBPlugin())
        register(ACARSPlugin())

        // Satellite
        register(InmarsatSTDCPlugin())
        register(InmarsatAEROPlugin())
        register(IridiumPlugin())

        // Amateur
        register(FT8Plugin())
        register(FT4Plugin())
        register(WSPRPlugin())
        register(PSK31Plugin())
        register(RTTYPlugin())

        // Weather
        register(NOAAAPTPlugin())
        register(MeteorLRPTPlugin())

        // Data
        register(APRSPlugin())
        register(LoRaPlugin())
    }

    /// Register a plugin
    public func register(_ plugin: any DecoderPlugin) {
        if !availablePlugins.contains(where: { $0.id == plugin.id }) {
            availablePlugins.append(plugin)
        }
    }

    /// Enable a plugin
    public func enable(_ plugin: any DecoderPlugin) {
        enabledPlugins.insert(type(of: plugin).identifier)
    }

    /// Disable a plugin
    public func disable(_ plugin: any DecoderPlugin) {
        enabledPlugins.remove(type(of: plugin).identifier)
        if activePlugin?.id == plugin.id {
            activePlugin = nil
        }
    }

    /// Activate a plugin for decoding
    public func activate(_ plugin: any DecoderPlugin) throws {
        activePlugin?.shutdown()
        try plugin.initialize()
        activePlugin = plugin
        enable(plugin)
    }

    /// Deactivate current plugin
    public func deactivate() {
        activePlugin?.shutdown()
        activePlugin = nil
    }

    /// Process samples through active plugin
    public func process(samples: [Float], sampleRate: Double) async {
        guard let plugin = activePlugin else { return }

        let messages = await plugin.process(samples: samples, sampleRate: sampleRate)

        if !messages.isEmpty {
            await MainActor.run {
                decodedMessages.insert(contentsOf: messages, at: 0)
                if decodedMessages.count > maxMessages {
                    decodedMessages.removeLast(decodedMessages.count - maxMessages)
                }
            }
        }
    }

    /// Clear decoded messages
    public func clearMessages() {
        decodedMessages.removeAll()
    }

    /// Get plugins by category
    public func plugins(in category: DecoderCategory) -> [any DecoderPlugin] {
        availablePlugins.filter { type(of: $0).category == category }
    }

    /// Find plugin by identifier
    public func plugin(withIdentifier identifier: String) -> (any DecoderPlugin)? {
        availablePlugins.first { type(of: $0).identifier == identifier }
    }
}
