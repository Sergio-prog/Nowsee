import Foundation
import NowseeCore

final class AudioEngine {
    static let rowCount = 256

    private let tap = SystemAudioTap()
    private let ring = AudioRingBuffer()
    private var spectrum: SpectrumAnalyzer?
    private var waveform: WaveformAnalyzer?
    private var timer: DispatchSourceTimer?

    var visualization: Visualization = .spectrogram
    var onColumn: (([Float]) -> Void)?
    var onEnvelope: ((Float, Float) -> Void)?
    var onStatus: ((String) -> Void)?

    private(set) var isRunning = false

    func start() {
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
        onStatus?("\(info.outputDeviceName) · \(Int(info.sampleRate / 1000)) kHz")
    }

    private func startDrainTimer() {
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: .milliseconds(16))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            switch self.visualization {
            case .spectrogram:
                self.spectrum?.drainColumns { self.onColumn?($0) }
            case .waveform:
                self.waveform?.drainEnvelopes { self.onEnvelope?($0, $1) }
            }
        }
        source.resume()
        timer = source
    }
}
