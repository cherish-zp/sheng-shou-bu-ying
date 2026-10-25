import XCTest
import CoreGraphics

/// TDD: 预捕获位图像素缓冲 - CGImage 一次性绘入 RGBA8 内存后按位图坐标读取；
/// 坐标约定：左上原点（行 0 = CGImage 顶行）。
final class ColorPixelBufferTests: XCTestCase {

    /// 2x2 字节图：行 0 红、绿；行 1 蓝、白。
    private func make2x2Image() -> CGImage? {
        var pixels: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255,
                               0, 0, 255, 255, 255, 255, 255, 255]
        let ctx = CGContext(data: &pixels, width: 2, height: 2, bitsPerComponent: 8,
                            bytesPerRow: 2 * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        return ctx?.makeImage()
    }

    func test_dimensionsMatchImage() throws {
        let buffer = try XCTUnwrap(ColorPixelBuffer(image: try XCTUnwrap(make2x2Image())))
        XCTAssertEqual(buffer.width, 2)
        XCTAssertEqual(buffer.height, 2)
    }

    func test_row0IsImageTopRow() throws {
        let buffer = try XCTUnwrap(ColorPixelBuffer(image: try XCTUnwrap(make2x2Image())))
        let topLeft = try XCTUnwrap(buffer.rgba(atX: 0, y: 0))
        XCTAssertEqual(topLeft.red, 1.0, accuracy: 0.01, "行 0 = CGImage 顶行")
        XCTAssertEqual(topLeft.green, 0.0, accuracy: 0.01)
        let topRight = try XCTUnwrap(buffer.rgba(atX: 1, y: 0))
        XCTAssertEqual(topRight.green, 1.0, accuracy: 0.01)
    }

    func test_row1IsImageBottomRow() throws {
        let buffer = try XCTUnwrap(ColorPixelBuffer(image: try XCTUnwrap(make2x2Image())))
        let bottomLeft = try XCTUnwrap(buffer.rgba(atX: 0, y: 1))
        XCTAssertEqual(bottomLeft.blue, 1.0, accuracy: 0.01)
        let bottomRight = try XCTUnwrap(buffer.rgba(atX: 1, y: 1))
        XCTAssertEqual(bottomRight.red, 1.0, accuracy: 0.01)
        XCTAssertEqual(bottomRight.green, 1.0, accuracy: 0.01)
        XCTAssertEqual(bottomRight.blue, 1.0, accuracy: 0.01)
    }

    func test_outOfBoundsReturnsNil() throws {
        let buffer = try XCTUnwrap(ColorPixelBuffer(image: try XCTUnwrap(make2x2Image())))
        XCTAssertNil(buffer.rgba(atX: 2, y: 0))
        XCTAssertNil(buffer.rgba(atX: -1, y: 0))
        XCTAssertNil(buffer.rgba(atX: 0, y: 2))
        XCTAssertNil(buffer.rgba(atX: 0, y: -1))
    }

    func test_smallestImageStillWorks() throws {
        // 1x1 最小图像：空/0 尺寸 CGImage 无法构造（CG 不接受），此处验证最小可用尺寸路径
        var pixels: [UInt8] = [10, 20, 30, 255]
        let ctx = CGContext(data: &pixels, width: 1, height: 1, bitsPerComponent: 8,
                            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        let image = try XCTUnwrap(ctx?.makeImage())
        let buffer = try XCTUnwrap(ColorPixelBuffer(image: image))
        let color = try XCTUnwrap(buffer.rgba(atX: 0, y: 0))
        XCTAssertEqual(color.red, 10.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(color.blue, 30.0 / 255.0, accuracy: 0.01)
    }
    // MARK: - 小区域裁剪（取色器按需采样，替代整屏 RGBA 常驻）

    /// 4x4 每像素不同的确定性图（i*4+j 编码进 R）。
    private func make4x4Image() -> CGImage? {
        var pixels = [UInt8](repeating: 255, count: 4 * 4 * 4)
        for i in 0..<16 {
            pixels[i * 4] = UInt8(i * 15)
        }
        let ctx = CGContext(data: &pixels, width: 4, height: 4, bitsPerComponent: 8,
                            bytesPerRow: 4 * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        return ctx?.makeImage()
    }

    func test_crop_readsSamePixelsAsFullBuffer() throws {
        let image = try XCTUnwrap(make4x4Image())
        let full = try XCTUnwrap(ColorPixelBuffer(image: image))
        // 裁剪 (1,1)-(3,3)：左上原点、含端点
        let cropped = try XCTUnwrap(ColorPixelBuffer(image: image, cropRect: CGRect(x: 1, y: 1, width: 2, height: 2)))
        XCTAssertEqual(cropped.width, 2)
        XCTAssertEqual(cropped.height, 2)
        for (x, y) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
            let fromFull = try XCTUnwrap(full.rgba(atX: x + 1, y: y + 1))
            let fromCrop = try XCTUnwrap(cropped.rgba(atX: x, y: y))
            XCTAssertEqual(fromFull.red, fromCrop.red, accuracy: 0.01, "裁剪 (\(x),\(y)) 应与整图同址一致")
        }
    }

    func test_regionBounds_coversPointsAndCursor_andClamps() {
        let size = CGSize(width: 3456, height: 2234)
        // 光标贴左上角、网格点最远到 (36, 36)：区域被夹到图像内
        let rect = ColorPixelBuffer.regionBounds(
            points: [CGPoint(x: 36, y: 36)], cursorPixel: CGPoint(x: 0.4, y: 0.4), imageSize: size)
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 37, height: 37), "含端点：0...36 共 37 像素")
        // 中央光标：区域对称覆盖
        let center = ColorPixelBuffer.regionBounds(
            points: [CGPoint(x: 1716, y: 1117)], cursorPixel: CGPoint(x: 1700, y: 1100), imageSize: size)
        XCTAssertEqual(center, CGRect(x: 1700, y: 1100, width: 17, height: 18))
        // 光标贴右下角：夹到边界
        let corner = ColorPixelBuffer.regionBounds(
            points: [CGPoint(x: 3400, y: 2200)], cursorPixel: CGPoint(x: 3455.6, y: 2233.6), imageSize: size)
        XCTAssertEqual(corner?.maxX, 3456, "CGRect.max 为排他边界：最后一个像素下标 3455")
        XCTAssertEqual(corner?.maxY, 2234)
    }

    func test_regionBounds_emptyPoints_returnsCursorCell() {
        let rect = ColorPixelBuffer.regionBounds(points: [], cursorPixel: CGPoint(x: 10, y: 20), imageSize: CGSize(width: 100, height: 100))
        XCTAssertEqual(rect, CGRect(x: 10, y: 20, width: 1, height: 1))
    }
}
