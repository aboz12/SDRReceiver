import SwiftUI

// MARK: - Click-to-Tune Handler

public struct ClickToTuneModifier: ViewModifier {
    @EnvironmentObject var sdrEngine: SDREngine

    let centerFrequency: Double
    let bandwidth: Double
    let onTune: ((Double) -> Void)?

    public func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        handleClick(at: value.location, in: value.startLocation)
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        // Double-tap to center on current frequency
                    }
            )
    }

    private func handleClick(at location: CGPoint, in startLocation: CGPoint) {
        // Only handle click if it's a tap (not a drag)
        let distance = sqrt(pow(location.x - startLocation.x, 2) + pow(location.y - startLocation.y, 2))
        guard distance < 5 else { return }

        // Calculate frequency from click position
        // This will be called by the parent view with proper geometry
    }
}

// MARK: - Interactive Spectrum View

public struct InteractiveSpectrumView: View {
    @ObservedObject var dspEngine: DSPEngine
    @EnvironmentObject var sdrEngine: SDREngine
    @ObservedObject var themeManager = ThemeManager.shared

    @State private var isDragging = false
    @State private var dragStartFrequency: Double = 0
    @State private var hoverFrequency: Double?
    @State private var showFrequencyMarker = false
    @State private var markerPosition: CGPoint = .zero

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Spectrum display
                Canvas { context, size in
                    drawSpectrum(context: context, size: size)
                }

                // Frequency marker on hover/click
                if showFrequencyMarker, let freq = hoverFrequency {
                    VStack(spacing: 4) {
                        Text(FrequencyFormatter.format(freq))
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .cornerRadius(4)

                        Rectangle()
                            .fill(Color.yellow.opacity(0.7))
                            .frame(width: 1, height: geometry.size.height)
                    }
                    .position(x: markerPosition.x, y: geometry.size.height / 2)
                }

                // Center frequency marker
                Rectangle()
                    .fill(Color.red.opacity(0.5))
                    .frame(width: 2, height: geometry.size.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                // Click overlay
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                handleDrag(value, in: geometry)
                            }
                            .onEnded { value in
                                handleDragEnd(value, in: geometry)
                            }
                    )
                    .onHover { hovering in
                        showFrequencyMarker = hovering
                    }
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            handleHover(at: location, in: geometry)
                        case .ended:
                            showFrequencyMarker = false
                        }
                    }
            }
        }
    }

    private func drawSpectrum(context: GraphicsContext, size: CGSize) {
        guard let spectrum = dspEngine.spectrumData, !spectrum.isEmpty else { return }

        let magnitudes = spectrum.magnitudes
        let count = magnitudes.count

        // Draw grid
        drawGrid(context: context, size: size)

        // Draw spectrum
        var path = Path()
        let xScale = size.width / CGFloat(count)

        for (index, magnitude) in magnitudes.enumerated() {
            let x = CGFloat(index) * xScale
            let normalized = CGFloat((magnitude + 120) / 120)
            let y = size.height * (1 - max(0, min(1, normalized)))

            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        // Fill
        var fillPath = path
        fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
        fillPath.addLine(to: CGPoint(x: 0, y: size.height))
        fillPath.closeSubpath()

        context.fill(
            fillPath,
            with: .linearGradient(
                Gradient(colors: [
                    themeManager.currentTheme.colors.spectrumFill.color,
                    themeManager.currentTheme.colors.spectrumFill.color.opacity(0.1)
                ]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height)
            )
        )

        // Stroke
        context.stroke(
            path,
            with: .color(themeManager.currentTheme.colors.spectrumStroke.color),
            lineWidth: 1.5
        )
    }

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let gridColor = themeManager.currentTheme.colors.spectrumGrid.color

        // Horizontal lines (dB scale)
        for i in 0...6 {
            let y = size.height * CGFloat(i) / 6
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(gridColor), lineWidth: 0.5)

            // dB label
            let db = -120 + (6 - i) * 20
            context.draw(
                Text("\(db) dB")
                    .font(.system(size: 9))
                    .foregroundColor(gridColor),
                at: CGPoint(x: 30, y: y + 10)
            )
        }

        // Vertical lines (frequency markers)
        let spectrum = dspEngine.spectrumData
        let centerFreq = spectrum?.centerFrequency ?? sdrEngine.frequency
        let bandwidth = spectrum?.sampleRate ?? 2_048_000  // Default bandwidth

        for i in 0...4 {
            let x = size.width * CGFloat(i) / 4
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: .color(gridColor), lineWidth: 0.5)

            // Frequency label
            let freqOffset = bandwidth * (Double(i) / 4 - 0.5)
            let freq = centerFreq + freqOffset
            context.draw(
                Text(FrequencyFormatter.formatShort(freq))
                    .font(.system(size: 9))
                    .foregroundColor(gridColor),
                at: CGPoint(x: x, y: size.height - 10)
            )
        }
    }

    private func handleHover(at location: CGPoint, in geometry: GeometryProxy) {
        let frequency = frequencyFromPosition(location.x, width: geometry.size.width)
        hoverFrequency = frequency
        markerPosition = location
        showFrequencyMarker = true
    }

    private func handleDrag(_ value: DragGesture.Value, in geometry: GeometryProxy) {
        if !isDragging {
            isDragging = true
            dragStartFrequency = sdrEngine.frequency
        }

        // Drag to pan frequency
        let deltaX = value.translation.width
        let bandwidth = dspEngine.spectrumData?.sampleRate ?? 2_048_000
        let deltaFreq = -deltaX / geometry.size.width * bandwidth

        let newFreq = dragStartFrequency + deltaFreq
        sdrEngine.tuneTo(newFreq)
    }

    private func handleDragEnd(_ value: DragGesture.Value, in geometry: GeometryProxy) {
        // Check if it was a click (minimal movement)
        let distance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))

        if distance < 5 {
            // Click to tune
            let frequency = frequencyFromPosition(value.location.x, width: geometry.size.width)
            sdrEngine.tuneTo(frequency)
            MultiVFOManager.shared.updateActiveVFO(frequency: frequency)
        }

        isDragging = false
    }

    private func frequencyFromPosition(_ x: CGFloat, width: CGFloat) -> Double {
        let spectrum = dspEngine.spectrumData
        let centerFreq = spectrum?.centerFrequency ?? sdrEngine.frequency
        let bandwidth = spectrum?.sampleRate ?? 2_048_000

        let relativePosition = x / width - 0.5  // -0.5 to 0.5
        return centerFreq + relativePosition * bandwidth
    }
}

