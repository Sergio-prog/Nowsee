import AppKit
import QuartzCore
import simd

final class MenuBarSpectrogramView: NSView {
    private enum DisplayState {
        case active
        case idle
        case paused
    }

    private let columnCount = 68
    private let rows = 18
    private let idleTimeout: CFTimeInterval = 1.5
    private let signalThreshold: Float = 0.2

    var redrawInterval: CFTimeInterval = 1.0 / 20
    private var intensities: [Float]
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

    init() {
        intensities = [Float](repeating: 0, count: columnCount * rows)
        pixels = [UInt8](repeating: 0, count: columnCount * rows * 4)
        super.init(frame: NSRect(x: 0, y: 0, width: 72, height: 22))

        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.state != .active else { return }
            self.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
    }

    required init?(coder: NSCoder) { nil }

    deinit { heartbeat?.invalidate() }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        if paused {
            for index in intensities.indices { intensities[index] = 0 }
        }
        lastSignal = 0
        needsDisplay = true
    }

    func apply(palette: Palette) {
        lookup = palette.lookupTable()
        needsDisplay = true
    }

    func append(column: [Float]) {
        guard !isPaused else { return }
        if (column.max() ?? 0) > signalThreshold {
            lastSignal = CACurrentMediaTime()
        }
        let bucketSize = max(1, column.count / rows)
        for row in 0..<rows {
            let start = row * bucketSize
            let end = min(column.count, start + bucketSize)
            var peak: Float = 0
            for index in start..<end {
                peak = max(peak, column[index])
            }
            intensities[writeIndex * rows + row] = peak
        }
        writeIndex = (writeIndex + 1) % columnCount

        let now = CACurrentMediaTime()
        guard now - lastRedraw >= redrawInterval else { return }
        lastRedraw = now
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        switch state {
        case .paused:
            drawPausedGlyph(in: context)
            return
        case .idle:
            drawIdleLine(in: context)
            return
        case .active:
            break
        }

        for column in 0..<columnCount {
            let source = (writeIndex + column) % columnCount
            for row in 0..<rows {
                let intensity = intensities[source * rows + row]
                let color = lookup[max(0, min(255, Int(intensity * 255)))]
                let alpha = min(1, intensity * 1.6)
                let offset = ((rows - 1 - row) * columnCount + column) * 4
                pixels[offset] = UInt8(color.x * alpha * 255)
                pixels[offset + 1] = UInt8(color.y * alpha * 255)
                pixels[offset + 2] = UInt8(color.z * alpha * 255)
                pixels[offset + 3] = UInt8(alpha * 255)
            }
        }

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
        context.draw(image, in: bounds.insetBy(dx: 2, dy: 3))
    }

    private func drawIdleLine(in context: CGContext) {
        let area = bounds.insetBy(dx: 2, dy: 3)
        context.setFillColor(NSColor.tertiaryLabelColor.cgColor)
        context.fill(
            CGRect(x: area.minX, y: area.midY - 0.5, width: area.width, height: 1))
    }

    private func drawPausedGlyph(in context: CGContext) {
        let area = bounds.insetBy(dx: 2, dy: 3)
        context.setFillColor(NSColor.tertiaryLabelColor.cgColor)
        let barWidth: CGFloat = 2
        let barHeight = area.height * 0.55
        let gap: CGFloat = 3
        let originY = area.midY - barHeight / 2
        let leftX = area.midX - gap / 2 - barWidth
        context.fill(CGRect(x: leftX, y: originY, width: barWidth, height: barHeight))
        context.fill(CGRect(x: area.midX + gap / 2, y: originY, width: barWidth, height: barHeight))
    }
}
