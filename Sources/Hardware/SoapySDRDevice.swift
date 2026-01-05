import Foundation
import SoapySDRShim

/// SoapySDR device implementation
public final class SoapySDRDeviceWrapper: SDRDevice {
    public let id: String
    public let name: String
    public let driver: String
    public private(set) var capabilities: DeviceCapabilities

    private var device: OpaquePointer?
    private var stream: OpaquePointer?
    private var streamTask: Task<Void, Never>?
    private let streamContinuation: AsyncStream<IQSampleBuffer>.Continuation?
    private let _sampleStream: AsyncStream<IQSampleBuffer>

    private var _centerFrequency: Double = 1_545_600_000
    private var _sampleRate: Double = 2_400_000
    private var _bandwidth: Double = 2_400_000
    private var _gain: Double = 30
    private var _gainMode: GainMode = .manual
    private var _antenna: String = "RX"
    private var _dcOffsetCorrection: Bool = true
    private var _iqBalanceCorrection: Bool = false
    private var _ppmCorrection: Double = 0
    private var _biasTee: Bool = false
    private var _isStreaming: Bool = false

    public var isConnected: Bool { device != nil }
    public var isStreaming: Bool { _isStreaming }

    public var centerFrequency: Double {
        get { _centerFrequency }
        set {
            _centerFrequency = newValue
            applyFrequency()
        }
    }

    public var sampleRate: Double {
        get { _sampleRate }
        set {
            _sampleRate = newValue
            applySampleRate()
        }
    }

    public var bandwidth: Double {
        get { _bandwidth }
        set {
            _bandwidth = newValue
            applyBandwidth()
        }
    }

    public var gain: Double {
        get { _gain }
        set {
            _gain = newValue
            applyGain()
        }
    }

    public var gainMode: GainMode {
        get { _gainMode }
        set {
            _gainMode = newValue
            applyGainMode()
        }
    }

    public var antenna: String {
        get { _antenna }
        set {
            _antenna = newValue
            applyAntenna()
        }
    }

    public var dcOffsetCorrection: Bool {
        get { _dcOffsetCorrection }
        set {
            _dcOffsetCorrection = newValue
            applyDCOffset()
        }
    }

    public var iqBalanceCorrection: Bool {
        get { _iqBalanceCorrection }
        set {
            _iqBalanceCorrection = newValue
        }
    }

    public var ppmCorrection: Double {
        get { _ppmCorrection }
        set {
            _ppmCorrection = newValue
            applyPPMCorrection()
        }
    }

    public var biasTee: Bool {
        get { _biasTee }
        set {
            _biasTee = newValue
            applyBiasTee()
        }
    }

    public var sampleStream: AsyncStream<IQSampleBuffer> {
        _sampleStream
    }

    /// Initialize with device arguments
    public init?(args: [String: String] = [:]) {
        // Create sample stream using makeStream for proper continuation capture
        let (stream, continuation) = AsyncStream<IQSampleBuffer>.makeStream()
        _sampleStream = stream
        self.streamContinuation = continuation

        // Build args string
        var argsKwargs = SoapySDRKwargs()
        for (key, value) in args {
            key.withCString { keyPtr in
                value.withCString { valuePtr in
                    SoapySDRKwargs_set(&argsKwargs, keyPtr, valuePtr)
                }
            }
        }

        // Open device
        device = SoapySDRDevice_make(&argsKwargs)
        SoapySDRKwargs_clear(&argsKwargs)

        guard device != nil else {
            self.id = ""
            self.name = ""
            self.driver = ""
            self.capabilities = DeviceCapabilities()
            return nil
        }

        // Get device info
        self.driver = String(cString: SoapySDRDevice_getDriverKey(device))
        self.name = String(cString: SoapySDRDevice_getHardwareKey(device))
        self.id = "\(driver)_\(name)"

        // Initialize capabilities with default (will be updated below)
        self.capabilities = DeviceCapabilities()

        // Query actual capabilities
        self.capabilities = queryCapabilities()

        // Apply initial settings
        applyFrequency()
        applySampleRate()
        applyBandwidth()
        applyGain()
        applyGainMode()
    }

    deinit {
        close()
    }

