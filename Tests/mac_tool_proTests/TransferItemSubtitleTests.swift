import XCTest
import Foundation
import AppKit

/// TDD: 条目副标题的纯逻辑格式化。
/// 1) 相对时间:刚刚 / N 分钟前 / HH:mm(时钟注入可测);
/// 2) 文件大小:B/KB/MB/GB,1 位小数去尾零;
/// 3) QL 预览序列:只含 file 条目,hover 定位起始索引,hover 非 file 时不响应。
final class TransferItemSubtitleTests: XCTestCase {

    // MARK: - 相对时间

    func test_relativeTimeWithinOneMinute() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertEqual(TransferItemRelativeTime.string(from: now.addingTimeInterval(-30), now: now), "刚刚")
        XCTAssertEqual(TransferItemRelativeTime.string(from: now, now: now), "刚刚")
    }

    func test_relativeTimeWithinOneHour() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertEqual(TransferItemRelativeTime.string(from: now.addingTimeInterval(-60), now: now), "1 分钟前")
        XCTAssertEqual(TransferItemRelativeTime.string(from: now.addingTimeInterval(-5 * 60), now: now), "5 分钟前")
        XCTAssertEqual(TransferItemRelativeTime.string(from: now.addingTimeInterval(-59 * 60), now: now), "59 分钟前")
    }

    func test_relativeTimeBeyondOneHourFallsBackToClockTime() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let over = now.addingTimeInterval(-61 * 60)
        let formatted = TransferItemRelativeTime.string(from: over, now: now)
        XCTAssertEqual(formatted, Self.clockString(over), "超过 1 小时显示 HH:mm 本地时间")
    }

    func test_relativeTimeFutureTimestampIsJustNow() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertEqual(TransferItemRelativeTime.string(from: now.addingTimeInterval(10), now: now), "刚刚",
                       "时钟回拨/边界误差下不应出现负数分钟")
    }

    private static func clockString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - 文件大小

    func test_fileSizeBytes() {
        XCTAssertEqual(TransferItemFileSize.string(bytes: 0), "0 B")
        XCTAssertEqual(TransferItemFileSize.string(bytes: 512), "512 B")
        XCTAssertEqual(TransferItemFileSize.string(bytes: 1023), "1023 B")
    }

    func test_fileSizeKB() {
        XCTAssertEqual(TransferItemFileSize.string(bytes: 1024), "1 KB")
        XCTAssertEqual(TransferItemFileSize.string(bytes: 1536), "1.5 KB")
        XCTAssertEqual(TransferItemFileSize.string(bytes: 1024 * 1024 - 1), "1024 KB")
    }

    func test_fileSizeMB() {
        XCTAssertEqual(TransferItemFileSize.string(bytes: 1024 * 1024), "1 MB")
        XCTAssertEqual(TransferItemFileSize.string(bytes: 1_266_000), "1.2 MB", "1 位小数")
    }

    func test_fileSizeGB() {
        XCTAssertEqual(TransferItemFileSize.string(bytes: 3 * 1024 * 1024 * 1024), "3 GB")
    }

    // MARK: - Quick Look 数据源条目序列

    func test_previewURLsContainOnlyFileItems() {
        let fileA = TransferItem(url: URL(fileURLWithPath: "/tmp/a.pdf"))
        let text = TransferItem.text("hello")
        let fileB = TransferItem(url: URL(fileURLWithPath: "/tmp/b.pdf"))
        let link = TransferItem.link(URL(string: "https://e.com")!)
        let urls = TransferShelfQuickLookIndex.previewURLs(for: [fileA, text, fileB, link])
        XCTAssertEqual(urls.map(\.path), ["/tmp/a.pdf", "/tmp/b.pdf"],
                       "QL 序列只给文件条目(text/link 没有可预览文件)")
    }

    func test_startIndexLocatesHoveredFile() {
        let fileA = TransferItem(url: URL(fileURLWithPath: "/tmp/a.pdf"))
        let text = TransferItem.text("hello")
        let fileB = TransferItem(url: URL(fileURLWithPath: "/tmp/b.pdf"))
        let items = [fileA, text, fileB]
        XCTAssertEqual(
            TransferShelfQuickLookIndex.startIndex(for: items, hovered: fileB.id), 1,
            "hover 第二个文件条目时 QL 应从其在文件序列中的位置开始"
        )
    }

    func test_startIndexNilForHoveredNonFileItem() {
        let text = TransferItem.text("hello")
        XCTAssertNil(TransferShelfQuickLookIndex.startIndex(for: [text], hovered: text.id),
                     "hover 非 file 条目按 Space 不应打开 QL")
    }

    func test_startIndexNilWithoutHover() {
        let fileA = TransferItem(url: URL(fileURLWithPath: "/tmp/a.pdf"))
        XCTAssertNil(TransferShelfQuickLookIndex.startIndex(for: [fileA], hovered: nil))
    }
}