// MARK: - Interactive Waterfall View

public struct InteractiveWaterfallView: View {
    @ObservedObject var dspEngine: DSPEngine
    @EnvironmentObject var sdrEngine: SDREngine
    @ObservedObject var themeManager = ThemeManager.shared

    @State private var waterfallLines: [[Float]] = []
    @State private var isDragging = false
    @State private var dragStartFrequency: Double = 0
    @State private var hoverFrequency: Double?
    @State private var showMarker = false
    @State private var markerX: CGFloat = 0

    private let maxLines = 200

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Waterfall display
                Canvas { context, size in
                    drawWaterfall(context: context, size: size)
                }

                // Frequency marker
                if showMarker, let freq = hoverFrequency {
                    VStack {
                        Text(FrequencyFormatter.format(freq))
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial)
                            .cornerRadius(3)
                        Spacer()
                    }
                    .position(x: markerX, y: 20)

                    Rectangle()
                        .fill(Color.yellow.opacity(0.5))
                        .frame(width: 1)
                        .position(x: markerX, y: geometry.size.height / 2)
                }

                // Center marker
                Rectangle()
                    .fill(Color.red.opacity(0.4))
                    .frame(width: 2)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                // Interaction overlay
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { handleDrag($0, in: geometry) }
                            .onEnded { handleDragEnd($0, in: geometry) }
                    )
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            handleHover(at: location, in: geometry)
                        case .ended:
                            showMarker = false
                        }
                    }
            }
        }
        .onChange(of: dspEngine.waterfallLine?.id) { _, _ in
            if let line = dspEngine.waterfallLine {
                waterfallLines.insert(line.magnitudes, at: 0)
                if waterfallLines.count > maxLines {
                    waterfallLines.removeLast()
                }
            }
        }
    }

    private func drawWaterfall(context: GraphicsContext, size: CGSize) {
        guard !waterfallLines.isEmpty else { return }

        let lineHeight = size.height / CGFloat(maxLines)
        let colorScheme = themeManager.currentTheme.waterfallColorScheme

        for (lineIndex, magnitudes) in waterfallLines.enumerated() {
            let y = CGFloat(lineIndex) * lineHeight
            let pixelWidth = size.width / CGFloat(magnitudes.count)

            for (i, magnitude) in magnitudes.enumerated() {
                let x = CGFloat(i) * pixelWidth
                let color = colorScheme.colorForMagnitude(magnitude)

                context.fill(
                    Path(CGRect(x: x, y: y, width: pixelWidth + 1, height: lineHeight + 1)),
                    with: .color(color)
                )
            }
        }
    }

    private func handleHover(at location: CGPoint, in geometry: GeometryProxy) {
        let frequency = frequencyFromPosition(location.x, width: geometry.size.width)
        hoverFrequency = frequency
        markerX = location.x
        showMarker = true
    }

    private func handleDrag(_ value: DragGesture.Value, in geometry: GeometryProxy) {
        if !isDragging {
            isDragging = true
            dragStartFrequency = sdrEngine.frequency
        }

        let deltaX = value.translation.width
        let bandwidth = dspEngine.spectrumData?.sampleRate ?? 2_048_000
        let deltaFreq = -deltaX / geometry.size.width * bandwidth

        sdrEngine.tuneTo(dragStartFrequency + deltaFreq)
    }

    private func handleDragEnd(_ value: DragGesture.Value, in geometry: GeometryProxy) {
        let distance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))

        if distance < 5 {
            let frequency = frequencyFromPosition(value.location.x, width: geometry.size.width)
            sdrEngine.tuneTo(frequency)
            MultiVFOManager.shared.updateActiveVFO(frequency: frequency)
        }

        isDragging = false
    }

    private func frequencyFromPosition(_ x: CGFloat, width: CGFloat) -> Double {
        let spectrum = dspEngine.spectrumData
        let centerFreq = spectrum?.centerFrequency ?? sdrEngine.frequency
        let bandwidth = spectrum?.sampleRate ?? 2_048_000

        let relativePosition = x / width - 0.5
        return centerFreq + relativePosition * bandwidth
    }
}

