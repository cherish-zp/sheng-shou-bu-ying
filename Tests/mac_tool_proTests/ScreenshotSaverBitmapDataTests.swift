import XCTest
import AppKit
import CoreGraphics

/// TDD: 位图编码直编（CGImageDestination）——免 TIFF 中间拷贝；
/// 编码结果必须可解码且像素尺寸保持（PNG 无损、JPG 最高质量）。
final class ScreenshotSaverBitmapDataTests: XCTestCase {

    /// 纯色 CGImage → NSImage（representations 保持精确像素尺寸）。
    private func solidImage(w: Int, h: Int) -> NSImage {
        var buf = [UInt8](repeating: 200, count: w * h * 4)
        for i in stride(from: 3, to: buf.count, by: 4) { buf[i] = 255 }
        let provider = CGDataProvider(data: Data(buf) as CFData)!
        let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                         bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                         provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return NSImage(cgImage: cg, size: NSSize(width: w, height: h))
    }

    func test_pngRoundTrip_preservesPixelSize() throws {
        let image = solidImage(w: 640, h: 400)
        let data = try XCTUnwrap(ScreenshotSaver.bitmapData(image, format: .png))
        let back = try XCTUnwrap(NSImage(data: data))
        XCTAssertEqual(back.representations.first?.pixelsWide, 640)
        XCTAssertEqual(back.representations.first?.pixelsHigh, 400)
    }

    func test_jpegRoundTrip_preservesPixelSize() throws {
        let image = solidImage(w: 320, h: 200)
        let data = try XCTUnwrap(ScreenshotSaver.bitmapData(image, format: .jpg))
        let back = try XCTUnwrap(NSImage(data: data))
        XCTAssertEqual(back.representations.first?.pixelsWide, 320)
        XCTAssertEqual(back.representations.first?.pixelsHigh, 200)
    }

    func test_defaultPNGEncoder_stillProducesData() {
        XCTAssertNotNil(ScreenshotSaver.defaultPNGEncoder(solidImage(w: 16, h: 16)))
    }
}
