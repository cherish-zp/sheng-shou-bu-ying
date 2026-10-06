import XCTest
import CoreGraphics

/// TDD: 新鲜帧捕获 + 裁剪 - y 翻转正确、Retina 缩放、捕获失败返回 nil、displayID 透传。
final class FreshFrameProviderTests: XCTestCase {

    /// 构造已知内容的整屏帧：上半蓝色、下半红色（CGImage 坐标左上原点）。
    private func makeFrame(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
        return ctx.makeImage()!
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (Int, Int, Int) {
        let w = image.width
        var buf = [UInt8](repeating: 0, count: w * image.height * 4)
        let ctx = CGContext(data: &buf, width: w, height: image.height, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: image.height))
        let off = (y * w + x) * 4
        return (Int(buf[off]), Int(buf[off + 1]), Int(buf[off + 2]))
    }

    func test_cropped_bottomSelectionYieldsBottomContent() {
        // 100x100 帧（scale=1）：视图坐标 (0,0,50,50) = 左下象限 → 图像下半 → 红色
        let provider = FreshFrameProvider(capture: { _ in self.makeFrame(width: 100, height: 100) })
        let cropped = provider.cropped(
            selection: CGRect(x: 0, y: 0, width: 50, height: 50),
            fullFrame: makeFrame(width: 100, height: 100),
            screenPointSize: CGSize(width: 100, height: 100))
        XCTAssertNotNil(cropped)
        XCTAssertEqual(cropped?.width, 50)
        XCTAssertEqual(cropped?.height, 50)
        let rgb = pixel(cropped!, x: 25, y: 25)
        XCTAssertGreaterThan(rgb.0, 200)
        XCTAssertLessThan(rgb.1, 50)
    }

    func test_cropped_topSelectionYieldsTopContent() {
        let provider = FreshFrameProvider(capture: { _ in nil })
        let cropped = provider.cropped(
            selection: CGRect(x: 0, y: 50, width: 50, height: 50),
            fullFrame: makeFrame(width: 100, height: 100),
            screenPointSize: CGSize(width: 100, height: 100))
        let rgb = pixel(cropped!, x: 25, y: 25)
        XCTAssertGreaterThan(rgb.2, 200, "视图上半选区应取到图像上半（蓝色）")
    }

    func test_cropped_retinaScalesByFactor() {
        let provider = FreshFrameProvider(capture: { _ in nil })
        let cropped = provider.cropped(
            selection: CGRect(x: 0, y: 0, width: 50, height: 50),
            fullFrame: makeFrame(width: 200, height: 200),
            screenPointSize: CGSize(width: 100, height: 100))
        XCTAssertEqual(cropped?.width, 100, "2x 屏上 50pt 选区裁出 100px")
        XCTAssertEqual(cropped?.height, 100)
    }

    func test_captureCropped_passesDisplayIDAndCombinesCrop() {
        let frame = makeFrame(width: 100, height: 100)
        var requestedDisplay: CGDirectDisplayID?
        let provider = FreshFrameProvider(capture: { displayID in
            requestedDisplay = displayID
            return frame
        })
        let combined = provider.captureCropped(
            selection: CGRect(x: 0, y: 0, width: 50, height: 50),
            displayID: 77, screenPointSize: CGSize(width: 100, height: 100))
        XCTAssertNotNil(combined)
        XCTAssertEqual(requestedDisplay, 77)
    }

    func test_captureFailureReturnsNil() {
        let provider = FreshFrameProvider(capture: { _ in nil })
        XCTAssertNil(provider.captureCropped(
            selection: CGRect(x: 0, y: 0, width: 50, height: 50),
            displayID: 1, screenPointSize: CGSize(width: 100, height: 100)))
    }
}
