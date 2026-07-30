import Foundation
import Synchronization

public final class AudioRingBuffer: @unchecked Sendable {
    private let capacity: Int
    private let mask: Int
    private let storage: UnsafeMutablePointer<Float>
    private let writeCount = Atomic<UInt64>(0)

    public init(capacity: Int = 1 << 17) {
        precondition(capacity.nonzeroBitCount == 1, "capacity must be a power of two")
        self.capacity = capacity
        self.mask = capacity - 1
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    public var framesWritten: UInt64 {
        writeCount.load(ordering: .acquiring)
    }

    public func write(_ samples: UnsafePointer<Float>, _ count: Int) {
        guard count > 0, count <= capacity else { return }
        let start = Int(writeCount.load(ordering: .relaxed))
        let offset = start & mask
        let firstChunk = min(count, capacity - offset)
        (storage + offset).update(from: samples, count: firstChunk)
        if firstChunk < count {
            storage.update(from: samples + firstChunk, count: count - firstChunk)
        }
        writeCount.store(UInt64(start &+ count), ordering: .releasing)
    }

    public func read(
        into destination: UnsafeMutablePointer<Float>,
        count: Int,
        endingAt position: UInt64
    ) -> Bool {
        guard position >= UInt64(count) else { return false }
        let oldest = position - UInt64(count)
        let available = framesWritten
        guard position <= available, available - oldest <= UInt64(capacity) else { return false }

        let start = Int(oldest) & mask
        let firstChunk = min(count, capacity - start)
        destination.update(from: storage + start, count: firstChunk)
        if firstChunk < count {
            (destination + firstChunk).update(from: storage, count: count - firstChunk)
        }
        return true
    }
}