    private func queryCapabilities() -> DeviceCapabilities {
        guard let dev = device else { return DeviceCapabilities() }

        // Get frequency range
        var freqRangeLen: Int = 0
        let freqRanges = SoapySDRDevice_getFrequencyRange(dev, SOAPY_SDR_RX, 0, &freqRangeLen)
        var minFreq: Double = 24_000_000
        var maxFreq: Double = 1_700_000_000
        if freqRangeLen > 0, let ranges = freqRanges {
            minFreq = ranges[0].minimum
            maxFreq = ranges[0].maximum
        }

        // Get sample rate range
        var rateRangeLen: Int = 0
        let rateRanges = SoapySDRDevice_getSampleRateRange(dev, SOAPY_SDR_RX, 0, &rateRangeLen)
        var minRate: Double = 225_001
        var maxRate: Double = 3_200_000
        if rateRangeLen > 0, let ranges = rateRanges {
            minRate = ranges[0].minimum
            maxRate = ranges[0].maximum
        }

        // Get gain range
        var gainRangePtr = SoapySDRDevice_getGainRange(dev, SOAPY_SDR_RX, 0)
        let minGain = gainRangePtr.minimum
        let maxGain = gainRangePtr.maximum

        // Get antennas
        var antennaLen: Int = 0
        let antennaList = SoapySDRDevice_listAntennas(dev, SOAPY_SDR_RX, 0, &antennaLen)
        var antennas: [String] = []
        if antennaLen > 0, let list = antennaList {
            for i in 0..<antennaLen {
                if let ant = list[i] {
                    antennas.append(String(cString: ant))
                }
            }
        }

        return DeviceCapabilities(
            frequencyRange: minFreq...maxFreq,
            sampleRateRange: minRate...maxRate,
            bandwidthRange: 0...maxRate,
            gainRange: minGain...maxGain,
            supportedAntennas: antennas.isEmpty ? ["RX"] : antennas,
            hasDCOffsetCorrection: SoapySDRDevice_hasDCOffsetMode(dev, SOAPY_SDR_RX, 0),
            hasIQBalanceCorrection: SoapySDRDevice_hasIQBalanceMode(dev, SOAPY_SDR_RX, 0),
            hasHardwareAGC: SoapySDRDevice_hasGainMode(dev, SOAPY_SDR_RX, 0),
            maxBandwidth: maxRate,
            supportsTransmit: false,  // Would need to check TX channels
            nativeFormat: .complexFloat32
        )
    }

    // MARK: - Apply Settings

    private func applyFrequency() {
        guard let dev = device else { return }
        SoapySDRDevice_setFrequency(dev, SOAPY_SDR_RX, 0, _centerFrequency, nil)
    }

    private func applySampleRate() {
        guard let dev = device else { return }
        SoapySDRDevice_setSampleRate(dev, SOAPY_SDR_RX, 0, _sampleRate)
    }

    private func applyBandwidth() {
        guard let dev = device else { return }
        SoapySDRDevice_setBandwidth(dev, SOAPY_SDR_RX, 0, _bandwidth)
    }

    private func applyGain() {
        guard let dev = device else { return }
        SoapySDRDevice_setGain(dev, SOAPY_SDR_RX, 0, _gain)
    }

    private func applyGainMode() {
        guard let dev = device else { return }
        SoapySDRDevice_setGainMode(dev, SOAPY_SDR_RX, 0, _gainMode == .automatic)
    }

    private func applyAntenna() {
        guard let dev = device else { return }
        _antenna.withCString { antPtr in
            SoapySDRDevice_setAntenna(dev, SOAPY_SDR_RX, 0, antPtr)
        }
    }

    private func applyDCOffset() {
        guard let dev = device else { return }
        SoapySDRDevice_setDCOffsetMode(dev, SOAPY_SDR_RX, 0, _dcOffsetCorrection)
    }

    private func applyPPMCorrection() {
        guard let dev = device else { return }
        SoapySDRDevice_setFrequencyCorrection(dev, SOAPY_SDR_RX, 0, _ppmCorrection)
    }

    private func applyBiasTee() {
        guard let dev = device else { return }
        // Bias-T is controlled via device settings
        // Try multiple setting names for compatibility across drivers
        let value = _biasTee ? "true" : "false"
        let value1 = _biasTee ? "1" : "0"

        // RTL-SDR Blog V4 and SoapyRTLSDR use "biastee"
        "biastee".withCString { keyPtr in
            value.withCString { valuePtr in
                SoapySDRDevice_writeSetting(dev, keyPtr, valuePtr)
            }
        }

        // Try with numeric value
        "biastee".withCString { keyPtr in
            value1.withCString { valuePtr in
                SoapySDRDevice_writeSetting(dev, keyPtr, valuePtr)
            }
        }

        // Also try "bias_tee" for compatibility
        "bias_tee".withCString { keyPtr in
            value.withCString { valuePtr in
                SoapySDRDevice_writeSetting(dev, keyPtr, valuePtr)
            }
        }

        // Try direct GPIO for RTL-SDR (GPIO 0 controls bias-t on V3/V4)
        "direct_samp".withCString { keyPtr in
            "0".withCString { valuePtr in
                // Ensure direct sampling is off
                SoapySDRDevice_writeSetting(dev, keyPtr, valuePtr)
            }
        }
    }

    // MARK: - Streaming