/// TDD: F2 手动呼出位置记忆(UserDefaults 注入可测)+ 越界 clamp。
final class TransferShelfManualPositionTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "transfer-position-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func test_noSavedOriginReturnsNil() {
        XCTAssertNil(TransferShelfManualPosition.savedOrigin(in: defaults))
    }

    func test_saveAndLoadOrigin() {
        TransferShelfManualPosition.save(origin: NSPoint(x: 120, y: 760), in: defaults)
        XCTAssertEqual(TransferShelfManualPosition.savedOrigin(in: defaults), NSPoint(x: 120, y: 760))
    }

    func test_clampedOriginInsideScreenUnchanged() {
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = TransferShelfManualPosition.clampedOrigin(
            NSPoint(x: 600, y: 810), visibleFrame: frame, panelSize: NSSize(width: 220, height: 80)
        )
        XCTAssertEqual(origin, NSPoint(x: 600, y: 810))
    }

    func test_clampedOriginLeftOverflow() {
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = TransferShelfManualPosition.clampedOrigin(
            NSPoint(x: -50, y: 810), visibleFrame: frame, panelSize: NSSize(width: 220, height: 80)
        )
        XCTAssertEqual(origin.x, 0, "左越界拉回屏内")
    }

    func test_clampedOriginRightOverflow() {
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = TransferShelfManualPosition.clampedOrigin(
            NSPoint(x: 1400, y: 810), visibleFrame: frame, panelSize: NSSize(width: 220, height: 80)
        )
        XCTAssertEqual(origin.x, 1440 - 220, "右越界拉回屏内")
    }

    func test_clampedOriginBottomOverflow() {
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        // y=-10 才是真正的底越界（面板 80 高，origin.y=-10 → 底部越出 10pt）；y=10 在屏内不需要拉回
        let origin = TransferShelfManualPosition.clampedOrigin(
            NSPoint(x: 600, y: -10), visibleFrame: frame, panelSize: NSSize(width: 220, height: 80)
        )
        XCTAssertEqual(origin.y, 0, "底越界拉回屏内")
    }

    func test_clampedOriginRespectsVisibleFrameOffset() {
        let frame = NSRect(x: 100, y: 60, width: 1200, height: 800)
        let origin = TransferShelfManualPosition.clampedOrigin(
            NSPoint(x: -20, y: -5), visibleFrame: frame, panelSize: NSSize(width: 220, height: 80)
        )
        XCTAssertEqual(origin.x, 100, "非零原点屏(多屏)下 clamp 到可见区边界")
        XCTAssertEqual(origin.y, 60)
    }

    func test_clampedOriginPanelLargerThanScreen() {
        let frame = NSRect(x: 0, y: 0, width: 100, height: 50)
        let origin = TransferShelfManualPosition.clampedOrigin(
            NSPoint(x: 40, y: 30), visibleFrame: frame, panelSize: NSSize(width: 220, height: 80)
        )
        XCTAssertEqual(origin, NSPoint(x: 0, y: 0), "面板比屏大时按屏原点兜底(max/min 混合收敛)")
    }

    // MARK: - resolvedOrigin（记忆点整体合法性：防跨屏悬空坐标）

    /// 真机实证：坏记忆 (2478, 22)——x 落在右屏区间、y 落在主屏区间，分量独立
    /// clamp 造出「不属于任何屏」的悬空坐标，面板不可见且坏值每次呼出被回存驻留。
    /// resolvedOrigin 语义：记忆点代表的整块面板必须完全落在当前鼠标屏可见区内，
    /// 否则放弃记忆回到顶部中央。
    func test_resolvedOrigin_validMemoryKept() {
        let frame = NSRect(x: 0, y: 0, width: 1728, height: 1084)
        let origin = TransferShelfManualPosition.resolvedOrigin(
            saved: NSPoint(x: 600, y: 900), visibleFrame: frame,
            panelSize: NSSize(width: 420, height: 88))
        XCTAssertEqual(origin, NSPoint(x: 600, y: 900), "合法记忆原样保留")
    }

    func test_resolvedOrigin_crossScreenGapFallsBackToTopCenter() {
        let mainVisible = NSRect(x: 0, y: 0, width: 1728, height: 1084)
        let origin = TransferShelfManualPosition.resolvedOrigin(
            saved: NSPoint(x: 2478, y: 22), visibleFrame: mainVisible,
            panelSize: NSSize(width: 420, height: 88))
        XCTAssertEqual(origin.x, (1728 - 420) / 2, accuracy: 0.1,
                       "记忆整体越界 → 顶部中央 x")
        XCTAssertEqual(origin.y, 1084 - 88 - TransferShelfLayoutSpec.topGap, accuracy: 0.1,
                       "顶部中央 y")
    }

    func test_resolvedOrigin_partialOverflowFallsBack() {
        // x 合法但 y 越界（面板下半探出屏外）也整块判非法 → 顶部中央
        let frame = NSRect(x: 0, y: 0, width: 1728, height: 1084)
        let origin = TransferShelfManualPosition.resolvedOrigin(
            saved: NSPoint(x: 600, y: -30), visibleFrame: frame,
            panelSize: NSSize(width: 420, height: 88))
        XCTAssertEqual(origin.x, (1728 - 420) / 2, accuracy: 0.1)
    }

    func test_resolvedOrigin_nilMemoryGoesTopCenter() {
        let frame = NSRect(x: 0, y: 0, width: 1728, height: 1084)
        let origin = TransferShelfManualPosition.resolvedOrigin(
            saved: nil, visibleFrame: frame, panelSize: NSSize(width: 420, height: 88))
        XCTAssertEqual(origin.x, (1728 - 420) / 2, accuracy: 0.1)
        XCTAssertEqual(origin.y, 1084 - 88 - TransferShelfLayoutSpec.topGap, accuracy: 0.1)
    }

    func test_resolvedOrigin_nonZeroOriginScreen() {
        // 外接屏（非零原点）：合法记忆保留、越界回落到该屏顶部中央
        let extVisible = NSRect(x: 1728, y: 114, width: 1920, height: 1003)
        let ok = TransferShelfManualPosition.resolvedOrigin(
            saved: NSPoint(x: 2478, y: 990), visibleFrame: extVisible,
            panelSize: NSSize(width: 420, height: 88))
        XCTAssertEqual(ok, NSPoint(x: 2478, y: 990), "外接屏内合法记忆保留")
        let bad = TransferShelfManualPosition.resolvedOrigin(
            saved: NSPoint(x: 100, y: 22), visibleFrame: extVisible,
            panelSize: NSSize(width: 420, height: 88))
        XCTAssertEqual(bad.x, 1728 + (1920 - 420) / 2, accuracy: 0.1, "越界回落外接屏顶部中央")
    }
}
