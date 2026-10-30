import Foundation
import CoreGraphics
import CryptoKit
import ImageIO

/// 批量改图纯逻辑（TDD）：缩放 + PNG/JPG 编码。
public enum ImageBatchConverter {

    public enum OutputFormat: String, CaseIterable {
        case png, jpeg

        var uti: String { self == .png ? "public.png" : "public.jpeg" }
    }

    public struct Options: Equatable {
        public var format: OutputFormat
        /// 最长边像素上限；0 = 保持原尺寸。
        public var maxEdge: Int
        public init(format: OutputFormat = .png, maxEdge: Int = 0) {
            self.format = format
            self.maxEdge = maxEdge
        }
    }

    /// 缩放 CGImage（等比，最长边到 maxEdge；0 表示原样）。
    public static func resize(_ image: CGImage, maxEdge: Int) -> CGImage {
        guard maxEdge > 0 else { return image }
        let longest = max(image.width, image.height)
        guard longest > maxEdge else { return image }
        let scale = CGFloat(maxEdge) / CGFloat(longest)
        let w = max(1, Int(CGFloat(image.width) * scale))
        let h = max(1, Int(CGFloat(image.height) * scale))
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    /// 编码（PNG 无损 / JPEG 质量 0.9）；失败返回 nil。
    public static func encode(_ image: CGImage, format: OutputFormat) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, format.uti as CFString, 1, nil) else { return nil }
        var properties: [CFString: Any] = [:]
        if format == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.9
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// 文件批量转换：返回 (输出文件 URL 列表, 失败输入名列表)。
    public static func convertFiles(at urls: [URL], options: Options,
                                    outputDirectory: URL,
                                    fileManager: FileManager = .default) -> (outputs: [URL], failures: [String]) {
        var outputs: [URL] = []
        var failures: [String] = []
        try? fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for url in urls {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                failures.append(url.lastPathComponent)
                continue
            }
            let resizedImage = resize(image, maxEdge: options.maxEdge)
            guard let data = encode(resizedImage, format: options.format) else {
                failures.append(url.lastPathComponent)
                continue
            }
            let base = url.deletingPathExtension().lastPathComponent
            let outputURL = outputDirectory
                .appendingPathComponent("\(base)-converted.\(options.format == .png ? "png" : "jpg")")
            do {
                try data.write(to: outputURL, options: .atomic)
                outputs.append(outputURL)
            } catch {
                failures.append(url.lastPathComponent)
            }
        }
        return (outputs, failures)
    }
}

/// 归档压缩/解压纯逻辑（TDD）：按扩展名给出系统工具与参数（zip/tar 系）。
public enum ArchiveCommandBuilder {

    public struct Command: Equatable {
        public let executablePath: String
        public let arguments: [String]

        public init(executablePath: String, arguments: [String]) {
            self.executablePath = executablePath
            self.arguments = arguments
        }
    }

    /// 压缩：把 paths 压成 directory 下的 archiveName（按后缀选 zip/tar.gz/tar.bz2）。
    public static func compress(archiveName: String, paths: [String], workingDirectory: String) -> Command {
        let archive = workingDirectory + "/" + archiveName
        if archiveName.hasSuffix(".zip") {
            return .init(executablePath: "/usr/bin/zip", arguments: ["-r", "-q", archive] + paths)
        }
        if archiveName.hasSuffix(".tar.bz2") {
            return .init(executablePath: "/usr/bin/tar", arguments: ["-cjf", archive] + paths)
        }
        return .init(executablePath: "/usr/bin/tar", arguments: ["-czf", archive] + paths)
    }

    /// 解压：按压缩包扩展名给出解压命令（目标目录）。
    public static func extract(archivePath: String, into directory: String) -> Command? {
        let lower = archivePath.lowercased()
        if lower.hasSuffix(".zip") {
            return .init(executablePath: "/usr/bin/unzip", arguments: ["-o", "-q", archivePath, "-d", directory])
        }
        if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz") {
            return .init(executablePath: "/usr/bin/tar", arguments: ["-xzf", archivePath, "-C", directory])
        }
        if lower.hasSuffix(".tar.bz2") || lower.hasSuffix(".tbz") {
            return .init(executablePath: "/usr/bin/tar", arguments: ["-xjf", archivePath, "-C", directory])
        }
        if lower.hasSuffix(".tar") {
            return .init(executablePath: "/usr/bin/tar", arguments: ["-xf", archivePath, "-C", directory])
        }
        return nil   // rar/7z：系统无支持，UI 明示
    }

    /// 压缩包是否受支持（UI 标注用）。
    public static func isSupportedArchive(_ path: String) -> Bool {
        extract(archivePath: path, into: "/tmp") != nil
    }

    /// 文件校验和（SHA256，文本工具同源）。
    public static func checksum(fileURL: URL) -> String? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return CryptoKit.SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
