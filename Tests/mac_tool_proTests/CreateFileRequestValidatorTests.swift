import XCTest

/// TDD: IPC「新建文件」请求的输入校验 —— 队列目录对同用户任意进程可写，
/// 恶意/畸形请求不得让非沙盒 App 在敏感位置建文件或建出路径穿越文件。
final class CreateFileRequestValidatorTests: XCTestCase {

    func test_validRequest_passes() {
        XCTAssertTrue(CreateFileRequestValidator.isAllowed(
            directoryPath: "/Users/zhangpeng/Desktop", baseName: "notes.txt"))
        XCTAssertTrue(CreateFileRequestValidator.isAllowed(
            directoryPath: "/Users/zhangpeng/code/project", baseName: "新建文件夹"))
    }

    // MARK: - baseName 白名单

    func test_baseNameWithPathSeparator_rejected() {
        XCTAssertFalse(CreateFileRequestValidator.isAllowed(
            directoryPath: "/Users/x", baseName: "../LaunchAgents/evil.plist"))
        XCTAssertFalse(CreateFileRequestValidator.isAllowed(
            directoryPath: "/Users/x", baseName: "a/b"))
    }

    func test_baseNameEmptyOrOversized_rejected() {
        XCTAssertFalse(CreateFileRequestValidator.isAllowed(directoryPath: "/Users/x", baseName: ""))
        XCTAssertFalse(CreateFileRequestValidator.isAllowed(directoryPath: "/Users/x", baseName: " "))
        let oversized = String(repeating: "a", count: 256)
        XCTAssertFalse(CreateFileRequestValidator.isAllowed(directoryPath: "/Users/x", baseName: oversized))
        XCTAssertEqual(String(repeating: "a", count: 255).utf8.count, 255, "用例自检")
    }

    func test_baseNameNullByte_rejected() {
        XCTAssertFalse(CreateFileRequestValidator.isAllowed(directoryPath: "/Users/x", baseName: "a\0b"))
    }

    // MARK: - directory 黑名单（持久化/系统位置）

    func test_persistenceDirectories_rejected() {
        for path in ["/Users/x/Library/LaunchAgents",
                     "/Users/x/Library/LaunchDaemons",
                     "/Library/LaunchAgents",
                     "/Library/LaunchDaemons",
                     "/System/Library/LaunchDaemons",
                     "/Users/x/Library/StartupItems"] {
            XCTAssertFalse(CreateFileRequestValidator.isAllowed(directoryPath: path, baseName: "ok.txt"),
                           "\(path) 不得作为目标目录")
        }
    }

    func test_systemRootDirectories_rejected() {
        for path in ["/System", "/System/Volumes/Data", "/Library", "/Library/Application Support"] {
            XCTAssertFalse(CreateFileRequestValidator.isAllowed(directoryPath: path, baseName: "ok.txt"),
                           "\(path) 不得作为目标目录")
        }
    }

    func test_userLibraryOtherSubdirectories_allowed() {
        XCTAssertTrue(CreateFileRequestValidator.isAllowed(
            directoryPath: "/Users/x/Library/Mobile Documents", baseName: "doc.pdf"),
            "只拉黑持久化/系统目录，不波及用户 Library 其余位置")
    }
}
