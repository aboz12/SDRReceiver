import Foundation

/// Direct RTL-SDR bias-t control using rtl_biast command line tool
/// This bypasses SoapySDR which doesn't always expose bias-t properly
public final class RTLSDRBiasT {
    public static let shared = RTLSDRBiasT()

    public private(set) var lastResult: String = ""
    public private(set) var isEnabled: Bool = false

    private init() {}

    /// Enable or disable bias-t on RTL-SDR device
    /// - Parameters:
    ///   - enabled: true to enable bias-t (provide power), false to disable
    ///   - deviceIndex: RTL-SDR device index (default 0)
    /// - Returns: true if successful, false otherwise
    @discardableResult
    public func setBiasTee(enabled: Bool, deviceIndex: Int = 0) -> Bool {
        // Run in background to avoid blocking
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/rtl_biast")
        process.arguments = ["-d", "\(deviceIndex)", "-b", enabled ? "1" : "0"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let status = process.terminationStatus
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if status == 0 {
                isEnabled = enabled
                lastResult = "Bias-T \(enabled ? "ON" : "OFF") - OK"
                print("RTLSDRBiasT: Bias-T \(enabled ? "ENABLED" : "DISABLED") on device \(deviceIndex)")
                print("RTLSDRBiasT output: \(output)")
                return true
            } else {
                lastResult = "Failed"
                print("RTLSDRBiasT: Failed with status \(status): \(output)")
                return false
            }
        } catch {
            lastResult = "Error"
            print("RTLSDRBiasT: Failed to run rtl_biast: \(error)")
            return false
        }
    }
}
