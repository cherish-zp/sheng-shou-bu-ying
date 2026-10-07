import XCTest
import Foundation

/// TDD: 片段数据变更通知名定义在纯逻辑层（SnippetStore），SnippetManager 保存后发送。
final class SnippetManagerNotificationTests: XCTestCase {

    func test_notificationName_exists() {
        XCTAssertEqual(Notification.Name.snippetsDidChange.rawValue, "com.zp.shengshoubuying.snippetsDidChange")
    }

    func test_notification_roundTrip() {
        let expectation = XCTestExpectation(description: "notification received")
        let observer = NotificationCenter.default.addObserver(
            forName: .snippetsDidChange, object: nil, queue: nil
        ) { _ in
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        NotificationCenter.default.post(name: .snippetsDidChange, object: nil)
        wait(for: [expectation], timeout: 2.0)
    }
}
