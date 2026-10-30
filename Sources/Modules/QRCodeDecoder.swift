import Foundation
import Vision
import CoreGraphics

/// 二维码识别（纯 Vision 逻辑，TDD）：从图片中提取二维码/条码载荷。
/// 运行时入口见 Sources/App/QRCode/QRReaderService.swift（剪贴板图片 → 本解码器）。
public enum QRCodeDecoder {

    /// 识别图中全部码的载荷文本；无码返回空数组。参数注入便于测试。
    public static func decode(cgImage: CGImage) throws -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [VNBarcodeSymbology.qr, VNBarcodeSymbology.ean13, VNBarcodeSymbology.code128]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        return request.results?
            .compactMap { $0.payloadStringValue }
            ?? []
    }
}
