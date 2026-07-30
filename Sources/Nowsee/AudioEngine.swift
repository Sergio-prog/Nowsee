import Foundation
import NowseeCore
import QuartzCore
import simd

final class AudioEngine {
    static let rowCount = 256
    static let bandCount = 128
    private static let drainTick = 0.016

    private let tap = SystemAudioTap()
    private let ring = AudioRingBuffer()
    private let leftRing = AudioRingBuffer(capacity: 1 << 15)
    private let rightRing = AudioRingBuffer(capacity: 1 << 15)
    private var spectrum: SpectrumAnalyzer?
    private var waveform: WaveformAnalyzer?
    private var stereoSpectrum: StereoSpectrumAnalyzer?
    private var timer: DispatchSourceTimer?
    private var synthetic: DispatchSourceTimer?
    private var lastScopeEmit: CFTimeInterval = 0

    var visualization: Visualization = .spectrogram
    var frameRate = 30
    var smoothing: Float = 0.55 { didSet { stereoSpectrum?.smoothing = smoothing } }
    var onColumn: (([Float]) -> Void)?
    var onEnvelope: ((Float, Float) -> Void)?
    var onSpectrumBands: (([SIMD4<Float>]) -> Void)?
    var onStatus: ((String) -> Void)?
    var onReconfigure: ((String) -> Void)?

    private(set) var isRunning = false

    func start() {
        tap.onStereoAudio = { [weak self] left, right, count in
            self?.leftRing.write(left, count)
            self?.rightRing.write(right, count)
        }

        do {
            try tap.start { [weak self] samples, count in
                self?.ring.write(samples, count)
            }
        } catch {
            onStatus?("Capture failed — \(error)")
            return
        }

        tap.onOutputDeviceChange = { [weak self] _ in
            DispatchQueue.main.async { self?.rebuildAnalyzers() }
        }
        tap.onReconfigure = { [weak self] reason in
            DispatchQueue.main.async { self?.onReconfigure?(reason) }
        }
        rebuildAnalyzers()
        startDrainTimer()
        isRunning = true
    }

    func stop() {
        timer?.cancel()
        timer = nil
        tap.stop()
        isRunning = false
    }

    private func rebuildAnalyzers() {
        guard let info = tap.streamInfo else {
            onStatus?("No output device")
            return
        }
        spectrum = SpectrumAnalyzer(
            ring: ring, sampleRate: info.sampleRate, rowCount: Self.rowCount)
        waveform = WaveformAnalyzer(ring: ring)
        stereoSpectrum = StereoSpectrumAnalyzer(
            left: leftRing, right: rightRing, sampleRate: info.sampleRate,
            bandCount: Self.bandCount)
        stereoSpectrum?.smoothing = smoothing
        onStatus?("\(info.outputDeviceName) · \(Int(info.sampleRate / 1000)) kHz")
    }

    private func startDrainTimer() {
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: Self.drainTick)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            switch self.visualization.source {
            case .spectrum:
                self.spectrum?.drainColumns { self.onColumn?($0) }
            case .envelope:
                self.waveform?.drainEnvelopes { self.onEnvelope?($0, $1) }
            case .stereoSpectrum:
                self.emitBandsIfDue()
            }
        }
        source.resume()
        timer = source
    }

    func startSyntheticSignal() {
        let block = 480
        var phase = 0
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: .milliseconds(10))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var left = [Float](repeating: 0, count: block)
            var right = [Float](repeating: 0, count: block)
            var mono = [Float](repeating: 0, count: block)

            for index in 0..<block {
                let position = Float(phase + index)
                left[index] = sin(position * 2 * .pi / 240) * 0.6
                right[index] = sin(position * 2 * .pi / 160) * 0.3
                mono[index] = (left[index] + right[index]) * 0.5
            }
            phase += block

            left.withUnsafeBufferPointer { self.leftRing.write($0.baseAddress!, block) }
            right.withUnsafeBufferPointer { self.rightRing.write($0.baseAddress!, block) }
            mono.withUnsafeBufferPointer { self.ring.write($0.baseAddress!, block) }
        }
        source.resume()
        synthetic = source

        if stereoSpectrum == nil {
            stereoSpectrum = StereoSpectrumAnalyzer(
                left: leftRing, right: rightRing, sampleRate: 48000, bandCount: Self.bandCount)
            stereoSpectrum?.smoothing = smoothing
            waveform = WaveformAnalyzer(ring: ring)
            spectrum = SpectrumAnalyzer(ring: ring, sampleRate: 48000, rowCount: Self.rowCount)
            startDrainTimer()
        }
    }

    func simulateReconfiguration() {
        tap.simulateReconfiguration()
    }

    private func emitBandsIfDue() {
        let now = CACurrentMediaTime()
        let interval = 1.0 / Double(max(frameRate, 1)) - Self.drainTick / 2
        guard now - lastScopeEmit >= interval else { return }
        lastScopeEmit = now
        stereoSpectrum?.snapshot { levels in onSpectrumBands?(levels) }
    }
}
