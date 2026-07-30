import Accelerate
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
    public typealias StereoHandler = (UnsafePointer<Float>, UnsafePointer<Float>, Int) -> Void
    public typealias RawHandler = (UnsafeMutableAudioBufferListPointer) -> Void

    public var onRawBuffers: RawHandler?
    public var onStereoAudio: StereoHandler?
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

    private let channelCapacity = 65536
    private var mixdown: UnsafeMutablePointer<Float>
    private var leftChannel: UnsafeMutablePointer<Float>
    private var rightChannel: UnsafeMutablePointer<Float>
    private var handler: MonoHandler?

    public init() {
        mixdown = .allocate(capacity: channelCapacity)
        leftChannel = .allocate(capacity: channelCapacity)
        rightChannel = .allocate(capacity: channelCapacity)
        mixdown.initialize(repeating: 0, count: channelCapacity)
        leftChannel.initialize(repeating: 0, count: channelCapacity)
        rightChannel.initialize(repeating: 0, count: channelCapacity)
    }

    deinit {
        removeDefaultDeviceListener()
        teardownChain()
        for buffer in [mixdown, leftChannel, rightChannel] {
            buffer.deinitialize(count: channelCapacity)
            buffer.deallocate()
        }
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

        let frames =
            buffers.count > 1 ? splitDeinterleaved(buffers) : splitInterleaved(buffers[0])
        guard frames > 0 else { return }

        onStereoAudio?(leftChannel, rightChannel, frames)

        var half: Float = 0.5
        vDSP_vadd(leftChannel, 1, rightChannel, 1, mixdown, 1, vDSP_Length(frames))
        vDSP_vsmul(mixdown, 1, &half, mixdown, 1, vDSP_Length(frames))
        handler(mixdown, frames)
    }

    private func splitInterleaved(_ buffer: AudioBuffer) -> Int {
        let channels = max(Int(buffer.mNumberChannels), 1)
        let totalSamples = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        let frames = min(totalSamples / channels, channelCapacity)
        guard frames > 0, let data = buffer.mData else { return 0 }
        let samples = data.assumingMemoryBound(to: Float.self)

        if channels == 1 {
            leftChannel.update(from: samples, count: frames)
            rightChannel.update(from: samples, count: frames)
            return frames
        }
        for frame in 0..<frames {
            leftChannel[frame] = samples[frame * channels]
            rightChannel[frame] = samples[frame * channels + 1]
        }
        return frames
    }

    private func splitDeinterleaved(_ buffers: UnsafeMutableAudioBufferListPointer) -> Int {
        let frames = min(
            Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size,
            channelCapacity
        )
        guard frames > 0, let first = buffers[0].mData else { return 0 }
        let second = buffers.count > 1 ? buffers[1].mData : first
        guard let second else { return 0 }

        leftChannel.update(from: first.assumingMemoryBound(to: Float.self), count: frames)
        rightChannel.update(from: second.assumingMemoryBound(to: Float.self), count: frames)
        return frames
    }
}