// MARK: - Bandwidth Selection Overlay

public struct BandwidthSelectionOverlay: View {
    @EnvironmentObject var sdrEngine: SDREngine
    @ObservedObject var dspEngine: DSPEngine

    let spectrumWidth: CGFloat

    public var body: some View {
        GeometryReader { geometry in
            let bandwidth = dspEngine.filterBandwidth
            let sampleRate = dspEngine.spectrumData?.sampleRate ?? 2_048_000
            let filterWidth = geometry.size.width * CGFloat(bandwidth / sampleRate)
            let centerX = geometry.size.width / 2

            ZStack {
                // Filter passband indicator
                Rectangle()
                    .fill(Color.yellow.opacity(0.15))
                    .frame(width: filterWidth, height: geometry.size.height)
                    .position(x: centerX, y: geometry.size.height / 2)

                // Filter edges
                Rectangle()
                    .fill(Color.yellow.opacity(0.4))
                    .frame(width: 2, height: geometry.size.height)
                    .position(x: centerX - filterWidth / 2, y: geometry.size.height / 2)

                Rectangle()
                    .fill(Color.yellow.opacity(0.4))
                    .frame(width: 2, height: geometry.size.height)
                    .position(x: centerX + filterWidth / 2, y: geometry.size.height / 2)

                // Resize handles
                ResizeHandle(edge: .leading, bandwidth: $dspEngine.filterBandwidth, geometry: geometry, sampleRate: sampleRate)
                    .position(x: centerX - filterWidth / 2, y: geometry.size.height / 2)

                ResizeHandle(edge: .trailing, bandwidth: $dspEngine.filterBandwidth, geometry: geometry, sampleRate: sampleRate)
                    .position(x: centerX + filterWidth / 2, y: geometry.size.height / 2)
            }
        }
    }
}

struct ResizeHandle: View {
    enum Edge {
        case leading, trailing
    }

    let edge: Edge
    @Binding var bandwidth: Double
    let geometry: GeometryProxy
    let sampleRate: Double

    @State private var isDragging = false

    var body: some View {
        Rectangle()
            .fill(Color.yellow)
            .frame(width: 8, height: 40)
            .cornerRadius(4)
            .opacity(isDragging ? 1 : 0.6)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        let deltaX = value.translation.width
                        let deltaBW = deltaX / geometry.size.width * sampleRate * 2

                        if edge == .trailing {
                            bandwidth = max(500, bandwidth + deltaBW)
                        } else {
                            bandwidth = max(500, bandwidth - deltaBW)
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }
}
