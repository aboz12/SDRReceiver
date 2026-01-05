import Foundation
import SwiftUI
import AVFoundation

// MARK: - Audio Recording Format

public enum AudioRecordingFormat: String, CaseIterable {
    case wav = "WAV"
    case mp3 = "MP3"
    case aac = "AAC"
    case flac = "FLAC"

    var fileExtension: String {
        rawValue.lowercased()
    }

    var audioFormatID: AudioFormatID {
        switch self {
        case .wav: return kAudioFormatLinearPCM
        case .mp3: return kAudioFormatMPEGLayer3
        case .aac: return kAudioFormatMPEG4AAC
        case .flac: return kAudioFormatFLAC
        }
    }
}

// MARK: - Audio Recording

public struct AudioRecordingInfo: Identifiable, Codable {
    public let id: UUID
    public let filename: String
    public let frequency: Double
    public let mode: String
    public let startTime: Date
    public var duration: TimeInterval
    public let format: String
    public let sampleRate: Double
    public let fileSize: Int64

    public var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    public var formattedFrequency: String {
        FrequencyFormatter.format(frequency)
    }

    public var formattedFileSize: String {
        if fileSize >= 1_048_576 {
            return String(format: "%.1f MB", Double(fileSize) / 1_048_576)
        } else {
            return String(format: "%.0f KB", Double(fileSize) / 1024)
        }
    }
}

// MARK: - Audio Recorder

@MainActor
public final class AudioRecorder: ObservableObject {
    public static let shared = AudioRecorder()

    @Published public var isRecording = false
    @Published public var isPaused = false
    @Published public var recordingDuration: TimeInterval = 0
    @Published public var peakLevel: Float = -60
    @Published public var recordings: [AudioRecordingInfo] = []

    // Playback
    @Published public var isPlaying = false
    @Published public var playbackPosition: TimeInterval = 0
    @Published public var playbackDuration: TimeInterval = 0
    @Published public var currentPlayback: AudioRecordingInfo?

    private var audioFile: AVAudioFile?
    private var currentFilePath: URL?
    private var recordingStartTime: Date?
    private var currentFormat: AudioRecordingFormat = .wav
    private var currentFrequency: Double = 0
    private var currentMode: String = "FM"
    private var timer: Timer?

    // Playback
    private var audioPlayer: AVAudioPlayer?

    private let recordingsDirectory: URL

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        recordingsDirectory = documents.appendingPathComponent("SDRAudioRecordings", isDirectory: true)

        try? FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)

        loadRecordings()
    }

    // MARK: - Recording

    public func startRecording(
        frequency: Double,
        mode: String,
        format: AudioRecordingFormat,
        sampleRate: Double = 48000
    ) throws {
        guard !isRecording else { return }

        currentFormat = format
        currentFrequency = frequency
        currentMode = mode

        // Create filename
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let freqMHz = String(format: "%.3f", frequency / 1_000_000)
        let filename = "Audio_\(freqMHz)MHz_\(timestamp).\(format.fileExtension)"

        currentFilePath = recordingsDirectory.appendingPathComponent(filename)

        // Create audio file
        let settings: [String: Any] = [
            AVFormatIDKey: format.audioFormatID,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false
        ]

        audioFile = try AVAudioFile(
            forWriting: currentFilePath!,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        isRecording = true
        isPaused = false
        recordingStartTime = Date()
        recordingDuration = 0

        // Start timer
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateRecordingState()
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

        audioFile = nil

        // Get file size
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: currentFilePath!.path)[.size] as? Int64) ?? 0

        // Create recording info
        let info = AudioRecordingInfo(
            id: UUID(),
            filename: currentFilePath!.lastPathComponent,
            frequency: currentFrequency,
            mode: currentMode,
            startTime: recordingStartTime!,
            duration: recordingDuration,
            format: currentFormat.rawValue,
            sampleRate: 48000,
            fileSize: fileSize
        )

        recordings.insert(info, at: 0)
        saveRecordings()

        isRecording = false
        isPaused = false
        recordingDuration = 0
        peakLevel = -60
    }

    public func writeAudioSamples(_ samples: [Float]) {
        guard isRecording, !isPaused, let file = audioFile else { return }

        // Convert to audio buffer
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else { return }

        buffer.frameLength = AVAudioFrameCount(samples.count)

        if let channelData = buffer.floatChannelData?[0] {
            for (index, sample) in samples.enumerated() {
                channelData[index] = sample
            }
        }

        try? file.write(from: buffer)

        // Update peak level
        let maxSample = samples.map { abs($0) }.max() ?? 0
        let db = 20 * log10(max(maxSample, 0.00001))
        peakLevel = max(peakLevel * 0.9 + db * 0.1, db)  // Smooth decay
    }

    private func updateRecordingState() {
        if let startTime = recordingStartTime, !isPaused {
            recordingDuration = Date().timeIntervalSince(startTime)
        }
    }

    // MARK: - Playback

    public func startPlayback(_ recording: AudioRecordingInfo) {
        let filePath = recordingsDirectory.appendingPathComponent(recording.filename)

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: filePath)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

            currentPlayback = recording
            isPlaying = true
            playbackDuration = recording.duration

            // Start playback timer
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.updatePlaybackState()
                }
            }
        } catch {
            print("Playback error: \(error)")
        }
    }

    public func pausePlayback() {
        audioPlayer?.pause()
        isPlaying = false
    }

    public func resumePlayback() {
        audioPlayer?.play()
        isPlaying = true
    }

    public func stopPlayback() {
        timer?.invalidate()
        timer = nil

        audioPlayer?.stop()
        audioPlayer = nil

        isPlaying = false
        playbackPosition = 0
        currentPlayback = nil
    }

    public func seekPlayback(to position: TimeInterval) {
        audioPlayer?.currentTime = position
        playbackPosition = position
    }

    private func updatePlaybackState() {
        if let player = audioPlayer {
            playbackPosition = player.currentTime

            if !player.isPlaying && playbackPosition >= playbackDuration - 0.1 {
                stopPlayback()
            }
        }
    }

    // MARK: - Management

    public func deleteRecording(_ recording: AudioRecordingInfo) {
        let filePath = recordingsDirectory.appendingPathComponent(recording.filename)
        try? FileManager.default.removeItem(at: filePath)

        recordings.removeAll { $0.id == recording.id }
        saveRecordings()
    }

    private func saveRecordings() {
        if let data = try? JSONEncoder().encode(recordings) {
            UserDefaults.standard.set(data, forKey: "SDRAudioRecordings")
        }
    }

    private func loadRecordings() {
        if let data = UserDefaults.standard.data(forKey: "SDRAudioRecordings"),
           let decoded = try? JSONDecoder().decode([AudioRecordingInfo].self, from: data) {
            recordings = decoded
        }
    }
}

