import Foundation
import SwiftUI

// MARK: - I/Q Recording Format

public enum IQRecordingFormat: String, CaseIterable {
    case raw8 = "RAW8"      // 8-bit unsigned I/Q
    case raw16 = "RAW16"    // 16-bit signed I/Q
    case float32 = "F32"    // 32-bit float I/Q
    case wav = "WAV"        // WAV file format

    var fileExtension: String {
        switch self {
        case .raw8, .raw16, .float32: return "iq"
        case .wav: return "wav"
        }
    }

    var bytesPerSample: Int {
        switch self {
        case .raw8: return 2   // I + Q each 1 byte
        case .raw16: return 4  // I + Q each 2 bytes
        case .float32: return 8 // I + Q each 4 bytes
        case .wav: return 8    // Stereo float
        }
    }
}

// MARK: - Recording Metadata

public struct IQRecordingMetadata: Codable {
    public let frequency: Double
    public let sampleRate: Double
    public let format: String
    public let startTime: Date
    public var endTime: Date?
    public var samplesRecorded: Int64
    public let gain: Double
    public let demodMode: String?
    public let notes: String?

    public init(
        frequency: Double,
        sampleRate: Double,
        format: IQRecordingFormat,
        gain: Double,
        demodMode: String? = nil,
        notes: String? = nil
    ) {
        self.frequency = frequency
        self.sampleRate = sampleRate
        self.format = format.rawValue
        self.startTime = Date()
        self.endTime = nil
        self.samplesRecorded = 0
        self.gain = gain
        self.demodMode = demodMode
        self.notes = notes
    }
}

// MARK: - Recording Info

public struct IQRecording: Identifiable, Codable {
    public let id: UUID
    public let filename: String
    public let metadata: IQRecordingMetadata
    public let fileSize: Int64

    public var duration: TimeInterval {
        guard metadata.sampleRate > 0 else { return 0 }
        return Double(metadata.samplesRecorded) / metadata.sampleRate
    }

    public var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    public var formattedFrequency: String {
        if metadata.frequency >= 1_000_000_000 {
            return String(format: "%.4f GHz", metadata.frequency / 1_000_000_000)
        } else if metadata.frequency >= 1_000_000 {
            return String(format: "%.4f MHz", metadata.frequency / 1_000_000)
        } else {
            return String(format: "%.3f kHz", metadata.frequency / 1_000)
        }
    }

    public var formattedFileSize: String {
        if fileSize >= 1_073_741_824 {
            return String(format: "%.2f GB", Double(fileSize) / 1_073_741_824)
        } else if fileSize >= 1_048_576 {
            return String(format: "%.1f MB", Double(fileSize) / 1_048_576)
        } else {
            return String(format: "%.0f KB", Double(fileSize) / 1024)
        }
    }
}

// MARK: - I/Q Recorder

@MainActor
public final class IQRecorder: ObservableObject {
    public static let shared = IQRecorder()

    @Published public var isRecording = false
    @Published public var isPaused = false
    @Published public var currentRecording: IQRecordingMetadata?
    @Published public var recordingDuration: TimeInterval = 0
    @Published public var bytesWritten: Int64 = 0
    @Published public var recordings: [IQRecording] = []

    // Playback
    @Published public var isPlaying = false
    @Published public var playbackPosition: TimeInterval = 0
    @Published public var currentPlayback: IQRecording?

    private var fileHandle: FileHandle?
    private var currentFilePath: URL?
    private var recordingStartTime: Date?
    private var timer: Timer?
    private var recordingFormat: IQRecordingFormat = .float32

    private let recordingsDirectory: URL

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        recordingsDirectory = documents.appendingPathComponent("SDRRecordings", isDirectory: true)