    public func startStreaming() throws {
        guard let dev = device else {
            throw SDRDeviceError.connectionFailed("Device not connected")
        }

        // Setup stream
        var channels: [Int] = [0]
        stream = channels.withUnsafeMutableBufferPointer { channelPtr in
            "CF32".withCString { formatPtr in
                SoapySDRDevice_setupStream(dev, SOAPY_SDR_RX, formatPtr, channelPtr.baseAddress, 1, nil)
            }
        }

        guard stream != nil else {
            throw SDRDeviceError.streamingFailed("Failed to setup stream")
        }

        // Activate stream
        let result = SoapySDRDevice_activateStream(dev, stream, 0, 0, 0)
        guard result == 0 else {
            throw SDRDeviceError.streamingFailed("Failed to activate stream: \(result)")
        }

        _isStreaming = true

        // Start background reading task
        streamTask = Task { [weak self] in
            await self?.streamLoop()
        }
    }

    private func streamLoop() async {
        guard let dev = device, let strm = stream else { return }

        let bufferSize = 65536
        var buffer = [Float](repeating: 0, count: bufferSize * 2)  // I/Q interleaved
        var flags: Int32 = 0
        var timeNs: Int64 = 0

        while !Task.isCancelled && _isStreaming {
            let samplesRead = buffer.withUnsafeMutableBufferPointer { bufPtr in
                var buffers: [UnsafeMutableRawPointer?] = [UnsafeMutableRawPointer(bufPtr.baseAddress)]
                return buffers.withUnsafeMutableBufferPointer { buffersPtr in
                    SoapySDRDevice_readStream(dev, strm, buffersPtr.baseAddress, bufferSize, &flags, &timeNs, 100000)
                }
            }

            if samplesRead > 0 {
                // Convert interleaved floats to ComplexFloat
                let count = Int(samplesRead)
                var complexSamples = [ComplexFloat](repeating: ComplexFloat(), count: count)
                for i in 0..<count {
                    complexSamples[i] = ComplexFloat(
                        real: buffer[i * 2],
                        imag: buffer[i * 2 + 1]
                    )
                }

                let iqBuffer = IQSampleBuffer(
                    samples: complexSamples,
                    timestamp: UInt64(timeNs),
                    centerFrequency: _centerFrequency,
                    sampleRate: _sampleRate,
                    overflowDetected: (flags & Int32(SOAPY_SDR_OVERFLOW)) != 0
                )

                streamContinuation?.yield(iqBuffer)
            }

            // Small yield to prevent tight loop
            await Task.yield()
        }
    }

    public func stopStreaming() {
        _isStreaming = false
        streamTask?.cancel()
        streamTask = nil

        if let dev = device, let strm = stream {
            SoapySDRDevice_deactivateStream(dev, strm, 0, 0)
            SoapySDRDevice_closeStream(dev, strm)
        }
        stream = nil
    }

    public func readSamples(into buffer: UnsafeMutablePointer<ComplexFloat>, count: Int) -> Int {
        guard let dev = device, let strm = stream else { return 0 }

        var flags: Int32 = 0
        var timeNs: Int64 = 0

        // Read into temporary float buffer (interleaved I/Q)
        var floatBuffer = [Float](repeating: 0, count: count * 2)
        let samplesRead = floatBuffer.withUnsafeMutableBufferPointer { bufPtr in
            var buffers: [UnsafeMutableRawPointer?] = [UnsafeMutableRawPointer(bufPtr.baseAddress)]
            return buffers.withUnsafeMutableBufferPointer { buffersPtr in
                SoapySDRDevice_readStream(dev, strm, buffersPtr.baseAddress, count, &flags, &timeNs, 100000)
            }
        }

        // Convert to ComplexFloat
        if samplesRead > 0 {
            let count = Int(samplesRead)
            for i in 0..<count {
                buffer[i] = ComplexFloat(
                    real: floatBuffer[i * 2],
                    imag: floatBuffer[i * 2 + 1]
                )
            }
        }

        return max(0, Int(samplesRead))
    }

    public func close() {
        stopStreaming()
        streamContinuation?.finish()

        if let dev = device {
            SoapySDRDevice_unmake(dev)
        }
        device = nil
    }

    // MARK: - Device Discovery

    /// List all available SoapySDR devices
    public static func enumerateDevices() -> [SDRDeviceInfo] {
        var deviceCount: Int = 0
        guard let deviceList = SoapySDRDevice_enumerate(nil, &deviceCount) else {
            return []
        }

        var devices: [SDRDeviceInfo] = []
        for i in 0..<deviceCount {
            let kwargs = deviceList[i]

            var driver = ""
            var serial = ""
            var product = ""

            // Extract key-value pairs
            for j in 0..<kwargs.size {
                let key = String(cString: kwargs.keys[j]!)
                let value = String(cString: kwargs.vals[j]!)

                switch key {
                case "driver":
                    driver = value
                case "serial":
                    serial = value
                case "product", "label":
                    product = value
                default:
                    break
                }
            }

            let name = product.isEmpty ? driver : product
            let id = serial.isEmpty ? "\(driver)_\(i)" : serial

            devices.append(SDRDeviceInfo(
                id: id,
                name: name,
                driver: driver,
                serial: serial.isEmpty ? nil : serial,
                product: product.isEmpty ? nil : product
            ))
        }

        SoapySDRKwargsList_clear(deviceList, deviceCount)

        return devices
    }
}
