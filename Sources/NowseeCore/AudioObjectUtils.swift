import CoreAudio
import Foundation

public enum AudioTapError: Error, CustomStringConvertible {
    case osStatus(String, OSStatus)
    case noDefaultOutputDevice

    public var description: String {
        switch self {
        case let .osStatus(operation, status):
            return "\(operation) failed — OSStatus \(status) '\(status.fourCharCode)'"
        case .noDefaultOutputDevice:
            return "no default output device"
        }
    }
}

extension OSStatus {
    var fourCharCode: String {
        let value = UInt32(bitPattern: self)
        let bytes = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return "----" }
        return String(bytes: bytes, encoding: .ascii) ?? "----"
    }
}

func propertyAddress(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )
}

public func defaultOutputDeviceID() throws -> AudioDeviceID {
    var address = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
    var deviceID = AudioDeviceID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
    )
    guard status == noErr else { throw AudioTapError.osStatus("read default output device", status) }
    guard deviceID != AudioDeviceID(kAudioObjectUnknown) else { throw AudioTapError.noDefaultOutputDevice }
    return deviceID
}

public func deviceUID(_ deviceID: AudioDeviceID) throws -> String {
    var address = propertyAddress(kAudioDevicePropertyDeviceUID)
    var uid: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = withUnsafeMutablePointer(to: &uid) {
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, $0)
    }
    guard status == noErr else { throw AudioTapError.osStatus("read device UID", status) }
    return uid as String
}

public func deviceName(_ deviceID: AudioDeviceID) -> String {
    var address = propertyAddress(kAudioObjectPropertyName)
    var name: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = withUnsafeMutablePointer(to: &name) {
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, $0)
    }
    return status == noErr ? name as String : "unknown"
}

public func inputStreamLayout(_ deviceID: AudioObjectID) -> String {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else {
        return "unavailable"
    }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, raw) == noErr else {
        return "unavailable"
    }
    let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
    guard buffers.count > 0 else { return "no input streams" }
    return buffers.enumerated()
        .map { "buf\($0.offset)=\($0.element.mNumberChannels)ch" }
        .joined(separator: " ")
}

public func outputVolumeScalar(_ deviceID: AudioDeviceID) -> Float? {
    for element in [kAudioObjectPropertyElementMain, 1, 2] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &address) else { continue }
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr {
            return volume
        }
    }
    return nil
}
