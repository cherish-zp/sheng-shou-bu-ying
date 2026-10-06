import AppKit

/// 截图保存的文件操作抽象，测试用 spy 注入。
public protocol ScreenshotFileStore: AnyObject {
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws
    func contentsOfDirectory(at url: URL) throws -> [String]
    func write(_ data: Data, to url: URL) throws
}

/// 生产实现：直接走 FileManager。
public final class DefaultScreenshotFileStore: ScreenshotFileStore {
    public init() {}

    public func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
    }

    public func contentsOfDirectory(at url: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path)
    }

    public func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}

/// 保存失败原因。调用方据此给出明确提示，禁止静默吞掉。
public enum ScreenshotSaveError: Error, Equatable {
    case directoryCreationFailed
    case listingFailed
    case encodingFailed
    case writeFailed(String)
}

/// 保存结果：成功时 url 非空且 error 为 nil。
public struct ScreenshotSaveOutcome: Equatable {
    public let url: URL?
    public let error: ScreenshotSaveError?

    public var succeeded: Bool { url != nil && error == nil }

    public init(url: URL?, error: ScreenshotSaveError?) {
        self.url = url
        self.error = error
    }
}

/// 统一截图保存出口：建目录 → 去重命名 → PNG 编码 → 写盘，全链路 do/catch。
/// 普通截图与长截图共用，保存失败必须以 error 形式暴露给调用方提示用户。
public final class ScreenshotSaver {
    private let config: ScreenshotConfig
    private let fileStore: ScreenshotFileStore
    private let now: () -> Date
    private let encoder: (NSImage) -> Data?

    public init(
        config: ScreenshotConfig = ScreenshotConfig(),
        fileStore: ScreenshotFileStore = DefaultScreenshotFileStore(),
        now: @escaping () -> Date = Date.init,
        encoder: @escaping (NSImage) -> Data? = ScreenshotSaver.defaultPNGEncoder
    ) {
        self.config = config
        self.fileStore = fileStore
        self.now = now
        self.encoder = encoder
    }

    public func save(_ image: NSImage) -> ScreenshotSaveOutcome {
        let dir = config.saveDirectory
        do {
            try fileStore.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return ScreenshotSaveOutcome(url: nil, error: .directoryCreationFailed)
        }

        let existing: [String]
        do {
            existing = try fileStore.contentsOfDirectory(at: dir)
        } catch {
            return ScreenshotSaveOutcome(url: nil, error: .listingFailed)
        }

        let name = ScreenshotFileNameBuilder.uniqueFileName(
            date: now(), config: config, existingNames: Set(existing)
        )
        let url = dir.appendingPathComponent(name)

        guard let data = encoder(image), !data.isEmpty else {
            return ScreenshotSaveOutcome(url: nil, error: .encodingFailed)
        }

        do {
            try fileStore.write(data, to: url)
        } catch {
            return ScreenshotSaveOutcome(url: nil, error: .writeFailed(String(describing: error)))
        }
        return ScreenshotSaveOutcome(url: url, error: nil)
    }

    /// NSImage → PNG 位图数据；任一环节失败返回 nil。
    public static func defaultPNGEncoder(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
