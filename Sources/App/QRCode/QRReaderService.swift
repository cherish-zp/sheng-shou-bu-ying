import AppKit
import Vision
import CoreGraphics

/// 二维码识别运行时：剪贴板图片 → Vision 条码识别 → 载荷回写剪贴板 + 反馈。
final class QRReaderService {

    enum ReaderError: LocalizedError {
        case noImageInPasteboard
        case noCodeFound

        var errorDescription: String? {
            switch self {
            case .noImageInPasteboard: return "剪贴板中没有图片"
            case .noCodeFound: return "未识别到二维码"
            }
        }
    }

    /// 解码注入点（测试用）。默认 QRCodeDecoder。
    var decode: (CGImage) throws -> [String] = { try QRCodeDecoder.decode(cgImage: $0) }

    /// 从剪贴板图片识别二维码，载荷回写剪贴板。完成回调主线程。
    func readFromPasteboard(completion: @escaping (Result<String, Error>) -> Void) {
        let pasteboard = NSPasteboard.general
        guard let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation,
              let source = NSBitmapImageRep(data: tiff),
              let cgImage = source.cgImage else {
                DispatchQueue.main.async { completion(.failure(ReaderError.noImageInPasteboard)) }
                return
        }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                let payloads = try decode(cgImage)
                DispatchQueue.main.async {
                    if let first = payloads.first {
                        pasteboard.clearContents()
                        pasteboard.setString(first, forType: .string)
                        completion(.success(first))
                    } else {
                        completion(.failure(ReaderError.noCodeFound))
                    }
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }
}
