import AudioToolbox
import CoreAudio
import Foundation

public final class SystemAudioTap {
    public struct StreamInfo {
        public let sampleRate: Double
        public let channelCount: Int
        public let outputDeviceName: String
        public let outputDeviceID: AudioDeviceID
    }

    public typealias MonoHandler = (UnsafePointer<Float>, Int) -> Void
    public typealias RawHandler = (UnsafeMutableAudioBufferListPointer) -> Void

    public var onRawBuffers: RawHandler?
    public var onOutputDeviceChange: ((StreamInfo?) -> Void)?
    public private(set) var tapDescriptionSummary = ""
    public private(set) var aggregateInputLayout = ""
    public private(set) var streamInfo: StreamInfo?

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var deviceListener: AudioObjectPropertyListenerBlock?

    private let ioQueue = DispatchQueue(label: "sh.nowsee.tap.io", qos: .userInteractive)
    private let controlQueue = DispatchQueue(label: "sh.nowsee.tap.control")

    private var mixdown: UnsafeMutablePointer<Float>
    private let mixdownCapacity = 65536
    private var handler: MonoHandler?

    public init() {
        mixdown = UnsafeMutablePointer<Float>.allocate(capacity: mixdownCapacity)
        mixdown.initialize(repeating: 0, count: mixdownCapacity)
    }

    deinit {
        removeDefaultDeviceListener()
        teardownChain()
        mixdown.deinitialize(count: mixdownCapacity)
        mixdown.deallocate()
    }

    public func start(onMonoAudio: @escaping MonoHandler) throws {
        handler = onMonoAudio
        try buildChain()
        installDefaultDeviceListener()
    }

    public func stop() {
        removeDefaultDeviceListener()
        handler = nil
        teardownChain()
    }

    private func buildChain() throws {
        let outputID = try defaultOutputDeviceID()
        let outputUID = try deviceUID(outputID)

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "Nowsee System Tap"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr, tapID != AudioObjectID(kAudioObjectUnknown) else {
            throw AudioTapError.osStatus("AudioHardwareCreateProcessTap", status)
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Nowsee Aggregate",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                ]
            ],
        ]

        status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID)
        guard status == noErr, aggregateID != AudioObjectID(kAudioObjectUnknown) else {
            teardownChain()
            throw AudioTapError.osStatus("AudioHardwareCreateAggregateDevice", status)
        }

        tapDescriptionSummary = """
            exclusive=\(description.isExclusive) mixdown=\(description.isMono ? "mono" : "stereo") \
            processes=\(description.processes.count) mute=\(description.muteBehavior.rawValue)
            """
        aggregateInputLayout = inputStreamLayout(aggregateID)

        let format = try tapStreamFormat()
        streamInfo = StreamInfo(
            sampleRate: format.mSampleRate,
            channelCount: Int(format.mChannelsPerFrame),
            outputDeviceName: deviceName(outputID),
            outputDeviceID: outputID
        )

        status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, ioQueue) {
            [weak self] _, inInputData, _, _, _ in
            self?.consume(inInputData)
        }
        guard status == noErr, let ioProcID else {
            teardownChain()
            throw AudioTapError.osStatus("AudioDeviceCreateIOProcIDWithBlock", status)
        }

        status = AudioDeviceStart(aggregateID, ioProcID)
        guard status == noErr else {
            teardownChain()
            throw AudioTapError.osStatus("AudioDeviceStart", status)
        }
    }

    private func teardownChain() {
        if let ioProcID, aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil

        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        streamInfo = nil
    }

    private func installDefaultDeviceListener() {
        var address = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.rebuildForNewOutputDevice()
        }
        deviceListener = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, controlQueue, block
        )
    }

    private func removeDefaultDeviceListener() {
        guard let deviceListener else { return }
        var address = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, controlQueue, deviceListener
        )
        self.deviceListener = nil
    }

    private func rebuildForNewOutputDevice() {
        guard handler != nil else { return }
        teardownChain()
        try? buildChain()
        onOutputDeviceChange?(streamInfo)
    }

    private func tapStreamFormat() throws -> AudioStreamBasicDescription {
        var address = propertyAddress(kAudioTapPropertyFormat)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd)
        guard status == noErr else { throw AudioTapError.osStatus("read tap format", status) }
        return asbd
    }

    private func consume(_ bufferList: UnsafePointer<AudioBufferList>) {
        guard let handler else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: bufferList)
        )
        guard buffers.count > 0, buffers[0].mData != nil else { return }
        onRawBuffers?(buffers)

        if buffers.count > 1 {
            mixDeinterleaved(buffers, handler: handler)
        } else {
            mixInterleaved(buffers[0], handler: handler)
        }
    }

    private func mixInterleaved(_ buffer: AudioBuffer, handler: MonoHandler) {
        let channels = max(Int(buffer.mNumberChannels), 1)
        let totalSamples = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        let frames = min(totalSamples / channels, mixdownCapacity)
        guard frames > 0, let data = buffer.mData else { return }
        let samples = data.assumingMemoryBound(to: Float.self)

        if channels == 1 {
            handler(samples, frames)
            return
        }
        let scale = 1.0 / Float(channels)
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channels {
                sum += samples[frame * channels + channel]
            }
            mixdown[frame] = sum * scale
        }
        handler(mixdown, frames)
    }

    private func mixDeinterleaved(_ buffers: UnsafeMutableAudioBufferListPointer, handler: MonoHandler) {
        let frames = min(
            Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size,
            mixdownCapacity
        )
        guard frames > 0 else { return }
        let scale = 1.0 / Float(buffers.count)
        for frame in 0..<frames {
            mixdown[frame] = 0
        }
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            for frame in 0..<frames {
                mixdown[frame] += samples[frame]
            }
        }
        for frame in 0..<frames {
            mixdown[frame] *= scale
        }
        handler(mixdown, frames)
    }
}
