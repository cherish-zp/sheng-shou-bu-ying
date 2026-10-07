import Foundation

/// 应用品牌单一事实来源（2026-10 由 mac_tool_pro 更名圣手捕影）。
/// 用户可见名称一律引用这里，避免散落硬编码。
public enum AppBrand {
    /// 用户可见名称（Dock/Finder/菜单/右键菜单）。
    public static let displayName = "圣手捕影"
    /// 包内可执行文件名（拉丁，规避中文可执行的工具链兼容风险；
    /// 对外可见的 .app 文件名由 PRODUCT_NAME（圣手捕影）决定）。
    public static let executableName = "ShengShouBuYing"
}

/// Application Support 目录统一入口：新命名 + 旧目录（mac_tool_pro）一次性迁移。
/// App 与 FinderSync 扩展共用：各自解析到自己的支持目录
/// （App → ~/Library/Application Support/圣手捕影；
///  沙盒扩展 → 容器内 .../Application Support/圣手捕影）。
public enum AppSupportDirectory {

    static let legacyName = "mac_tool_pro"
    static let currentName = AppBrand.displayName

    /// 当前支持目录（不自动创建；各使用方按需 createDirectory）。
    public static var url: URL {
        base.appendingPathComponent(currentName, isDirectory: true)
    }

    private static var base: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    /// 一次性迁移：旧目录存在时把数据并入新目录，保留片段、中转站条目、
    /// 贴图设置、Finder 工具开关等全部数据。
    /// - 新目录不存在 → 整体改名搬移；
    /// - 新目录已存在（如诊断日志先于迁移创建过）→ 逐项合并，同名文件保留现有版本；
    /// - 幂等：旧目录不存在时为空操作；失败静默（旧数据原地保留，不丢失）。
    public static func migrateIfNeeded() {
        let legacy = base.appendingPathComponent(legacyName, isDirectory: true)
        let current = base.appendingPathComponent(currentName, isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: legacy.path, isDirectory: &isDir),
              isDir.boolValue else { return }

        var isDirCurrent: ObjCBool = false
        let currentExists = FileManager.default.fileExists(atPath: current.path, isDirectory: &isDirCurrent)
        if !currentExists || !isDirCurrent.boolValue {
            // 新目录不存在（或同名文件挡路）→ 直接整体搬移
            if currentExists { try? FileManager.default.removeItem(at: current) }
            do {
                try FileManager.default.moveItem(at: legacy, to: current)
                NSLog("[AppBrand] 支持目录已迁移: \(legacyName) → \(currentName)")
            } catch {
                NSLog("[AppBrand] 支持目录迁移失败（旧数据原地保留）: \(error.localizedDescription)")
            }
            return
        }

        // 两目录并存 → 逐项合并（同名以新目录为准，不覆盖）
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: legacy.path), !entries.isEmpty else {
            try? fm.removeItem(at: legacy)   // 旧目录已空，直接移除
            return
        }
        var movedCount = 0
        for entry in entries {
            let from = legacy.appendingPathComponent(entry)
            let to = current.appendingPathComponent(entry)
            guard !fm.fileExists(atPath: to.path) else { continue }
            do {
                try fm.moveItem(at: from, to: to)
                movedCount += 1
            } catch {
                NSLog("[AppBrand] 迁移条目失败 \(entry): \(error.localizedDescription)")
            }
        }
        let remaining = (try? fm.contentsOfDirectory(atPath: legacy.path))?.count ?? 1
        if remaining == 0 {
            try? fm.removeItem(at: legacy)
        }
        NSLog("[AppBrand] 支持目录合并迁移完成: \(movedCount) 项（\(legacyName) → \(currentName)）")
    }
}
