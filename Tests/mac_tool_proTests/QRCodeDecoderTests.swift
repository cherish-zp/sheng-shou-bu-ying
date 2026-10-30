import XCTest
import CoreGraphics
import CoreImage

/// TDD: 二维码识别 —— 用 CIQRCodeGenerator 生成测试码，Vision 解码回原文。
final class QRCodeDecoderTests: XCTestCase {

    /// CIQRCodeGenerator 生成二维码 CGImage。
    private func makeQR(_ text: String) throws -> CGImage {
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        let output = try XCTUnwrap(filter.outputImage)
        // 放大到可识别尺寸
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        let cg = try XCTUnwrap(context.createCGImage(scaled, from: scaled.extent))
        return cg
    }

    func test_decodeGeneratedQR() throws {
        let payload = "https://shengshoubuying.example/feature"
        let decoded = try QRCodeDecoder.decode(cgImage: try makeQR(payload))
        XCTAssertEqual(decoded, [payload])
    }

    func test_decodeChinesePayload() throws {
        let payload = "圣手捕影二维码内容"
        let decoded = try QRCodeDecoder.decode(cgImage: try makeQR(payload))
        XCTAssertEqual(decoded, [payload])
    }

    func test_noQRInPlainImage_returnsEmpty() throws {
        // 20x20 灰色纯色图
        var pixels = [UInt8](repeating: 128, count: 20 * 20 * 4)
        for i in stride(from: 3, to: pixels.count, by: 4) { pixels[i] = 255 }
        let ctx = CGContext(data: &pixels, width: 20, height: 20, bitsPerComponent: 8,
                            bytesPerRow: 80, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = ctx.makeImage()!
        let decoded = try QRCodeDecoder.decode(cgImage: image)
        XCTAssertTrue(decoded.isEmpty)
    }
}
