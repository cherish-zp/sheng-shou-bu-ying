import XCTest
import CoreImage
import CoreGraphics

/// TDD: 二维码检测 - 用 CIQRCodeGenerator 生成已知 QR 图再断言检出（闭环）。
final class QRCodeDetectorTests: XCTestCase {

    private func makeQR(_ content: String, scale: CGFloat = 8) -> CGImage {
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(content.data(using: .isoLatin1) ?? Data(), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        let scaled = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext().createCGImage(scaled, from: scaled.extent)!
    }

    func test_detect_knownContent() {
        let content = "HELLO-MAC-TOOL-2026"
        XCTAssertEqual(QRCodeDetector.detect(in: makeQR(content)), [content])
    }

    func test_detect_plainImageReturnsEmpty() {
        let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        XCTAssertTrue(QRCodeDetector.detect(in: ctx.makeImage()!).isEmpty)
    }

    func test_detect_qrInsideLargerCanvas() {
        // 模拟截图画面：白底画布中嵌一块小二维码
        let canvas = CGContext(data: nil, width: 300, height: 120, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        canvas.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        canvas.fill(CGRect(x: 0, y: 0, width: 300, height: 120))
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue("QR-INSIDE".data(using: .isoLatin1), forKey: "inputMessage")
        let scaled = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 3, y: 3))
        let qr = CIContext().createCGImage(scaled, from: scaled.extent)!
        canvas.draw(qr, in: CGRect(x: 30, y: 20, width: 80, height: 80))
        XCTAssertEqual(QRCodeDetector.detect(in: canvas.makeImage()!), ["QR-INSIDE"])
    }

    func test_summary_truncatesLongContent() {
        XCTAssertEqual(QRCodeDetector.summary(of: "ABC"), "ABC")
        let long = String(repeating: "x", count: 20)
        XCTAssertEqual(QRCodeDetector.summary(of: long), String(repeating: "x", count: 16) + "…")
    }
}
