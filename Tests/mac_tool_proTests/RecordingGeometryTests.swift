import XCTest

/// TDD: 录屏几何换算 - 选区视图坐标（左下原点，点）→ 显示器像素矩形
/// （左上原点，Retina 缩放，偶数对齐，夹取屏内）→ SCKit sourceRect（点）。
final class RecordingGeometryTests: XCTestCase {

    // 视图/屏幕：1080pt 高、2x Retina（2160px 高）、宽 1000pt
    private let screenFrame = CGRect(x: 0, y: 0, width: 1000, height: 1080)
    private let scale: CGFloat = 2

    // MARK: - y 翻转

    func test_yFlip_topLeftSelection() {
        // 选区贴屏幕顶部：视图 y = [1080-100, 1080]，应映射到像素 y = 0（顶部）
        let viewRect = CGRect(x: 100, y: 980, width: 300, height: 100)
        let px = RecordingGeometry.pixelRect(
            forSelection: viewRect, screenHeightPoints: screenFrame.height,
            scale: scale, displayPixelSize: CGSize(width: 2000, height: 2160))
        XCTAssertEqual(px.origin.x, 200)
        XCTAssertEqual(px.origin.y, 0, "顶部选区翻转后像素 y 应为 0")
        XCTAssertEqual(px.width, 600)
        XCTAssertEqual(px.height, 200)
    }

    func test_yFlip_bottomSelection() {
        // 选区贴屏幕底部：视图 y = [0, 80]，应映射到像素底部
        let viewRect = CGRect(x: 0, y: 0, width: 100, height: 80)
        let px = RecordingGeometry.pixelRect(
            forSelection: viewRect, screenHeightPoints: screenFrame.height,
            scale: scale, displayPixelSize: CGSize(width: 2000, height: 2160))
        XCTAssertEqual(px.origin.y, 2160 - 160, "底部选区翻转后应贴像素底部")
    }

    // MARK: - Retina 缩放

    func test_scale_2x() {
        let viewRect = CGRect(x: 10, y: 10, width: 40, height: 30)
        let px = RecordingGeometry.pixelRect(
            forSelection: viewRect, screenHeightPoints: screenFrame.height,
            scale: scale, displayPixelSize: CGSize(width: 2000, height: 2160))
        XCTAssertEqual(px.width, 80)
        XCTAssertEqual(px.height, 60)
    }

    func test_scale_1x() {
        let viewRect = CGRect(x: 10, y: 500, width: 40, height: 30)
        let px = RecordingGeometry.pixelRect(
            forSelection: viewRect, screenHeightPoints: 1080,
            scale: 1, displayPixelSize: CGSize(width: 1000, height: 1080))
        XCTAssertEqual(px.width, 40)
        XCTAssertEqual(px.height, 30)
    }

    // MARK: - 偶数对齐（H.264 要求偶数宽高）

    func test_evenAlignment_oddEdges() {
        // 1x 下奇数坐标：origin (11, 501)，宽 41 高 31 → 偶数对齐
        let viewRect = CGRect(x: 11, y: 501, width: 41, height: 31)
        let px = RecordingGeometry.pixelRect(
            forSelection: viewRect, screenHeightPoints: 1080,
            scale: 1, displayPixelSize: CGSize(width: 1000, height: 1080))
        XCTAssertEqual(Int(px.width) % 2, 0, "宽须为偶数")
        XCTAssertEqual(Int(px.height) % 2, 0, "高须为偶数")
        XCTAssertGreaterThanOrEqual(px.width, 40)
        XCTAssertGreaterThanOrEqual(px.height, 30)
    }

    // MARK: - 夹取屏内

    func test_clamp_toDisplayBounds() {
        // 选区超出屏幕右/下边界（异常防御）时不得产生越界像素矩形
        let viewRect = CGRect(x: 990, y: 0, width: 100, height: 60)
        let px = RecordingGeometry.pixelRect(
            forSelection: viewRect, screenHeightPoints: 1080,
            scale: 1, displayPixelSize: CGSize(width: 1000, height: 1080))
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 1000, height: 1080).contains(px),
                      "像素矩形必须落在显示器像素范围内：\(px)")
    }

    // MARK: - 像素 → sourceRect（点，左上原点）

    func test_sourceRectPoints_roundTrip() {
        let viewRect = CGRect(x: 100, y: 900, width: 300, height: 100)
        let px = RecordingGeometry.pixelRect(
            forSelection: viewRect, screenHeightPoints: screenFrame.height,
            scale: scale, displayPixelSize: CGSize(width: 2000, height: 2160))
        let source = RecordingGeometry.sourceRectPoints(fromPixelRect: px, scale: scale)
        // sourceRect 与像素矩形逐项还原一致（±0.5pt 对齐误差）
        XCTAssertEqual(source.minX, viewRect.minX, accuracy: 0.6)
        // y：视图顶部选区 → sourceRect 顶部（y≈0）
        XCTAssertEqual(source.minY, screenFrame.height - viewRect.maxY, accuracy: 0.6)
        XCTAssertEqual(source.width, viewRect.width, accuracy: 0.6)
        XCTAssertEqual(source.height, viewRect.height, accuracy: 0.6)
    }

    // MARK: - 整屏

    func test_fullScreen_selectionCoversWholeScreen() {
        let viewRect = CGRect(x: 0, y: 0, width: 1000, height: 1080)
        let px = RecordingGeometry.pixelRect(
            forSelection: viewRect, screenHeightPoints: 1080,
            scale: 2, displayPixelSize: CGSize(width: 2000, height: 2160))
        XCTAssertEqual(px, CGRect(x: 0, y: 0, width: 2000, height: 2160))
    }
}
