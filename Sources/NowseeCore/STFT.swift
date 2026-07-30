import Accelerate
import Foundation

public final class STFT {
    public let windowSize: Int
    public let binCount: Int

    private let fft: vDSP.FFT<DSPSplitComplex>
    private let window: [Float]
    private let scale: Float
    private var windowed: [Float]
    private var real: [Float]
    private var imaginary: [Float]

    public init(windowSize: Int = 2048) {
        precondition(windowSize.nonzeroBitCount == 1, "window size must be a power of two")
        self.windowSize = windowSize
        self.binCount = windowSize / 2

        let log2n = vDSP_Length(log2(Double(windowSize)).rounded())
        guard let fft = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self) else {
            fatalError("could not create FFT setup for window size \(windowSize)")
        }
        self.fft = fft

        window = vDSP.window(
            ofType: Float.self,
            usingSequence: .hanningDenormalized,
            count: windowSize,
            isHalfWindow: false
        )
        scale = 1 / (Float(windowSize) * 0.5)
        windowed = [Float](repeating: 0, count: windowSize)
        real = [Float](repeating: 0, count: binCount)
        imaginary = [Float](repeating: 0, count: binCount)
    }

    public func magnitudesDB(of frame: UnsafePointer<Float>, into output: inout [Float]) {
        precondition(output.count == binCount)

        let input = UnsafeBufferPointer(start: frame, count: windowSize)
        vDSP.multiply(input, window, result: &windowed)

        real.withUnsafeMutableBufferPointer { realBuffer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                var split = DSPSplitComplex(
                    realp: realBuffer.baseAddress!,
                    imagp: imaginaryBuffer.baseAddress!
                )
                windowed.withUnsafeBufferPointer { windowedBuffer in
                    windowedBuffer.baseAddress!.withMemoryRebound(
                        to: DSPComplex.self, capacity: binCount
                    ) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(binCount))
                    }
                }
                fft.forward(input: split, output: &split)
                vDSP_zvabs(&split, 1, &output, 1, vDSP_Length(binCount))
            }
        }

        vDSP.multiply(scale, output, result: &output)
        vDSP.add(1e-9, output, result: &output)

        var reference: Float = 1
        vDSP_vdbcon(output, 1, &reference, &output, 1, vDSP_Length(binCount), 1)
    }
}