// MARK: - Audio Recording View

public struct AudioRecordingView: View {
    @ObservedObject var recorder = AudioRecorder.shared
    @EnvironmentObject var sdrEngine: SDREngine

    @State private var selectedFormat: AudioRecordingFormat = .wav
    @State private var showingRecordingsList = false

    public var body: some View {
        VStack(spacing: 12) {
            // Recording Controls
            HStack(spacing: 16) {
                // Record button
                Button {
                    if recorder.isRecording {
                        recorder.stopRecording()
                    } else {
                        try? recorder.startRecording(
                            frequency: sdrEngine.frequency,
                            mode: sdrEngine.dspEngine.demodulationMode.rawValue,
                            format: selectedFormat
                        )
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(recorder.isRecording ? Color.red : Color.red.opacity(0.8))
                            .frame(width: 44, height: 44)

                        if recorder.isRecording {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white)
                                .frame(width: 14, height: 14)
                        } else {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 16, height: 16)
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
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 2) {
                    if recorder.isRecording {
                        HStack {
                            Circle()
                                .fill(recorder.isPaused ? Color.yellow : Color.red)
                                .frame(width: 6, height: 6)
                            Text(recorder.isPaused ? "PAUSED" : "REC")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(recorder.isPaused ? .yellow : .red)
                        }

                        Text(formatDuration(recorder.recordingDuration))
                            .font(.system(size: 16, design: .monospaced))
                    } else {
                        Text("Audio Ready")
                            .font(.system(size: 12, weight: .medium))
                    }
                }

                // Peak meter
                if recorder.isRecording {
                    AudioLevelMeter(level: recorder.peakLevel)
                        .frame(width: 100, height: 20)
                }

                Spacer()

                if !recorder.isRecording {
                    Picker("", selection: $selectedFormat) {
                        ForEach(AudioRecordingFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }

                Button {
                    showingRecordingsList.toggle()
                } label: {
                    Image(systemName: "list.bullet")
                    Text("\(recorder.recordings.count)")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(10)

            // Playback
            if let playback = recorder.currentPlayback {
                PlaybackControlView(recording: playback)
            }

            // Recordings list
            if showingRecordingsList {
                AudioRecordingsListView()
                    .frame(height: 200)
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}

struct AudioLevelMeter: View {
    let level: Float // dB

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black.opacity(0.3))

                // Level segments
                HStack(spacing: 1) {
                    ForEach(0..<20, id: \.self) { i in
                        let threshold = -60 + Float(i) * 3
                        let isActive = level >= threshold
                        Rectangle()
                            .fill(segmentColor(for: i, active: isActive))
                    }
                }
                .padding(2)
            }
        }
    }

    private func segmentColor(for index: Int, active: Bool) -> Color {
        guard active else { return Color.gray.opacity(0.2) }

        if index >= 18 { return .red }
        if index >= 14 { return .yellow }
        return .green
    }
}

struct PlaybackControlView: View {
    let recording: AudioRecordingInfo
    @ObservedObject var recorder = AudioRecorder.shared

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if recorder.isPlaying {
                    recorder.pausePlayback()
                } else {
                    recorder.resumePlayback()
                }
            } label: {
                Image(systemName: recorder.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18))
            }
            .buttonStyle(.bordered)

            Button {
                recorder.stopPlayback()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 16))
            }
            .buttonStyle(.bordered)

            Text(recording.formattedFrequency)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.cyan)

            // Progress
            Slider(
                value: Binding(
                    get: { recorder.playbackPosition },
                    set: { recorder.seekPlayback(to: $0) }
                ),
                in: 0...max(recorder.playbackDuration, 0.1)
            )

            Text(formatTime(recorder.playbackPosition))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 50)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct AudioRecordingsListView: View {
    @ObservedObject var recorder = AudioRecorder.shared

    var body: some View {
        List {
            ForEach(recorder.recordings) { recording in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recording.formattedFrequency)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.cyan)

                        HStack(spacing: 8) {
                            Text(recording.mode)
                                .font(.system(size: 10))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.3))
                                .cornerRadius(3)

                            Text(recording.format)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)

                            Text(recording.formattedDuration)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)

                            Text(recording.formattedFileSize)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Text(recording.startTime, style: .date)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    if recorder.currentPlayback?.id == recording.id {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundColor(.green)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    recorder.startPlayback(recording)
                }
                .contextMenu {
                    Button {
                        recorder.startPlayback(recording)
                    } label: {
                        Label("Play", systemImage: "play.fill")
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
