import AudioToolbox
import CoreAudio
import Darwin
import Dispatch
import Foundation
import NowseeCore

final class LevelMeter {
    private var sumSquares: Double = 0
    private var peak: Float = 0
    private var frames: Int = 0
    private(set) var totalFrames: Int = 0
    private(set) var callbackCount: Int = 0
    private(set) var peakEver: Float = 0

    func accumulate(_ samples: UnsafePointer<Float>, _ count: Int) {
        var localSum: Double = 0
        var localPeak: Float = 0
        for index in 0..<count {
            let sample = samples[index]
            localSum += Double(sample) * Double(sample)
            localPeak = max(localPeak, abs(sample))
        }
        sumSquares += localSum
        peak = max(peak, localPeak)
        peakEver = max(peakEver, localPeak)
        frames += count
        totalFrames += count
        callbackCount += 1
    }

    func drain() -> (rmsDB: Float, peakDB: Float) {
        defer {
            sumSquares = 0
            peak = 0
            frames = 0
        }
        guard frames > 0 else { return (-120, -120) }
        let rms = Float((sumSquares / Double(frames)).squareRoot())
        return (decibels(rms), decibels(peak))
    }

    private func decibels(_ amplitude: Float) -> Float {
        amplitude <= 0.0000001 ? -120 : 20 * log10(amplitude)
    }
}

func bar(_ db: Float, width: Int = 44) -> String {
    let normalized = max(0, min(1, (db + 80) / 80))
    let filled = Int(normalized * Float(width))
    return String(repeating: "█", count: filled) + String(repeating: "·", count: width - filled)
}

final class BufferProbe {
    private(set) var layout: String?
    private(set) var peaks: [Float] = []

    func inspect(_ buffers: UnsafeMutableAudioBufferListPointer) {
        if layout == nil {
            layout = buffers.enumerated()
                .map { "buf\($0.offset)=\($0.element.mNumberChannels)ch/\($0.element.mDataByteSize)B" }
                .joined(separator: " ")
            peaks = Array(repeating: 0, count: buffers.count)
        }
        for (index, buffer) in buffers.enumerated() where index < peaks.count {
            guard let data = buffer.mData else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            var localPeak: Float = 0
            for sample in 0..<count {
                localPeak = max(localPeak, abs(samples[sample]))
            }
            peaks[index] = max(peaks[index], localPeak)
        }
    }
}

let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/nowsee-probe.log")
FileManager.default.createFile(atPath: logURL.path, contents: nil)

func report(_ text: String) {
    print(text)
    guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
    handle.seekToEndOfFile()
    handle.write((text + "\n").data(using: .utf8)!)
    try? handle.close()
}

let asciiRamp = Array(" .:-=+*#%@")
let asciiRows = 96
let wantsSpectrogram = CommandLine.arguments.contains("--spectrogram")

func asciiLine(_ column: [Float]) -> String {
    String(
        column.map { value in
            asciiRamp[max(0, min(asciiRamp.count - 1, Int(value * Float(asciiRamp.count))))]
        })
}

var analyzer: SpectrumAnalyzer?
var columns: [[Float]] = []
let ring = AudioRingBuffer()

let meter = LevelMeter()
let bufferProbe = BufferProbe()
let tap = SystemAudioTap()
tap.onRawBuffers = { bufferProbe.inspect($0) }

print("nowsee-probe — Core Audio process tap check\n")

do {
    try tap.start { samples, count in
        meter.accumulate(samples, count)
        ring.write(samples, count)
    }
} catch {
    report("FAILED: \(error)")
    exit(1)
}

if let info = tap.streamInfo {
    report("output device : \(info.outputDeviceName)")
    report("tap format    : \(Int(info.sampleRate)) Hz, \(info.channelCount) ch")
    if let volume = outputVolumeScalar(info.outputDeviceID) {
        report("system volume : \(Int(volume * 100))%")
    }
}
report("tap descr     : \(tap.tapDescriptionSummary)")
report("aggregate in  : \(tap.aggregateInputLayout)")

if wantsSpectrogram, let info = tap.streamInfo {
    analyzer = SpectrumAnalyzer(ring: ring, sampleRate: info.sampleRate, rowCount: asciiRows)
}
report("\nPlay something. Ctrl-C to stop.\n")

func finish() -> Never {
    DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
        FileHandle.standardError.write("teardown exceeded 3s — forcing exit\n".data(using: .utf8)!)
        _exit(2)
    }
    tap.stop()
    report("\nreceived \(meter.totalFrames) frames in \(meter.callbackCount) callbacks")
    report("callback layout: \(bufferProbe.layout ?? "never fired")")
    let peakReport = bufferProbe.peaks.enumerated()
        .map { String(format: "buf%d=%.4f", $0.offset, $0.element) }
        .joined(separator: " ")
    report("per-buffer peak: \(peakReport.isEmpty ? "none" : peakReport)")
    if meter.totalFrames == 0 {
        report("VERDICT: no audio reached the callback — tap created but delivered nothing.")
    } else if meter.peakEver <= 0.0000001 {
        report("VERDICT: callbacks fired but every sample was silent — permission almost certainly denied.")
    } else {
        report(String(format: "VERDICT: CAPTURE WORKS — loudest sample %.1f dBFS", 20 * log10(meter.peakEver)))
    }

    if let analyzer, !columns.isEmpty {
        let stride = max(1, columns.count / 60)
        let shown = Swift.stride(from: 0, to: columns.count, by: stride).map { columns[$0] }
        let range = analyzer.contrastRange
        report("")
        report(String(format: "spectrogram — %d columns, auto-contrast %.0f..%.0f dB",
                      columns.count, range.low, range.high))
        report("30 Hz" + String(repeating: " ", count: asciiRows - 12) + "16 kHz")
        report(String(repeating: "-", count: asciiRows))
        for column in shown {
            report(asciiLine(column))
        }
    }
    exit(0)
}

let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
interrupt.setEventHandler { finish() }
interrupt.resume()
signal(SIGINT, SIG_IGN)

let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
terminate.setEventHandler { finish() }
terminate.resume()
signal(SIGTERM, SIG_IGN)

let duration = CommandLine.arguments.contains("--forever")
    ? nil
    : CommandLine.arguments.compactMap(Double.init).first ?? 10
if let duration {
    DispatchQueue.main.asyncAfter(deadline: .now() + duration) { finish() }
}

let deviceID = tap.streamInfo?.outputDeviceID
let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(deadline: .now(), repeating: .milliseconds(50))
timer.setEventHandler {
    analyzer?.drainColumns { column in
        if columns.count < 8192 { columns.append(column) }
    }
    guard isatty(STDOUT_FILENO) == 1 else { _ = meter.drain(); return }
    let (rms, peak) = meter.drain()
    let volume = deviceID.flatMap { outputVolumeScalar($0) }
    let volumeText = volume.map { " vol \(String(format: "%3d", Int($0 * 100)))%" } ?? ""
    let line = String(
        format: "\r%@ %6.1f dB rms  %6.1f dB peak%@", bar(rms), rms, peak, volumeText
    )
    FileHandle.standardOutput.write(line.data(using: .utf8)!)
}
timer.resume()

dispatchMain()