        // Create recordings directory
        try? FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)

        loadRecordingsList()
    }

    // MARK: - Recording Control

    public func startRecording(
        frequency: Double,
        sampleRate: Double,
        format: IQRecordingFormat,
        gain: Double,
        notes: String? = nil
    ) throws {
        guard !isRecording else { return }

        recordingFormat = format

        // Create filename
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let freqMHz = String(format: "%.3f", frequency / 1_000_000)
        let filename = "SDR_\(freqMHz)MHz_\(timestamp).\(format.fileExtension)"

        currentFilePath = recordingsDirectory.appendingPathComponent(filename)

        // Create file
        FileManager.default.createFile(atPath: currentFilePath!.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: currentFilePath!)

        // Write WAV header if needed
        if format == .wav {
            try writeWAVHeader(sampleRate: sampleRate)
        }

        // Create metadata
        currentRecording = IQRecordingMetadata(
            frequency: frequency,
            sampleRate: sampleRate,
            format: format,
            gain: gain,
            notes: notes
        )

        isRecording = true
        isPaused = false
        recordingStartTime = Date()
        bytesWritten = 0

        // Start timer for UI updates
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateRecordingDuration()
            }
        }
    }

    public func pauseRecording() {
        isPaused = true
    }

    public func resumeRecording() {
        isPaused = false
    }

    public func stopRecording() {
        guard isRecording else { return }

        timer?.invalidate()
        timer = nil

        // Finalize WAV header if needed
        if recordingFormat == .wav {
            finalizeWAVHeader()
        }

        try? fileHandle?.close()
        fileHandle = nil

        // Update metadata
        if var metadata = currentRecording {
            metadata.endTime = Date()

            // Save metadata file
            let metadataPath = currentFilePath!.deletingPathExtension().appendingPathExtension("json")
            if let data = try? JSONEncoder().encode(metadata) {
                try? data.write(to: metadataPath)
            }

            // Add to recordings list
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: currentFilePath!.path)[.size] as? Int64) ?? 0
            let recording = IQRecording(
                id: UUID(),
                filename: currentFilePath!.lastPathComponent,
                metadata: metadata,
                fileSize: fileSize
            )
            recordings.insert(recording, at: 0)
            saveRecordingsList()
        }

        isRecording = false
        isPaused = false
        currentRecording = nil
        recordingDuration = 0
        bytesWritten = 0
    }

    // MARK: - Sample Writing

    public func writeSamples(_ samples: [ComplexFloat]) {
        guard isRecording, !isPaused, let handle = fileHandle else { return }

        var data: Data

        switch recordingFormat {
        case .raw8:
            data = Data(capacity: samples.count * 2)
            for sample in samples {
                let i = UInt8(clamping: Int((sample.real + 1.0) * 127.5))
                let q = UInt8(clamping: Int((sample.imag + 1.0) * 127.5))
                data.append(i)
                data.append(q)
            }

        case .raw16:
            data = Data(capacity: samples.count * 4)
            for sample in samples {
                var i = Int16(clamping: Int(sample.real * 32767))
                var q = Int16(clamping: Int(sample.imag * 32767))
                data.append(contentsOf: withUnsafeBytes(of: &i) { Array($0) })
                data.append(contentsOf: withUnsafeBytes(of: &q) { Array($0) })
            }

        case .float32, .wav:
            data = Data(capacity: samples.count * 8)
            for sample in samples {
                var i = sample.real
                var q = sample.imag
                data.append(contentsOf: withUnsafeBytes(of: &i) { Array($0) })
                data.append(contentsOf: withUnsafeBytes(of: &q) { Array($0) })
            }
        }

        try? handle.write(contentsOf: data)
        bytesWritten += Int64(data.count)

        if var metadata = currentRecording {
            metadata.samplesRecorded += Int64(samples.count)
            currentRecording = metadata
        }
    }

    // MARK: - WAV Format

    private func writeWAVHeader(sampleRate: Double) throws {
        guard let handle = fileHandle else { return }

        // Placeholder header - will be updated when recording stops
        var header = Data(count: 44)

        // RIFF header
        header.replaceSubrange(0..<4, with: "RIFF".data(using: .ascii)!)
        header.replaceSubrange(8..<12, with: "WAVE".data(using: .ascii)!)

        // fmt chunk
        header.replaceSubrange(12..<16, with: "fmt ".data(using: .ascii)!)
        var fmtSize: UInt32 = 16
        header.replaceSubrange(16..<20, with: withUnsafeBytes(of: &fmtSize) { Data($0) })
        var audioFormat: UInt16 = 3 // IEEE float
        header.replaceSubrange(20..<22, with: withUnsafeBytes(of: &audioFormat) { Data($0) })
        var numChannels: UInt16 = 2 // I/Q stereo
        header.replaceSubrange(22..<24, with: withUnsafeBytes(of: &numChannels) { Data($0) })
        var sampleRateInt: UInt32 = UInt32(sampleRate)
        header.replaceSubrange(24..<28, with: withUnsafeBytes(of: &sampleRateInt) { Data($0) })
        var byteRate: UInt32 = UInt32(sampleRate) * 2 * 4 // channels * bytes per sample
        header.replaceSubrange(28..<32, with: withUnsafeBytes(of: &byteRate) { Data($0) })
        var blockAlign: UInt16 = 8 // 2 channels * 4 bytes
        header.replaceSubrange(32..<34, with: withUnsafeBytes(of: &blockAlign) { Data($0) })
        var bitsPerSample: UInt16 = 32
        header.replaceSubrange(34..<36, with: withUnsafeBytes(of: &bitsPerSample) { Data($0) })

        // data chunk
        header.replaceSubrange(36..<40, with: "data".data(using: .ascii)!)
        // data size will be filled in when finalizing

        try handle.write(contentsOf: header)
    }

    private func finalizeWAVHeader() {
        guard let handle = fileHandle else { return }

        let dataSize = UInt32(bytesWritten - 44)
        let fileSize = UInt32(bytesWritten - 8)

        // Update RIFF size
        try? handle.seek(toOffset: 4)
        var riffSize = fileSize
        try? handle.write(contentsOf: withUnsafeBytes(of: &riffSize) { Data($0) })

        // Update data size
        try? handle.seek(toOffset: 40)
        var dataSizeVal = dataSize
        try? handle.write(contentsOf: withUnsafeBytes(of: &dataSizeVal) { Data($0) })
    }

    // MARK: - Playback

    public func startPlayback(_ recording: IQRecording, sdrEngine: SDREngine) {
        guard !isPlaying else { return }

        currentPlayback = recording
        isPlaying = true
        playbackPosition = 0

        // TODO: Implement SDR playback mode
        // Set SDR to playback mode
        // let filePath = recordingsDirectory.appendingPathComponent(recording.filename)
        // sdrEngine.startPlayback(from: filePath, metadata: recording.metadata)
    }

    public func stopPlayback(sdrEngine: SDREngine) {
        isPlaying = false
        playbackPosition = 0
        currentPlayback = nil
        // TODO: Implement SDR playback stop
        // sdrEngine.stopPlayback()
    }

    public func seekPlayback(to position: TimeInterval) {
        playbackPosition = position
        // Notify SDR engine to seek
    }

    // MARK: - Recording Management

    public func deleteRecording(_ recording: IQRecording) {
        let filePath = recordingsDirectory.appendingPathComponent(recording.filename)
        let metadataPath = filePath.deletingPathExtension().appendingPathExtension("json")

        try? FileManager.default.removeItem(at: filePath)
        try? FileManager.default.removeItem(at: metadataPath)

        recordings.removeAll { $0.id == recording.id }
        saveRecordingsList()
    }

    private func loadRecordingsList() {
        let files = try? FileManager.default.contentsOfDirectory(at: recordingsDirectory, includingPropertiesForKeys: [.fileSizeKey])

        recordings = files?.compactMap { url -> IQRecording? in
            guard url.pathExtension != "json" else { return nil }

            let metadataPath = url.deletingPathExtension().appendingPathExtension("json")
            guard let data = try? Data(contentsOf: metadataPath),
                  let metadata = try? JSONDecoder().decode(IQRecordingMetadata.self, from: data) else {
                return nil
            }

            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

            return IQRecording(
                id: UUID(),
                filename: url.lastPathComponent,
                metadata: metadata,
                fileSize: Int64(fileSize)
            )
        } ?? []

        recordings.sort { $0.metadata.startTime > $1.metadata.startTime }
    }

    private func saveRecordingsList() {
        // Recordings are saved as individual files, no master list needed
    }

    private func updateRecordingDuration() {
        if let startTime = recordingStartTime, !isPaused {
            recordingDuration = Date().timeIntervalSince(startTime)
        }
    }
}

