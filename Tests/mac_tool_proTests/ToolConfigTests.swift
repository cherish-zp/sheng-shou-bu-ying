import XCTest

/// TDD: ToolConfig 双进程共享解析 —— 扩展（沙盒）读自身容器，App（非沙盒）直写扩展容器。
/// 旧版两进程各写各的目录，设置面板的 Finder 工具开关对扩展完全失效（split-brain）。
final class ToolConfigTests: XCTestCase {

    private let home = URL(fileURLWithPath: "/tmp/toolconfig-home")
    private let bundleID = "com.zp.shengshoubuying.FinderSyncExt"

    // MARK: - 目录解析

    func test_resolve_appProcess_writesExtensionContainer() {
        let url = ToolConfig.resolveDirectoryURL(isExtensionProcess: false, homeDirectory: home)
        XCTAssertEqual(
            url.path,
            home.appendingPathComponent("Library/Containers/\(bundleID)/Data/Library/Application Support/圣手捕影").path
        )
    }

    func test_resolve_extensionProcess_usesOwnAppSupport() {
        let url = ToolConfig.resolveDirectoryURL(isExtensionProcess: true, homeDirectory: home)
        XCTAssertEqual(
            url.path,
            home.appendingPathComponent("Library/Application Support/圣手捕影").path
        )
    }

    // MARK: - 旧配置一次性迁移（App 侧旧文件并入扩展容器）

    private func tempDir(_ name: String) -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("toolconfig-tests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func test_migrate_movesLegacyWhenDestinationMissing() throws {
        let dir = tempDir("move")
        let legacy = dir.appendingPathComponent("legacy/config.json")
        let destination = dir.appendingPathComponent("container/config.json")
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"enabled\":{}}".utf8).write(to: legacy)

        let moved = ToolConfig.migrateLegacyConfigIfNeeded(
            legacyFileURL: legacy, destinationFileURL: destination)

        XCTAssertTrue(moved)
        XCTAssertEqual(try Data(contentsOf: destination), Data("{\"enabled\":{}}".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }

    func test_migrate_keepsExistingDestination() throws {
        let dir = tempDir("keep")
        let legacy = dir.appendingPathComponent("legacy/config.json")
        let destination = dir.appendingPathComponent("container/config.json")
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("legacy".utf8).write(to: legacy)
        try Data("container".utf8).write(to: destination)

        let moved = ToolConfig.migrateLegacyConfigIfNeeded(
            legacyFileURL: legacy, destinationFileURL: destination)

        XCTAssertFalse(moved, "容器已有配置（扩展可能已写入）时应保留现有版本")
        XCTAssertEqual(try Data(contentsOf: destination), Data("container".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path), "旧文件保留不删")
    }

    func test_migrate_noopWhenLegacyMissing() throws {
        let dir = tempDir("noop")
        let moved = ToolConfig.migrateLegacyConfigIfNeeded(
            legacyFileURL: dir.appendingPathComponent("missing.json"),
            destinationFileURL: dir.appendingPathComponent("container/config.json"))
        XCTAssertFalse(moved)
    }
}
