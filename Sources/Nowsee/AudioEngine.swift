import Foundation
import NowseeCore

final class AudioEngine {
    static let rowCount = 256

    private let tap = SystemAudioTap()
    private var analyzer: SpectrumAnalyzer?
    private var timer: DispatchSourceTimer?

    var onColumn: (([Float]) -> Void)?
    var onStatus: ((String) -> Void)?

    private(set) var isRunning = false

    func start() {
        do {
            try tap.start { [weak self] samples, count in
                self?.analyzer?.ingest(samples, count)
            }
        } catch {
            onStatus?("Capture failed — \(error)")
            return
        }

        tap.onOutputDeviceChange = { [weak self] _ in
            DispatchQueue.main.async { self?.rebuildAnalyzer() }
        }
        rebuildAnalyzer()
        startDrainTimer()
        isRunning = true
    }

    func stop() {
        timer?.cancel()
        timer = nil
        tap.stop()
        isRunning = false
    }

    private func rebuildAnalyzer() {
        guard let info = tap.streamInfo else {
            onStatus?("No output device")
            return
        }
        analyzer = SpectrumAnalyzer(sampleRate: info.sampleRate, rowCount: Self.rowCount)
        onStatus?("\(info.outputDeviceName) · \(Int(info.sampleRate / 1000)) kHz")
    }

    private func startDrainTimer() {
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: .milliseconds(16))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.analyzer?.drainColumns { column in
                self.onColumn?(column)
            }
        }
        source.resume()
        timer = source
    }
}
