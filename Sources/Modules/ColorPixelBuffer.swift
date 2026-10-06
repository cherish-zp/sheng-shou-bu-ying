import CoreGraphics
import Foundation

/// 预捕获位图的像素缓冲（纯 CG 逻辑）：把 CGImage 一次性绘入 RGBA8 内存，
/// 放大镜每帧与取色直接读内存，零重复采集开销。
/// 坐标约定：位图像素、左上原点（与 ColorMagnifierGridMath 一致）。
public final class ColorPixelBuffer {

    public let width: Int
    public let height: Int
    private let data: UnsafeMutableRawPointer

    /// 绘制失败（图像为空 / 上下文创建失败）返回 nil。
    public init?(image: CGImage) {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return nil }
        width = w
        height = h
        let bytes = w * h * 4
        byteCount = bytes
        data = UnsafeMutableRawPointer.allocate(
            byteCount: bytes, alignment: MemoryLayout<UInt32>.alignment
        )
        data.initializeMemory(as: UInt8.self, repeating: 0, count: bytes)
        guard let ctx = CGContext(
            data: data, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            data.deallocate()
            return nil
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }

    private let byteCount: Int

    deinit {
        data.deallocate()
    }

    /// 读取像素 RGBA（0-1）；坐标为位图像素、左上原点；越界返回 nil。
    public func rgba(atX x: Int, y: Int) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let offset = (y * width + x) * 4
        func normalized(_ value: UInt8) -> Double { Double(value) / 255.0 }
        return (normalized(pixels[offset]), normalized(pixels[offset + 1]),
                normalized(pixels[offset + 2]), normalized(pixels[offset + 3]))
    }
}
