import AppKit
import QuartzCore
import simd

final class StripVisualizationView: NSView {
    private enum DisplayState {
        case active
        case idle
        case paused
    }

    private let idleTimeout: CFTimeInterval = 1.5
    private let signalThreshold: Float = 0.2

    var redrawInterval: CFTimeInterval = 1.0 / 20
    var mode: Visualization = .spectrogram { didSet { needsDisplay = true } }
    var fadeWidth: CGFloat = 6 { didSet { needsDisplay = true } }
    var opacity: CGFloat = 1 { didSet { needsDisplay = true } }
    var gain: Float = 4 { didSet { needsDisplay = true } }
    var showsIdleIndicator = true

    private var rows: Int
    private var columnCount: Int
    private var intensities: [Float]
    private var envelopes: [SIMD2<Float>]
    private var levels: [SIMD2<Float>]
    private var pixels: [UInt8]
    private var writeIndex = 0
    private var lastRedraw: CFTimeInterval = 0
    private var lastSignal: CFTimeInterval = 0
    private var isPaused = false
    private var heartbeat: Timer?
    private var lookup = Palette.magma.lookupTable()

    override var isFlipped: Bool { true }

    private var state: DisplayState {
        if isPaused { return .paused }
        return CACurrentMediaTime() - lastSignal > idleTimeout ? .idle : .active
    }

    init(width: CGFloat, height: CGFloat) {
        rows = max(8, Int(height) - 4)
        columnCount = max(16, Int(width))
        intensities = [Float](repeating: 0, count: columnCount * rows)
        envelopes = [SIMD2<Float>](repeating: .zero, count: columnCount)
        levels = [SIMD2<Float>](repeating: .zero, count: columnCount)
        pixels = [UInt8](repeating: 0, count: columnCount * rows * 4)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.state != .active else { return }
            self.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
    }

    required init?(coder: NSCoder) { nil }

    deinit { heartbeat?.invalidate() }

    func resize(width: CGFloat, height: CGFloat) {
        let newColumns = max(16, Int(width))
        let newRows = max(8, Int(height) - 4)
        guard newColumns != columnCount || newRows != rows else { return }
        columnCount = newColumns
        rows = newRows
        intensities = [Float](repeating: 0, count: columnCount * rows)
        envelopes = [SIMD2<Float>](repeating: .zero, count: columnCount)
        levels = [SIMD2<Float>](repeating: .zero, count: columnCount)
        pixels = [UInt8](repeating: 0, count: columnCount * rows * 4)
        writeIndex = 0
        needsDisplay = true
    }

    func apply(palette: Palette) {
        lookup = palette.lookupTable()
        needsDisplay = true
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        if paused {
            for index in intensities.indices { intensities[index] = 0 }
            for index in envelopes.indices { envelopes[index] = .zero }
            for index in levels.indices { levels[index] = .zero }
        }
        lastSignal = 0
        needsDisplay = true
    }

    func append(column: [Float]) {
        guard !isPaused, mode.source == .spectrum else { return }
        if (column.max() ?? 0) > signalThreshold {
            lastSignal = CACurrentMediaTime()
        }
        let bucketSize = max(1, column.count / rows)
        for row in 0..<rows {
            let start = min(column.count - 1, row * bucketSize)
            let end = min(column.count, start + bucketSize)
            var peak: Float = 0
            for index in start..<end {
                peak = max(peak, column[index])
            }
            intensities[writeIndex * rows + row] = peak
        }
        advance()
    }

    func append(low: Float, high: Float) {
        guard !isPaused, mode.source == .envelope else { return }
        if max(abs(low), abs(high)) > 0.002 {
            lastSignal = CACurrentMediaTime()
        }
        envelopes[writeIndex] = SIMD2(low, high)
        advance()
    }

    func update(spectrum: [SIMD2<Float>]) {
        guard !isPaused, mode.source == .stereoSpectrum, !spectrum.isEmpty else { return }

        var peak: Float = 0
        for column in 0..<columnCount {
            let start = column * spectrum.count / columnCount
            let end = min(
                spectrum.count, max(start + 1, (column + 1) * spectrum.count / columnCount))
            var highest = SIMD2<Float>.zero
            for index in start..<end {
                highest = simd_max(highest, spectrum[index])
            }
            levels[column] = highest
            peak = max(peak, max(highest.x, highest.y))
        }

        if peak > 0.01 {
            lastSignal = CACurrentMediaTime()
        }
        throttledRedraw()
    }