// MARK: - Recording View

public struct IQRecordingView: View {
    @ObservedObject var recorder = IQRecorder.shared
    @EnvironmentObject var sdrEngine: SDREngine

    @State private var selectedFormat: IQRecordingFormat = .float32
    @State private var recordingNotes = ""
    @State private var showingRecordingsList = false

    public var body: some View {
        VStack(spacing: 16) {
            // Recording Controls
            HStack(spacing: 20) {
                // Record button
                Button {
                    if recorder.isRecording {
                        recorder.stopRecording()
                    } else {
                        try? recorder.startRecording(
                            frequency: sdrEngine.frequency,
                            sampleRate: 2_048_000,
                            format: selectedFormat,
                            gain: sdrEngine.gain,
                            notes: recordingNotes.isEmpty ? nil : recordingNotes
                        )
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(recorder.isRecording ? Color.red : Color.red.opacity(0.8))
                            .frame(width: 50, height: 50)

                        if recorder.isRecording {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white)
                                .frame(width: 18, height: 18)
                        } else {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 20, height: 20)
                        }
                    }
                }
                .buttonStyle(.plain)

                if recorder.isRecording {
                    // Pause/Resume
                    Button {
                        if recorder.isPaused {
                            recorder.resumeRecording()
                        } else {
                            recorder.pauseRecording()
                        }
                    } label: {
                        Image(systemName: recorder.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.gray.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if recorder.isRecording {
                        HStack {
                            Circle()
                                .fill(recorder.isPaused ? Color.yellow : Color.red)
                                .frame(width: 8, height: 8)
                            Text(recorder.isPaused ? "PAUSED" : "RECORDING")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(recorder.isPaused ? .yellow : .red)
                        }

                        Text(formatDuration(recorder.recordingDuration))
                            .font(.system(size: 18, design: .monospaced))
                            .foregroundColor(.white)

                        Text(formatBytes(recorder.bytesWritten))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        Text("Ready to Record")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)

                        Text(sdrEngine.frequency > 0 ? FrequencyFormatter.format(sdrEngine.frequency) : "No frequency set")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if !recorder.isRecording {
                    // Format picker
                    Picker("Format", selection: $selectedFormat) {
                        ForEach(IQRecordingFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }

                // Recordings list button
                Button {
                    showingRecordingsList.toggle()
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 16))
                    Text("\(recorder.recordings.count)")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(12)

            // Recordings List
            if showingRecordingsList {
                RecordingsListView()
                    .frame(height: 300)
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)

        if hours > 0 {
            return String(format: "%d:%02d:%02d.%d", hours, minutes, seconds, tenths)
        } else {
            return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes >= 1_073_741_824 {
            return String(format: "%.2f GB", Double(bytes) / 1_073_741_824)
        } else if bytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576)
        } else {
            return String(format: "%d KB", bytes / 1024)
        }
    }
}

struct RecordingsListView: View {
    @ObservedObject var recorder = IQRecorder.shared
    @EnvironmentObject var sdrEngine: SDREngine

    var body: some View {
        List {
            ForEach(recorder.recordings) { recording in
                RecordingRow(recording: recording)
                    .contextMenu {
                        Button {
                            recorder.startPlayback(recording, sdrEngine: sdrEngine)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }

                        Button {
                            // Tune to recorded frequency
                            sdrEngine.tuneTo(recording.metadata.frequency)
                        } label: {
                            Label("Tune to Frequency", systemImage: "antenna.radiowaves.left.and.right")
                        }

                        Divider()

                        Button(role: .destructive) {
                            recorder.deleteRecording(recording)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.inset)
    }
}

struct RecordingRow: View {
    let recording: IQRecording
    @ObservedObject var recorder = IQRecorder.shared

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.formattedFrequency)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.cyan)

                HStack(spacing: 8) {
                    Text(recording.metadata.format)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.3))
                        .cornerRadius(4)

                    Text(recording.formattedDuration)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Text(recording.formattedFileSize)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(recording.metadata.startTime, style: .date)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            if recorder.currentPlayback?.id == recording.id {
                Image(systemName: "play.fill")
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 4)
    }
}
