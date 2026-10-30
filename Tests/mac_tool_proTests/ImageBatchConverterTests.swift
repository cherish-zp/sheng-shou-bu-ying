import XCTest
import CoreGraphics

/// TDD: 批量改图（缩放/编码）与归档命令构建。
final class ImageBatchConverterTests: XCTestCase {

    private func solidImage(w: Int, h: Int) -> CGImage {
        var buf = [UInt8](repeating: 180, count: w * h * 4)
        for i in stride(from: 3, to: buf.count, by: 4) { buf[i] = 255 }
        let provider = CGDataProvider(data: Data(buf) as CFData)!
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    private func tempDir() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("batch-convert-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func test_resize_maxEdge() {
        let resized = ImageBatchConverter.resize(solidImage(w: 800, h: 400), maxEdge: 200)
        XCTAssertEqual(resized.width, 200)
        XCTAssertEqual(resized.height, 100)
    }

    func test_resize_zeroKeepsOriginal() {
        let original = solidImage(w: 800, h: 400)
        let resized = ImageBatchConverter.resize(original, maxEdge: 0)
        XCTAssertEqual(resized.width, 800)
    }

    func test_convertFiles_pngAndFailures() throws {
        let dir = tempDir()
        let input = dir.appendingPathComponent("in.png")
        try NSBitmapImageRep(cgImage: solidImage(w: 100, h: 100)).representation(using: .png, properties: [:])!
            .write(to: input)
        let outputDir = dir.appendingPathComponent("out")

        let (outputs, failures) = ImageBatchConverter.convertFiles(
            at: [input, URL(fileURLWithPath: "/nonexistent/x.png")],
            options: .init(format: .png, maxEdge: 50), outputDirectory: outputDir)

        XCTAssertEqual(outputs.count, 1)
        XCTAssertEqual(failures, ["x.png"])
        let converted = try XCTUnwrap(outputs.first)
        XCTAssertEqual(converted.pathExtension, "png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: converted.path))
    }

    func test_compressCommand_zipAndTar() {
        let zip = ArchiveCommandBuilder.compress(
            archiveName: "pack.zip", paths: ["/a", "/b"], workingDirectory: "/tmp")
        XCTAssertEqual(zip, .init(executablePath: "/usr/bin/zip", arguments: ["-r", "-q", "/tmp/pack.zip", "/a", "/b"]))
        let tgz = ArchiveCommandBuilder.compress(
            archiveName: "pack.tar.gz", paths: ["/a"], workingDirectory: "/tmp")
        XCTAssertEqual(tgz, .init(executablePath: "/usr/bin/tar", arguments: ["-czf", "/tmp/pack.tar.gz", "/a"]))
    }

    func test_extractCommand_byExtension() {
        XCTAssertEqual(
            ArchiveCommandBuilder.extract(archivePath: "/a/x.zip", into: "/out"),
            .init(executablePath: "/usr/bin/unzip", arguments: ["-o", "-q", "/a/x.zip", "-d", "/out"]))
        XCTAssertNil(ArchiveCommandBuilder.extract(archivePath: "/a/x.rar", into: "/out"),
                     "rar 系统不支持，UI 明示")
        XCTAssertTrue(ArchiveCommandBuilder.isSupportedArchive("/a/x.tar.gz"))
        XCTAssertFalse(ArchiveCommandBuilder.isSupportedArchive("/a/x.7z"))
    }

    func test_checksum_deterministic() throws {
        let file = tempDir().appendingPathComponent("f.txt")
        try Data("payload".utf8).write(to: file)
        let first = ArchiveCommandBuilder.checksum(fileURL: file)
        let second = ArchiveCommandBuilder.checksum(fileURL: file)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first?.count, 64)
    }
}
