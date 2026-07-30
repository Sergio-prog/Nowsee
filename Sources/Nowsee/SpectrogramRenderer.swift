import Metal
import MetalKit
import simd

private let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut vertexMain(uint vertexID [[vertex_id]]) {
    float2 corners[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    VertexOut out;
    out.position = float4(corners[vertexID], 0.0, 1.0);
    out.uv = (corners[vertexID] + 1.0) * 0.5;
    return out;
}

fragment float4 fragmentMain(VertexOut in [[stage_in]],
                             texture2d<float> spectrogram [[texture(0)]],
                             texture2d<float> palette [[texture(1)]],
                             constant float &writeOffset [[buffer(0)]],
                             constant float4 &background [[buffer(1)]]) {
    constexpr sampler wrapSampler(filter::linear, address::repeat);
    constexpr sampler clampSampler(filter::linear, address::clamp_to_edge);
    float u = fract(in.uv.x + writeOffset);
    float intensity = spectrogram.sample(wrapSampler, float2(u, in.uv.y)).r;
    float3 color = palette.sample(clampSampler, float2(intensity, 0.5)).rgb;
    return float4(mix(background.rgb, color, intensity), background.a + (1.0 - background.a) * intensity);
}

fragment float4 fragmentWaveform(VertexOut in [[stage_in]],
                                 texture2d<float> envelope [[texture(0)]],
                                 texture2d<float> palette [[texture(1)]],
                                 constant float &writeOffset [[buffer(0)]],
                                 constant float4 &background [[buffer(1)]]) {
    constexpr sampler wrapSampler(filter::linear, address::repeat);
    constexpr sampler clampSampler(filter::linear, address::clamp_to_edge);
    float u = fract(in.uv.x + writeOffset);
    float2 bounds = envelope.sample(wrapSampler, float2(u, 0.5)).rg;

    float y = in.uv.y * 2.0 - 1.0;
    float amplitude = clamp(max(abs(bounds.r), abs(bounds.g)), 0.0, 1.0);
    float edge = fwidth(y) * 1.5 + 0.004;
    float inside = smoothstep(bounds.r - edge, bounds.r + edge, y)
                 * (1.0 - smoothstep(bounds.g - edge, bounds.g + edge, y));

    float3 color = palette.sample(clampSampler, float2(amplitude, 0.5)).rgb;
    float glow = exp(-abs(y) * 6.0) * amplitude * 0.25;
    float coverage = clamp(inside + glow, 0.0, 1.0);
    return float4(mix(background.rgb, color, coverage), background.a + (1.0 - background.a) * coverage);
}
"""

final class SpectrogramRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let spectrogramPipeline: MTLRenderPipelineState
    private let waveformPipeline: MTLRenderPipelineState
    private let spectrogram: MTLTexture
    private let envelope: MTLTexture
    private var palette: MTLTexture
    private let columnCapacity: Int
    private let rowCount: Int
    private var writeIndex = 0
    private var envelopeIndex = 0

    var mode: Visualization = .spectrogram
    var background = SIMD4<Float>(0, 0, 0, 1)

    private(set) var columnsAppended = 0
    private(set) var framesDrawn = 0
    private(set) var brightestColumn: Float = 0

    private let idleAfter: CFTimeInterval = 12
    private let signalThreshold: Float = 0.2
    private var lastSignalTime = CACurrentMediaTime()

    var hasScrolledToSilence: Bool {
        CACurrentMediaTime() - lastSignalTime > idleAfter
    }

    init?(rowCount: Int, columnCapacity: Int = 1024) {
        guard let device = MTLCreateSystemDefaultDevice(),
            let commandQueue = device.makeCommandQueue()
        else { return nil }

        self.device = device
        self.commandQueue = commandQueue
        self.rowCount = rowCount
        self.columnCapacity = columnCapacity

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let vertexFunction = library.makeFunction(name: "vertexMain")

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = library.makeFunction(name: "fragmentMain")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            spectrogramPipeline = try device.makeRenderPipelineState(descriptor: descriptor)

            descriptor.fragmentFunction = library.makeFunction(name: "fragmentWaveform")
            waveformPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            NSLog("Nowsee: Metal pipeline failed — \(error)")
            return nil
        }

        let spectrogramDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: columnCapacity,
            height: rowCount,
            mipmapped: false
        )
        spectrogramDescriptor.usage = .shaderRead
        spectrogramDescriptor.storageMode = .shared
        guard let spectrogram = device.makeTexture(descriptor: spectrogramDescriptor) else { return nil }
        self.spectrogram = spectrogram

        let envelopeDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg32Float,
            width: columnCapacity,
            height: 1,
            mipmapped: false
        )
        envelopeDescriptor.usage = .shaderRead
        envelopeDescriptor.storageMode = .shared
        guard let envelope = device.makeTexture(descriptor: envelopeDescriptor) else { return nil }
        self.envelope = envelope

        let paletteDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float,
            width: 256,
            height: 1,
            mipmapped: false
        )
        paletteDescriptor.usage = .shaderRead
        paletteDescriptor.storageMode = .shared
        guard let palette = device.makeTexture(descriptor: paletteDescriptor) else { return nil }
        self.palette = palette

        super.init()
        apply(palette: .magma)
    }

    func apply(palette newPalette: Palette) {
        let table = newPalette.lookupTable()
        table.withUnsafeBytes { bytes in
            palette.replace(
                region: MTLRegionMake2D(0, 0, table.count, 1),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: table.count * MemoryLayout<SIMD4<Float>>.stride
            )
        }
    }

    func append(column: [Float]) {
        precondition(column.count == rowCount)
        column.withUnsafeBytes { bytes in
            spectrogram.replace(
                region: MTLRegionMake2D(writeIndex, 0, 1, rowCount),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: MemoryLayout<Float>.stride
            )
        }
        writeIndex = (writeIndex + 1) % columnCapacity
        columnsAppended += 1
        let peak = column.max() ?? 0
        brightestColumn = max(brightestColumn, peak)
        if peak > signalThreshold {
            lastSignalTime = CACurrentMediaTime()
        }
    }

    func append(low: Float, high: Float) {
        var pair = SIMD2<Float>(low, high)
        withUnsafeBytes(of: &pair) { bytes in
            envelope.replace(
                region: MTLRegionMake2D(envelopeIndex, 0, 1, 1),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: MemoryLayout<SIMD2<Float>>.stride
            )
        }
        envelopeIndex = (envelopeIndex + 1) % columnCapacity
        columnsAppended += 1
        if max(abs(low), abs(high)) > 0.002 {
            lastSignalTime = CACurrentMediaTime()
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let buffer = commandQueue.makeCommandBuffer(),
            let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        let isWaveform = mode == .waveform
        encoder.setRenderPipelineState(isWaveform ? waveformPipeline : spectrogramPipeline)
        encoder.setFragmentTexture(isWaveform ? envelope : spectrogram, index: 0)
        encoder.setFragmentTexture(palette, index: 1)
        var offset = Float(isWaveform ? envelopeIndex : writeIndex) / Float(columnCapacity)
        encoder.setFragmentBytes(&offset, length: MemoryLayout<Float>.size, index: 0)
        var backgroundColor = background
        encoder.setFragmentBytes(
            &backgroundColor, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
        framesDrawn += 1
    }
}
