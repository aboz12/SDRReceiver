import SwiftUI
import MetalKit

// MARK: - Metal Waterfall Renderer

public class WaterfallRenderer: NSObject, MTKViewDelegate {
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var waterfallTexture: MTLTexture!

    private var textureWidth: Int = 1024
    private var textureHeight: Int = 512
    private var currentLine: Int = 0

    private var uniforms = WaterfallUniforms(
        minDb: -120,
        maxDb: 0,
        scrollOffset: 0,
        time: 0,
        glowIntensity: 0.5
    )

    private var startTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()

    public override init() {
        super.init()
        setupMetal()
    }

    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal not supported")
            return
        }
        self.device = device
        self.commandQueue = device.makeCommandQueue()

        // Create waterfall data texture
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: textureWidth,
            height: textureHeight,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        waterfallTexture = device.makeTexture(descriptor: textureDescriptor)

        // Clear texture
        clearTexture()

        // Create pipeline
        setupPipeline()
    }

    private func clearTexture() {
        let zeros = [Float](repeating: -120, count: textureWidth * textureHeight)
        zeros.withUnsafeBytes { ptr in
            waterfallTexture.replace(
                region: MTLRegion(
                    origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: textureWidth, height: textureHeight, depth: 1)
                ),
                mipmapLevel: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: textureWidth * MemoryLayout<Float>.size
            )
        }
    }

    private func setupPipeline() {
        guard let library = device.makeDefaultLibrary() else {
            print("Could not load Metal library")
            return
        }

        let vertexFunction = library.makeFunction(name: "waterfall_vertex")
        let fragmentFunction = library.makeFunction(name: "waterfall_fragment")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create pipeline state: \(error)")
        }
    }

    public func addLine(_ magnitudes: [Float]) {
        guard waterfallTexture != nil else { return }

        // Resample magnitudes to texture width
        var lineData = [Float](repeating: -120, count: textureWidth)
        let ratio = Float(magnitudes.count) / Float(textureWidth)

        for i in 0..<textureWidth {
            let srcIndex = Int(Float(i) * ratio)
            if srcIndex < magnitudes.count {
                lineData[i] = magnitudes[srcIndex]
            }
        }

        // Write to current line in texture
        lineData.withUnsafeBytes { ptr in
            waterfallTexture.replace(
                region: MTLRegion(
                    origin: MTLOrigin(x: 0, y: currentLine, z: 0),
                    size: MTLSize(width: textureWidth, height: 1, depth: 1)
                ),
                mipmapLevel: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: textureWidth * MemoryLayout<Float>.size
            )
        }

        currentLine = (currentLine + 1) % textureHeight
        uniforms.scrollOffset = Float(currentLine) / Float(textureHeight)
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let pipelineState = pipelineState,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        uniforms.time = Float(CFAbsoluteTimeGetCurrent() - startTime)

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(waterfallTexture, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<WaterfallUniforms>.size, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

// Uniforms struct matching Metal shader
struct WaterfallUniforms {
    var minDb: Float
    var maxDb: Float
    var scrollOffset: Float
    var time: Float
    var glowIntensity: Float
}

// MARK: - SwiftUI Metal View Wrapper

public struct MetalWaterfallView: NSViewRepresentable {
    @ObservedObject var dspEngine: DSPEngine
    let renderer: WaterfallRenderer

    public init(dspEngine: DSPEngine) {
        self.dspEngine = dspEngine
        self.renderer = WaterfallRenderer()
    }

    public func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = renderer
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.preferredFramesPerSecond = 60
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0.05, alpha: 1)
        return mtkView
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {
        // Add new waterfall line when spectrum data updates
        if let spectrum = dspEngine.spectrumData {
            renderer.addLine(spectrum.magnitudes)
        }
    }
}

// MARK: - Canvas-based Waterfall (Fallback)

public struct CanvasWaterfallView: View {
    @ObservedObject var dspEngine: DSPEngine
    @State private var waterfallLines: [[Float]] = []
    private let maxLines = 300

    public var body: some View {
        Canvas { context, size in
            let lineHeight = size.height / CGFloat(maxLines)

            for (index, magnitudes) in waterfallLines.enumerated() {
                let y = CGFloat(index) * lineHeight
                let pixelWidth = size.width / CGFloat(magnitudes.count)

                for (i, magnitude) in magnitudes.enumerated() {
                    let x = CGFloat(i) * pixelWidth
                    let color = magnitudeToColor(magnitude)

                    context.fill(
                        Path(CGRect(x: x, y: y, width: pixelWidth + 1, height: lineHeight + 1)),
                        with: .color(color)
                    )
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

    private func magnitudeToColor(_ db: Float) -> Color {
        let normalized = Double((db + 120) / 120)  // -120 to 0 dB -> 0 to 1
        let n = max(0, min(1, normalized))

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
}
