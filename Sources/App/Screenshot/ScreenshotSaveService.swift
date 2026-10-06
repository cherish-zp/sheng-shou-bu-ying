import AppKit

/// 截图统一保存服务：目录创建 -> 查重命名 -> 位图编码 -> 写盘，全链路错误可报告。
///
/// 普通截图（工具条保存按钮）与长截图结果窗（保存按钮）共用同一条路径，
/// 修复旧实现「普通截图保存失败静默丢失」的原始 bug：任何一步失败都会
/// 弹出携带原因的错误提示并写 diag.log；成功则激活 Finder 定位文件 + 「已保存」Toast。
///
/// 编码在后台队列执行（长图 PNG 编码可达数百毫秒，不阻塞主线程）；
/// completion 与 UI 反馈均回调在主线程。
final class ScreenshotSaveService {

    /// 保存失败原因（中文可读描述见 `localizedDescription`）。
    enum SaveError: Error {
        case directoryCreationFailed(underlying: Error)
        case listingFailed(underlying: Error)
        case encodingFailed
        case writeFailed(underlying: Error)

        var localizedDescription: String {
            switch self {
            case .directoryCreationFailed(let e): return "无法创建保存目录：\(e.localizedDescription)"
            case .listingFailed(let e): return "无法读取保存目录，文件名生成失败：\(e.localizedDescription)"
            case .encodingFailed: return "图片编码失败"
            case .writeFailed(let e): return "写入文件失败：\(e.localizedDescription)"
            }
        }
    }

    /// 反馈展示器（toast/alert）：由调用方注入以便与所在会话共用实例。
    private let feedback: ScreenshotFeedbackPresenter
    /// 保存队列（串行）：同一时刻只进行一次写盘，避免同名查重竞态。
    private let queue = DispatchQueue(label: "com.mac-tool-pro.screenshot-save", qos: .userInitiated)

    init(feedback: ScreenshotFeedbackPresenter) {
        self.feedback = feedback
    }

    /// 保存图片到 `config.saveDirectory`（默认 ~/Pictures/Screenshots）。
    /// - Parameters:
    ///   - image: 待保存图片。
    ///   - config: 保存配置（目录/格式/文件名前缀）。
    ///   - completion: 主线程回调；成功/失败的 UI 反馈与 DiagLog 埋点已在本服务内完成，
    ///     调用方通常只需在需要后续动作（如关窗）时使用。
    func save(image: NSImage,
              config: ScreenshotConfig = .init(),
              completion: ((Result<URL, SaveError>) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.performSave(image: image, config: config)
            DispatchQueue.main.async {
                switch result {
                case .success(let url):
                    DiagLog.write("ScreenshotSaveService: saved \(url.path) format=\(config.format.rawValue)")
                    // 保存后在 Finder 中显示文件（保留普通截图模式既有行为）
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    self.feedback.showSaved(url: url)
                case .failure(let error):
                    DiagLog.write("ScreenshotSaveService: save failed - \(error.localizedDescription)")
                    self.feedback.showSaveFailed(message: error.localizedDescription)
                }
                completion?(result)
            }
        }
    }

    // MARK: - 内部：同步保存流程（后台队列执行）

    private func performSave(image: NSImage, config: ScreenshotConfig) -> Result<URL, SaveError> {
        let fm = FileManager.default
        // 1. 目录创建（首保存时目录可能不存在）
        do {
            try fm.createDirectory(at: config.saveDirectory, withIntermediateDirectories: true)
        } catch {
            return .failure(.directoryCreationFailed(underlying: error))
        }
        // 2. 查重命名：读取现有文件名，交由 FileNameBuilder 生成不冲突的完整文件名
        let existing: Set<String>
        do {
            existing = Set(try fm.contentsOfDirectory(atPath: config.saveDirectory.path))
        } catch {
            return .failure(.listingFailed(underlying: error))
        }
        let name = ScreenshotFileNameBuilder.uniqueFileName(
            date: Date(), config: config, existingNames: existing)
        let url = config.saveDirectory.appendingPathComponent(name)
        // 3. 位图编码（PNG/JPG 跟随配置），编码与写盘分别 do/catch
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: config.format.nsBitmapFileType, properties: [:]) else {
            return .failure(.encodingFailed)
        }
        // 4. 写盘
        do {
            try data.write(to: url)
        } catch {
            return .failure(.writeFailed(underlying: error))
        }
        return .success(url)
    }
}

extension ScreenshotFormat {
    /// 映射到 NSBitmapImageRep 的编码类型。
    var nsBitmapFileType: NSBitmapImageRep.FileType {
        switch self {
        case .png: return .png
        case .jpg: return .jpeg
        }
    }
}
