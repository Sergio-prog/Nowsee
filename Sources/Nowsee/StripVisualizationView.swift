import AppKit
import NowseeCore
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
    private let redrawTolerance: CFTimeInterval = 0.85

    var redrawInterval: CFTimeInterval = 1.0 / 20
    var mode: Visualization = .spectrogram { didSet { invalidateIfChanged(mode != oldValue) } }
    var fadeWidth: CGFloat = 6 { didSet { invalidateIfChanged(fadeWidth != oldValue) } }
    var opacity: CGFloat = 1 { didSet { invalidateIfChanged(opacity != oldValue) } }
    var gain: Float = 4 { didSet { invalidateIfChanged(gain != oldValue) } }
    var smoothing: Float = 0.55 { didSet { invalidateIfChanged(smoothing != oldValue) } }
    var barCount = 56 { didSet { invalidateIfChanged(barCount != oldValue) } }
    var barGap: Float = 0.16 { didSet { invalidateIfChanged(barGap != oldValue) } }
    var backgroundOpacity: CGFloat = 0 {
        didSet { invalidateIfChanged(backgroundOpacity != oldValue) }
    }
    var cornerRadius: CGFloat = 0 {
        didSet {
            guard cornerRadius != oldValue else { return }
            if cornerRadius > 0 { wantsLayer = true }
            layer?.cornerRadius = cornerRadius
            layer?.masksToBounds = cornerRadius > 0
        }
    }
    var showsIdleIndicator = true
    var isPreview = false
    var baselineTint: NSColor? { didSet { invalidateIfChanged(baselineTint != oldValue) } }
    var baselineOpacity: CGFloat = 1 { didSet { invalidateIfChanged(baselineOpacity != oldValue) } }
    var standbyIntensity: CGFloat = 0.6 { didSet { invalidateIfChanged(standbyIntensity != oldValue) } }
    var standby: StandbyAnimation = .breathe {
        didSet {
            guard standby != oldValue else { return }
            restartHeartbeat()
            needsDisplay = true
        }
    }

    private var rows: Int
    private var columnCount: Int
    private var intensities: [Float]
    private var envelopes: [SIMD2<Float>]
    private var levels: [SIMD4<Float>]
    private var magnitudes: [Float]
    private var heights: [Float]
    private var pixels: UnsafeMutablePointer<UInt8>
    private var pixelCount: Int
    private var bitmap: CGContext?
    private var writeIndex = 0
    private var lastRedraw: CFTimeInterval = 0
    private var lastSignal: CFTimeInterval = 0
    private var isPaused = false
    private var heartbeat: Timer?
    private var palette = Palette.magma
    private var lookup = Palette.magma.lookupTable()

    override var isFlipped: Bool { true }

    var isActive: Bool { state == .active }

    private(set) var drawsCompleted = 0
    private var idleFramesDrawn = 0

    private var state: DisplayState {
        if isPaused { return .paused }
        return CACurrentMediaTime() - lastSignal > idleTimeout ? .idle : .active
    }

    init(width: CGFloat, height: CGFloat) {
        rows = max(8, Int(height) - 4)
        columnCount = max(16, Int(width))
        intensities = [Float](repeating: 0, count: columnCount * rows)
        envelopes = [SIMD2<Float>](repeating: .zero, count: columnCount)
        levels = [SIMD4<Float>](repeating: .zero, count: columnCount)
        magnitudes = [Float](repeating: 0, count: columnCount)
        heights = [Float](repeating: 0, count: columnCount)
        pixelCount = columnCount * rows * 4
        pixels = .allocate(capacity: pixelCount)
        pixels.initialize(repeating: 0, count: pixelCount)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))

        makeBitmap()

        restartHeartbeat()
    }

    private func restartHeartbeat() {
        heartbeat?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: standbyTick, repeats: true) {
            [weak self] _ in
            guard let self, self.state != .active else { return }
            self.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
    }

    private var standbyTick: TimeInterval {
        standby.animates ? 1.0 / 12 : 0.5
    }

    private var standbyAmplitude: CGFloat {
        standby == .wave ? standbyIntensity * min(6, bounds.height * 0.2) : 0
    }

    private var standbyBand: NSRect {
        let area = bounds.insetBy(dx: 1, dy: 2)
        let resting = area.minY + (area.height - 1) * baselineFraction
        let padding = standbyAmplitude + 2
        let top = max(area.minY, resting - padding)
        return NSRect(
            x: area.minX, y: top, width: area.width,
            height: min(area.maxY - top, padding * 2 + 1))
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        heartbeat?.invalidate()
        pixels.deallocate()
    }

    private func invalidateIfChanged(_ changed: Bool) {
        if changed { needsDisplay = true }
    }

    private func makeBitmap() {
        bitmap = CGContext(
            data: pixels,
            width: columnCount,
            height: rows,
            bitsPerComponent: 8,
            bytesPerRow: columnCount * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    func resize(width: CGFloat, height: CGFloat) {
        let newColumns = max(16, Int(width))
        let newRows = max(8, Int(height) - 4)
        guard newColumns != columnCount || newRows != rows else { return }
        columnCount = newColumns
        rows = newRows
        intensities = [Float](repeating: 0, count: columnCount * rows)
        envelopes = [SIMD2<Float>](repeating: .zero, count: columnCount)
        levels = [SIMD4<Float>](repeating: .zero, count: columnCount)
        magnitudes = [Float](repeating: 0, count: columnCount)
        heights = [Float](repeating: 0, count: columnCount)

        pixels.deallocate()
        pixelCount = columnCount * rows * 4
        pixels = .allocate(capacity: pixelCount)
        pixels.initialize(repeating: 0, count: pixelCount)
        makeBitmap()

        writeIndex = 0
        needsDisplay = true
    }

    func apply(palette newPalette: Palette) {
        guard newPalette != palette else { return }
        palette = newPalette
        lookup = newPalette.lookupTable()
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

    func update(spectrum: [SIMD4<Float>]) {
        guard !isPaused, mode.source == .stereoSpectrum, !spectrum.isEmpty else { return }

        var peak: Float = 0
        for column in 0..<columnCount {
            let start = column * spectrum.count / columnCount
            let end = min(
                spectrum.count, max(start + 1, (column + 1) * spectrum.count / columnCount))
            var highest = SIMD4<Float>.zero
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
        guard now - lastRedraw >= redrawInterval * redrawTolerance else { return }
        lastRedraw = now
        if state == .active {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        drawsCompleted += 1
        idleFramesDrawn = state == .idle ? idleFramesDrawn + 1 : 0

        if backgroundOpacity > 0 {
            context.setFillColor(CGColor(gray: 0, alpha: backgroundOpacity))
            context.fill(bounds)
        }

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
        case .bars: fillBarsPixels()
        case .stereo: fillStereoPixels()
        case .morph: fillMorphPixels()
        }
        applyEdgeFade()

        guard let image = bitmap?.makeImage() else { return }
        context.interpolationQuality = .none
        context.draw(image, in: bounds.insetBy(dx: 1, dy: 2))
    }

    private func clear() {
        memset(pixels, 0, pixelCount)
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
        clear()
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
        clear()

        for column in 0..<columnCount {
            let envelope = envelopes[column]
            magnitudes[column] = max(abs(envelope.x), abs(envelope.y))
        }
        EnvelopeSmoother(smoothing: smoothing, width: columnCount)
            .smooth(magnitudes, startIndex: writeIndex, gain: gain, into: &heights)

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

    private func scaledLevel(at column: Int) -> SIMD4<Float> {
        simd_clamp(levels[column] * gain * 0.25, .zero, SIMD4(repeating: 1))
    }

    private func fillBarsPixels() {
        clear()

        let slots = max(4, min(barCount, columnCount / 2))
        let slotWidth = Float(columnCount) / Float(slots)
        let gapColumns = slotWidth * barGap

        for slot in 0..<slots {
            let slotStart = Float(slot) * slotWidth
            let start = Int((slotStart + gapColumns * 0.5).rounded())
            let end = min(columnCount, Int((slotStart + slotWidth - gapColumns * 0.5).rounded()))
            guard start < end else { continue }

            let sample = min(columnCount - 1, Int(slotStart + slotWidth * 0.5))
            let value = scaledLevel(at: sample)
            let height = max(value.x, value.y)
            let cap = max(value.z, value.w)

            let filled = height * Float(rows)
            let capRow = rows - 1 - Int((cap * Float(rows - 1)).rounded())

            for column in start..<end {
                if capRow >= 0, capRow < rows {
                    writePixel(column: column, row: capRow, color: lookup[250], alpha: 1)
                }
                for row in 0..<rows {
                    let fromBottom = Float(rows - row)
                    let coverage = min(1, max(0, filled - fromBottom + 1))
                    guard coverage > 0 else { continue }
                    let depth = Float(rows - 1 - row) / max(filled, 0.001)
                    let shade = 0.35 + min(1, depth) * 0.6
                    let color = lookup[max(0, min(255, Int(shade * 255)))]
                    writePixel(
                        column: column, row: row, color: color,
                        alpha: max(0.45, height) * coverage)
                }
            }
        }
    }

    private func fillStereoPixels() {
        clear()
        let centre = Float(rows - 1) / 2

        for column in 0..<columnCount {
            let level = scaledLevel(at: column)

            for row in 0..<rows {
                let isLower = Float(row) > centre
                let limit = isLower ? level.y : level.x
                let distance = abs(Float(row) - centre) / max(centre, 0.001)
                let coverage = min(1, max(0, (limit - distance) * centre + 0.5))
                guard coverage > 0 else { continue }

                let depth = limit > 0.001 ? min(1, distance / limit) : 0
                let shade = 0.45 + depth * 0.5
                var color = lookup[max(0, min(255, Int(shade * 255)))]
                if isLower { color *= 0.82 }
                writePixel(
                    column: column, row: row, color: color,
                    alpha: max(0.4, limit) * coverage)
            }
        }
    }

    private func fillMorphPixels() {
        clear()
        let centre = Float(rows - 1) / 2
        let hot = lookup[217]
        let cool = lookup[128]
        var previous: SIMD2<Int>?

        for column in 0..<columnCount {
            let level = scaledLevel(at: column)
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
        mode.baselineAtBottom ? 1 : 0.5
    }

    private var baselineCGColor: CGColor {
        let resolved = (baselineTint ?? .tertiaryLabelColor).cgColor
        let alpha = resolved.alpha * baselineOpacity
        return resolved.copy(alpha: max(0, min(1, alpha))) ?? resolved
    }

    private func drawBaseline(in context: CGContext) {
        let area = bounds.insetBy(dx: 1, dy: 2)
        let resting = area.minY + (area.height - 1) * baselineFraction
        let color = baselineCGColor

        guard standby.animates, state == .idle else {
            context.setFillColor(color)
            context.fill(CGRect(x: area.minX, y: resting, width: area.width, height: 1))
            return
        }
        drawStandby(in: context, area: area, resting: resting, color: color)
    }

    private func drawStandby(
        in context: CGContext, area: CGRect, resting: CGFloat, color: CGColor
    ) {
        let time = CACurrentMediaTime()
        let strength = max(0, min(1, standbyIntensity))

        switch standby {
        case .off:
            break

        case .breathe:
            let pulse = 0.5 + 0.5 * sin(time * 1.1)
            let scale = 1 - strength + strength * (0.18 + 0.82 * pulse)
            let faded = color.copy(alpha: max(0, min(1, color.alpha * scale))) ?? color
            context.setFillColor(faded)
            context.fill(CGRect(x: area.minX, y: resting, width: area.width, height: 1))

        case .wave:
            let amplitude = standbyAmplitude
            let anchor = min(max(resting, area.minY + amplitude + 1), area.maxY - amplitude - 1)
            let steps = max(24, Int(area.width))
            context.setStrokeColor(color)
            context.setLineWidth(1)
            context.setLineJoin(.round)
            context.beginPath()
            for step in 0...steps {
                let fraction = CGFloat(step) / CGFloat(steps)
                let taper = sin(fraction * .pi)
                let offset = amplitude * taper * sin(fraction * .pi * 5 + time * 1.2)
                let point = CGPoint(x: area.minX + fraction * area.width, y: anchor + offset)
                if step == 0 { context.move(to: point) } else { context.addLine(to: point) }
            }
            context.strokePath()

        case .sweep:
            let head = CGFloat((time * 0.22).truncatingRemainder(dividingBy: 1))
            let segment: CGFloat = 2
            var offset: CGFloat = 0
            while offset < area.width {
                let fraction = (offset + segment / 2) / area.width
                var distance = abs(fraction - head)
                distance = min(distance, 1 - distance)
                let glow = exp(-pow(distance / 0.12, 2))
                let scale = 0.22 + 0.78 * glow * strength
                let lit = color.copy(alpha: max(0, min(1, color.alpha * scale))) ?? color
                context.setFillColor(lit)
                context.fill(
                    CGRect(
                        x: area.minX + offset, y: resting,
                        width: min(segment, area.width - offset), height: 1))
                offset += segment
            }
        }
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
