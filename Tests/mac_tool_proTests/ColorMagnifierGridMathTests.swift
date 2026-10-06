import XCTest
import CoreGraphics

/// TDD: 放大镜取样网格 - 光标像素 → 源位图取样坐标网格；
/// 屏幕 NS 坐标（左下原点）→ 位图像素（左上原点）的换算含 scaleFactor 与 y 翻转。
final class ColorMagnifierGridMathTests: XCTestCase {

    // MARK: - cursorPixel（点 → 像素换算）

    func test_cursorPixel_centerAndYFlip() {
        // 主屏 (0,0,100,50) NS 坐标、位图 200x100（等效 scale 2）：
        // 光标 (50, 25) → 视图 (50, 25) → 像素 x=100、y=(50-25)*2=50（y 翻转）
        let px = ColorMagnifierGridMath.cursorPixel(
            cursorInScreen: CGPoint(x: 50, y: 25),
            screenFrame: CGRect(x: 0, y: 0, width: 100, height: 50),
            imagePixelSize: CGSize(width: 200, height: 100))
        XCTAssertEqual(px.x, 100, accuracy: 0.001)
        XCTAssertEqual(px.y, 50, accuracy: 0.001)
    }

    func test_cursorPixel_screenWithOffset() {
        // 副屏 (100,0,100,50)，光标 (110, 40) → 视图 (10, 40) → 像素 (20, 20)
        let px = ColorMagnifierGridMath.cursorPixel(
            cursorInScreen: CGPoint(x: 110, y: 40),
            screenFrame: CGRect(x: 100, y: 0, width: 100, height: 50),
            imagePixelSize: CGSize(width: 200, height: 100))
        XCTAssertEqual(px.x, 20, accuracy: 0.001)
        XCTAssertEqual(px.y, 20, accuracy: 0.001)
    }

    func test_cursorPixel_degenerateInputsReturnZero() {
        XCTAssertEqual(ColorMagnifierGridMath.cursorPixel(
            cursorInScreen: .zero, screenFrame: .zero,
            imagePixelSize: CGSize(width: 10, height: 10)), .zero)
        XCTAssertEqual(ColorMagnifierGridMath.cursorPixel(
            cursorInScreen: .zero, screenFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            imagePixelSize: .zero), .zero)
    }

    // MARK: - samplePoints（取样网格）

    /// 9× 放大、显示半径 45pt、Retina(scale 2)：源像素半径 = 45*2/9 = 10 → step 10 → 21×21。
    private let retinaParams = (magnification: CGFloat(9), radius: CGFloat(45), scale: CGFloat(2))

    func test_samplePoints_gridSizeAndCenter() {
        let grid = ColorMagnifierGridMath.samplePoints(
            cursorPixel: CGPoint(x: 50, y: 50),
            imageSize: CGSize(width: 200, height: 100),
            magnification: retinaParams.magnification,
            magnifierRadiusInPoints: retinaParams.radius,
            backingScale: retinaParams.scale)
        XCTAssertEqual(grid.count, 21)
        XCTAssertEqual(grid[0].count, 21)
        XCTAssertEqual(grid[10][10], CGPoint(x: 50, y: 50), "网格中心 = 光标像素")
        XCTAssertEqual(grid[0][0], CGPoint(x: 40, y: 40), "左上角 = 光标 - 半径")
    }

    func test_samplePoints_nonRetinaSize() {
        // 非Retina scale 1：75/9 ≈ 8.34 → step 9 → 19×19
        let grid = ColorMagnifierGridMath.samplePoints(
            cursorPixel: CGPoint(x: 100, y: 100),
            imageSize: CGSize(width: 500, height: 500),
            magnification: 9, magnifierRadiusInPoints: 75, backingScale: 1)
        XCTAssertEqual(grid.count, 19)
        XCTAssertEqual(grid[0].count, 19)
    }

    func test_samplePoints_clampsNearEdges() {
        let grid = ColorMagnifierGridMath.samplePoints(
            cursorPixel: CGPoint(x: 2, y: 2),
            imageSize: CGSize(width: 200, height: 100),
            magnification: 9, magnifierRadiusInPoints: 45, backingScale: 2)
        XCTAssertEqual(grid[0][0], CGPoint(x: 0, y: 0), "越界格夹取到边界像素")
        XCTAssertEqual(grid[10][10], CGPoint(x: 2, y: 2), "中心保持光标位置")
        XCTAssertEqual(grid.count, 21, "夹取不改变网格形状")
    }

    func test_samplePoints_clampsOutsideImage() {
        let grid = ColorMagnifierGridMath.samplePoints(
            cursorPixel: CGPoint(x: 999, y: -5),
            imageSize: CGSize(width: 10, height: 10),
            magnification: 1, magnifierRadiusInPoints: 5, backingScale: 1)
        for row in grid {
            for p in row {
                XCTAssertTrue(p.x >= 0 && p.x <= 9 && p.y >= 0 && p.y <= 9, "所有取样点都在位图内")
            }
        }
    }

    func test_samplePoints_emptyImageReturnsEmpty() {
        XCTAssertTrue(ColorMagnifierGridMath.samplePoints(
            cursorPixel: .zero, imageSize: .zero,
            magnification: 9, magnifierRadiusInPoints: 45, backingScale: 2).isEmpty)
    }
}