    private func advance() {
        writeIndex = (writeIndex + 1) % columnCount
        throttledRedraw()
    }

    private func throttledRedraw() {
        let now = CACurrentMediaTime()
        guard now - lastRedraw >= redrawInterval else { return }
        lastRedraw = now
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        if state == .paused {
            if showsIdleIndicator { drawPausedGlyph(in: context) }
            return
        }

        if showsIdleIndicator { drawBaseline(in: context) }
        guard state == .active else { return }

        switch mode {
        case .spectrogram: fillSpectrogramPixels()
        case .waveform: fillWaveformPixels()
        case .ocean: fillOceanPixels()
        case .stereo: fillStereoPixels()
        case .morph: fillMorphPixels()
        }
        applyEdgeFade()

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
            let image = CGImage(
                width: columnCount,
                height: rows,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: columnCount * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else { return }

        context.interpolationQuality = .none
        context.draw(image, in: bounds.insetBy(dx: 1, dy: 2))
    }

    private func writePixel(column: Int, row: Int, color: SIMD4<Float>, alpha: Float) {
        let scaled = alpha * Float(opacity)
        let offset = ((rows - 1 - row) * columnCount + column) * 4
        pixels[offset] = UInt8(max(0, min(255, color.x * scaled * 255)))
        pixels[offset + 1] = UInt8(max(0, min(255, color.y * scaled * 255)))
        pixels[offset + 2] = UInt8(max(0, min(255, color.z * scaled * 255)))
        pixels[offset + 3] = UInt8(max(0, min(255, scaled * 255)))
    }

    private func fillSpectrogramPixels() {
        for column in 0..<columnCount {
            let source = (writeIndex + column) % columnCount
            for row in 0..<rows {
                let intensity = intensities[source * rows + row]
                let color = lookup[max(0, min(255, Int(intensity * 255)))]
                writePixel(column: column, row: row, color: color, alpha: min(1, intensity * 1.6))
            }
        }
    }

    private func fillWaveformPixels() {
        for index in pixels.indices { pixels[index] = 0 }
        let centre = Float(rows - 1) / 2

        for column in 0..<columnCount {
            let source = (writeIndex + column) % columnCount
            let envelope = envelopes[source] * gain
            let amplitude = min(1, max(abs(envelope.x), abs(envelope.y)))
            let color = lookup[max(0, min(255, Int(amplitude * 255)))]

            let top = centre - min(1, max(0, envelope.y)) * centre
            let bottom = centre - max(-1, min(0, envelope.x)) * centre
            let first = max(0, Int(top.rounded(.down)))
            let last = min(rows - 1, Int(bottom.rounded(.up)))
            guard first <= last else { continue }

            for row in first...last {
                writePixel(column: column, row: row, color: color, alpha: max(0.35, amplitude))
            }
        }
    }

    private func fillOceanPixels() {
        for index in pixels.indices { pixels[index] = 0 }

        var heights = [Float](repeating: 0, count: columnCount)
        for column in 0..<columnCount {
            var total: Float = 0
            var weightSum: Float = 0
            for tap in -3...3 {
                let source = (writeIndex + column + tap + columnCount * 2) % columnCount
                let weight = exp(-Float(tap * tap) / 6)
                let envelope = envelopes[source]
                total += max(abs(envelope.x), abs(envelope.y)) * weight
                weightSum += weight
            }
            heights[column] = min(1, total / weightSum * gain)
        }

        for column in 0..<columnCount {
            let crest = heights[column] * Float(rows)
            guard crest > 0 else { continue }
            let top = rows - 1 - Int(crest.rounded(.down))
            for row in max(0, top)..<rows {
                let depth = Float(rows - 1 - row) / max(crest, 0.001)
                let shade = min(0.95, 0.18 + depth * 0.77)
                let color = lookup[max(0, min(255, Int(shade * 255)))]
                let isCrest = row == max(0, top)
                writePixel(
                    column: column, row: rows - 1 - row, color: color,
                    alpha: isCrest ? 1 : max(0.45, heights[column]))
            }
        }
    }

    private func smoothedLevel(at column: Int) -> SIMD2<Float> {
        var total = SIMD2<Float>.zero
        var weightSum: Float = 0
        for tap in -2...2 {
            let index = min(columnCount - 1, max(0, column + tap))
            let weight = exp(-Float(tap * tap) / 4)
            total += levels[index] * weight
            weightSum += weight
        }
        return simd_clamp(total / weightSum * gain * 0.25, .zero, SIMD2(repeating: 1))
    }

    private func fillStereoPixels() {
        for index in pixels.indices { pixels[index] = 0 }
        let centre = Float(rows - 1) / 2

        for column in 0..<columnCount {
            let level = smoothedLevel(at: column)
            let top = max(0, Int((centre - level.x * centre).rounded(.down)))
            let bottom = min(rows - 1, Int((centre + level.y * centre).rounded(.up)))
            guard top <= bottom else { continue }

            for row in top...bottom {
                let isLower = Float(row) > centre
                let limit = isLower ? level.y : level.x
                let distance = abs(Float(row) - centre) / max(centre, 0.001)
                let depth = limit > 0.001 ? min(1, distance / limit) : 0
                let shade = 0.45 + depth * 0.5
                var color = lookup[max(0, min(255, Int(shade * 255)))]
                if isLower { color *= 0.82 }
                writePixel(column: column, row: row, color: color, alpha: max(0.4, limit))
            }
        }
    }

    private func fillMorphPixels() {
        for index in pixels.indices { pixels[index] = 0 }
        let centre = Float(rows - 1) / 2
        let hot = lookup[217]
        let cool = lookup[128]
        var previous: SIMD2<Int>?

        for column in 0..<columnCount {
            let level = smoothedLevel(at: column)
            let current = SIMD2(
                row(for: level.x, centre: centre), row(for: -level.y, centre: centre))
            let start = previous ?? current

            drawSegment(column: column, from: start.y, to: current.y, color: cool, alpha: 0.75)
            drawSegment(column: column, from: start.x, to: current.x, color: hot, alpha: 1)
            previous = current
        }
    }

    private func row(for value: Float, centre: Float) -> Int {
        let clamped = max(-1, min(1, value))
        return max(0, min(rows - 1, Int((centre - clamped * centre).rounded())))
    }

    private func drawSegment(
        column: Int, from: Int, to: Int, color: SIMD4<Float>, alpha: Float
    ) {
        for row in min(from, to)...max(from, to) {
            writePixel(column: column, row: row, color: color, alpha: alpha)
        }
    }

    private func applyEdgeFade() {
        guard fadeWidth > 0 else { return }
        let fadeColumns = Int((fadeWidth / max(bounds.width, 1)) * CGFloat(columnCount))
        guard fadeColumns > 0 else { return }

        for column in 0..<min(fadeColumns, columnCount / 2) {
            let ramp = Float(column) / Float(fadeColumns)
            for row in 0..<rows {
                for edge in [column, columnCount - 1 - column] {
                    let offset = ((rows - 1 - row) * columnCount + edge) * 4
                    for channel in 0..<4 {
                        pixels[offset + channel] = UInt8(Float(pixels[offset + channel]) * ramp)
                    }
                }
            }
        }
    }

    private var baselineFraction: CGFloat {
        switch mode {
        case .spectrogram, .ocean: return 1
        case .waveform, .stereo, .morph: return 0.5
        }
    }

    private func drawBaseline(in context: CGContext) {
        let area = bounds.insetBy(dx: 1, dy: 2)
        let position = area.minY + (area.height - 1) * baselineFraction
        context.setFillColor(NSColor.tertiaryLabelColor.cgColor)
        context.fill(CGRect(x: area.minX, y: position, width: area.width, height: 1))
    }

    private func drawPausedGlyph(in context: CGContext) {
        let area = bounds.insetBy(dx: 1, dy: 2)
        context.setFillColor(NSColor.tertiaryLabelColor.cgColor)
        let barWidth: CGFloat = 2
        let barHeight = area.height * 0.55
        let gap: CGFloat = 3
        let originY = area.midY - barHeight / 2
        context.fill(
            CGRect(x: area.midX - gap / 2 - barWidth, y: originY, width: barWidth, height: barHeight))
        context.fill(CGRect(x: area.midX + gap / 2, y: originY, width: barWidth, height: barHeight))
    }
}
