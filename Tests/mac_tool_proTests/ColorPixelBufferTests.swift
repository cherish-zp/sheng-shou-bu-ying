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
}
