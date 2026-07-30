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
                                 constant float4 &background [[buffer(1)]],
                                 constant float &gain [[buffer(2)]]) {
    constexpr sampler wrapSampler(filter::linear, address::repeat);
    constexpr sampler clampSampler(filter::linear, address::clamp_to_edge);
    float u = fract(in.uv.x + writeOffset);
    float2 bounds = clamp(envelope.sample(wrapSampler, float2(u, 0.5)).rg * gain, -1.0, 1.0);

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

fragment float4 fragmentOcean(VertexOut in [[stage_in]],
                              texture2d<float> envelope [[texture(0)]],
                              texture2d<float> palette [[texture(1)]],
                              constant float &writeOffset [[buffer(0)]],
                              constant float4 &background [[buffer(1)]],
                              constant float &gain [[buffer(2)]]) {
    constexpr sampler wrapSampler(filter::linear, address::repeat);
    constexpr sampler clampSampler(filter::linear, address::clamp_to_edge);

    float width = float(envelope.get_width());
    float u = fract(in.uv.x + writeOffset);

    float crestHeight = 0.0;
    float weightSum = 0.0;
    for (int tap = -4; tap <= 4; ++tap) {
        float weight = exp(-float(tap * tap) / 8.0);
        float2 bounds = envelope.sample(wrapSampler, float2(fract(u + float(tap) / width), 0.5)).rg;
        crestHeight += max(abs(bounds.r), abs(bounds.g)) * weight;
        weightSum += weight;
    }
    crestHeight = clamp(crestHeight / weightSum * gain, 0.0, 1.0);

    float y = in.uv.y;
    float edge = fwidth(y) * 1.5 + 0.003;
    float body = 1.0 - smoothstep(crestHeight - edge, crestHeight + edge, y);
    float depth = crestHeight > 0.001 ? clamp(y / crestHeight, 0.0, 1.0) : 0.0;

    float3 color = palette.sample(clampSampler, float2(mix(0.18, 0.95, depth), 0.5)).rgb;
    float crest = exp(-pow((y - crestHeight) / (edge * 5.0), 2.0)) * 0.7;
    float coverage = clamp(body + crest, 0.0, 1.0);
    float3 lit = mix(color, float3(1.0), crest * 0.35);
    return float4(mix(background.rgb, lit, coverage), background.a + (1.0 - background.a) * coverage);
}

constant float spectrumGain = 0.25;

static float2 smoothedBands(texture2d<float> spectrum, sampler bandSampler, float u, float gain) {
    float width = float(spectrum.get_width());
    float2 total = float2(0.0);
    float weightSum = 0.0;
    for (int tap = -2; tap <= 2; ++tap) {
        float weight = exp(-float(tap * tap) / 4.0);
        float position = clamp(u + float(tap) / width, 0.0, 1.0);
        total += spectrum.sample(bandSampler, float2(position, 0.5)).rg * weight;
        weightSum += weight;
    }
    return clamp(total / weightSum * gain * spectrumGain, 0.0, 1.0);
}

fragment float4 fragmentStereo(VertexOut in [[stage_in]],
                               texture2d<float> spectrum [[texture(0)]],
                               texture2d<float> palette [[texture(1)]],
                               constant float &writeOffset [[buffer(0)]],
                               constant float4 &background [[buffer(1)]],
                               constant float &gain [[buffer(2)]]) {
    constexpr sampler clampSampler(filter::linear, address::clamp_to_edge);
    float2 level = smoothedBands(spectrum, clampSampler, in.uv.x, gain);

    float y = in.uv.y * 2.0 - 1.0;
    float limit = y >= 0.0 ? level.r : level.g;
    float edge = fwidth(y) * 1.5 + 0.004;
    float body = 1.0 - smoothstep(limit - edge, limit + edge, abs(y));

    float depth = limit > 0.001 ? clamp(abs(y) / limit, 0.0, 1.0) : 0.0;
    float3 color = palette.sample(clampSampler, float2(mix(0.45, 0.95, depth), 0.5)).rgb;
    color *= y >= 0.0 ? 1.0 : 0.82;

    float axis = exp(-abs(y) / (edge * 2.0)) * 0.4;
    float coverage = clamp(body + axis, 0.0, 1.0);
    float3 lit = mix(color, float3(1.0), axis * 0.4);
    return float4(mix(background.rgb, lit, coverage), background.a + (1.0 - background.a) * coverage);
}

fragment float4 fragmentMorph(VertexOut in [[stage_in]],
                              texture2d<float> spectrum [[texture(0)]],
                              texture2d<float> palette [[texture(1)]],
                              constant float &writeOffset [[buffer(0)]],
                              constant float4 &background [[buffer(1)]],
                              constant float &gain [[buffer(2)]]) {
    constexpr sampler clampSampler(filter::linear, address::clamp_to_edge);
    float2 level = smoothedBands(spectrum, clampSampler, in.uv.x, gain);

    float y = in.uv.y * 2.0 - 1.0;
    float thickness = fwidth(y) * 1.5 + 0.006;

    float leftLine = 1.0 - smoothstep(0.0, thickness, abs(y - level.r));
    float rightLine = 1.0 - smoothstep(0.0, thickness, abs(y + level.g));
    float leftGlow = exp(-pow((y - level.r) / (thickness * 8.0), 2.0)) * 0.35;
    float rightGlow = exp(-pow((y + level.g) / (thickness * 8.0), 2.0)) * 0.25;

    float3 hot = palette.sample(clampSampler, float2(0.85, 0.5)).rgb;
    float3 cool = palette.sample(clampSampler, float2(0.5, 0.5)).rgb;

    float3 color = clamp(cool * (rightLine + rightGlow) + hot * (leftLine + leftGlow), 0.0, 1.0);
    float coverage = clamp(leftLine + rightLine + leftGlow + rightGlow, 0.0, 1.0);
    return float4(mix(background.rgb, color, coverage), background.a + (1.0 - background.a) * coverage);
}
"""

final class SpectrogramRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let spectrogramPipeline: MTLRenderPipelineState
    private let waveformPipeline: MTLRenderPipelineState
    private let oceanPipeline: MTLRenderPipelineState
    private let stereoPipeline: MTLRenderPipelineState
    private let morphPipeline: MTLRenderPipelineState
    private let spectrogram: MTLTexture
    private let envelope: MTLTexture
    private let bands: MTLTexture
    private var palette: MTLTexture
    private let columnCapacity: Int
    private let rowCount: Int
    private var writeIndex = 0
    private var envelopeIndex = 0

    var mode: Visualization = .spectrogram
    var background = SIMD4<Float>(0, 0, 0, 1)
    var gain: Float = 4

    private(set) var columnsAppended = 0
    private(set) var framesDrawn = 0
    private(set) var brightestColumn: Float = 0
    private(set) var scopePeak: Float = 0

    private let idleAfter: CFTimeInterval = 12
    private let signalThreshold: Float = 0.2
    private var lastSignalTime = CACurrentMediaTime()

    var hasScrolledToSilence: Bool {
        CACurrentMediaTime() - lastSignalTime > idleAfter
    }

    init?(rowCount: Int, columnCapacity: Int = 1024, bandCount: Int = 128) {
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

            descriptor.fragmentFunction = library.makeFunction(name: "fragmentOcean")
            oceanPipeline = try device.makeRenderPipelineState(descriptor: descriptor)

            descriptor.fragmentFunction = library.makeFunction(name: "fragmentStereo")
            stereoPipeline = try device.makeRenderPipelineState(descriptor: descriptor)

            descriptor.fragmentFunction = library.makeFunction(name: "fragmentMorph")
            morphPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
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

        let bandDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg32Float,
            width: bandCount,
            height: 1,
            mipmapped: false
        )
        bandDescriptor.usage = .shaderRead
        bandDescriptor.storageMode = .shared
        guard let bands = device.makeTexture(descriptor: bandDescriptor) else { return nil }
        self.bands = bands

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

    func update(spectrum: [SIMD2<Float>]) {
        guard !spectrum.isEmpty else { return }

        spectrum.withUnsafeBytes { bytes in
            bands.replace(
                region: MTLRegionMake2D(0, 0, spectrum.count, 1),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: spectrum.count * MemoryLayout<SIMD2<Float>>.stride
            )
        }

        columnsAppended += 1
        var peak: Float = 0
        for value in spectrum {
            peak = max(peak, max(value.x, value.y))
        }
        scopePeak = peak
        if peak > 0.01 {
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

        let pipeline: MTLRenderPipelineState
        let source: MTLTexture
        switch mode {
        case .spectrogram: (pipeline, source) = (spectrogramPipeline, spectrogram)
        case .waveform: (pipeline, source) = (waveformPipeline, envelope)
        case .ocean: (pipeline, source) = (oceanPipeline, envelope)
        case .stereo: (pipeline, source) = (stereoPipeline, bands)
        case .morph: (pipeline, source) = (morphPipeline, bands)
        }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentTexture(palette, index: 1)

        var offset: Float
        switch mode.source {
        case .spectrum: offset = Float(writeIndex) / Float(columnCapacity)
        case .envelope: offset = Float(envelopeIndex) / Float(columnCapacity)
        case .stereoSpectrum: offset = 0
        }
        encoder.setFragmentBytes(&offset, length: MemoryLayout<Float>.size, index: 0)
        var backgroundColor = background
        encoder.setFragmentBytes(
            &backgroundColor, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
        var gainValue = gain
        encoder.setFragmentBytes(&gainValue, length: MemoryLayout<Float>.size, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
        framesDrawn += 1
    }
}
