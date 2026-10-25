import CoreGraphics
import Foundation

/// 位图像素缓冲（纯 CG 逻辑）：把 CGImage（整幅或小区域）绘入 RGBA8 内存读取。
/// 坐标约定：位图像素、左上原点（与 ColorMagnifierGridMath 一致）。
/// 取色器用法：持有 CGImage，每次鼠标移动只把采样窗大小的区域绘入小缓冲——
/// 免去整屏 RGBA 常驻（5K 屏 ~59MB/屏），每帧代价是一次 ~40×40px 的小 blit。
public final class ColorPixelBuffer {

    public let width: Int
    public let height: Int
    private let data: UnsafeMutableRawPointer

    /// 整幅绘入（小图/测试用；取色器生产路径请用 cropRect 小区域）。
    public convenience init?(image: CGImage) {
        self.init(image: image, cropRect: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }

    /// 只把 cropRect（图像像素坐标、左上原点、越界自动夹取）绘入小缓冲。
    /// 绘制失败（区域退化/图像为空/上下文创建失败）返回 nil。
    public init?(image: CGImage, cropRect: CGRect) {
        guard image.width > 0, image.height > 0 else { return nil }
        let x0 = max(0, min(image.width, Int(cropRect.minX.rounded(.down))))
        let y0 = max(0, min(image.height, Int(cropRect.minY.rounded(.down))))
        let x1 = max(x0, min(image.width, Int(cropRect.maxX.rounded(.up))))
        let y1 = max(y0, min(image.height, Int(cropRect.maxY.rounded(.up))))
        let w = x1 - x0
        let h = y1 - y0
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
        // 左上原点区域 → CG 左下原点平移：把整图按偏移画入，裁剪区落在上下文 (0,0)
        ctx.draw(image, in: CGRect(
            x: -CGFloat(x0),
            y: -CGFloat(image.height - (y0 + h)),
            width: CGFloat(image.width), height: CGFloat(image.height)))
    }

    /// 采样覆盖窗（左上原点、含端点、夹取在图像内）：全部网格点 + 光标点所需的最小像素窗。
    /// points 为空时返回光标所在单元格（1×1）；图像退化返回 nil。
    public static func regionBounds(points: [CGPoint], cursorPixel: CGPoint, imageSize: CGSize) -> CGRect? {
        guard imageSize.width >= 1, imageSize.height >= 1 else { return nil }
        var minX = cursorPixel.x, maxX = cursorPixel.x
        var minY = cursorPixel.y, maxY = cursorPixel.y
        if points.isEmpty {
            let x0 = max(0, min(Int(imageSize.width) - 1, Int(cursorPixel.x.rounded(.down))))
            let y0 = max(0, min(Int(imageSize.height) - 1, Int(cursorPixel.y.rounded(.down))))
            return CGRect(x: x0, y: y0, width: 1, height: 1)
        }
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let x0 = max(0, Int(minX.rounded(.down)))
        let y0 = max(0, Int(minY.rounded(.down)))
        let x1 = min(Int(imageSize.width) - 1, Int(maxX.rounded(.up)))
        let y1 = min(Int(imageSize.height) - 1, Int(maxY.rounded(.up)))
        guard x1 >= x0, y1 >= y0 else { return nil }
        return CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)
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
