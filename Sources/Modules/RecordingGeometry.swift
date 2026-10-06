import CoreGraphics

/// 录屏几何换算（纯函数）：
/// 选区视图坐标（屏幕局部、左下原点、点）→ 显示器像素矩形（左上原点、Retina 缩放、
/// 偶数对齐、夹取屏内）→ ScreenCaptureKit sourceRect（点、左上原点）。
/// y 翻转口径与 ScrollCaptureSession.displayCaptureRect 一致（CG 显示器空间左上原点）。
public enum RecordingGeometry {

    /// 选区视图矩形 → 显示器像素矩形（左上原点）。
    /// H.264 要求偶数宽高：原点向下取偶、尺寸向上取偶，再夹取到显示器像素范围内。
    /// - Parameters:
    ///   - viewRect: 选区（屏幕局部视图坐标，左下原点，点）
    ///   - screenHeightPoints: 屏幕高度（点）
    ///   - scale: backingScaleFactor
    ///   - displayPixelSize: 显示器像素尺寸（宽×高）
    public static func pixelRect(
        forSelection viewRect: CGRect,
        screenHeightPoints: CGFloat,
        scale: CGFloat,
        displayPixelSize: CGSize
    ) -> CGRect {
        let safeScale = scale > 0 ? scale : 1
        // 视图坐标（左下原点）→ 显示器点坐标（左上原点）：y = 屏高 - maxY
        let displayPoints = CGRect(
            x: viewRect.minX,
            y: screenHeightPoints - viewRect.maxY,
            width: viewRect.width,
            height: viewRect.height
        )
        // 点 → 像素
        let px = CGRect(
            x: displayPoints.minX * safeScale,
            y: displayPoints.minY * safeScale,
            width: displayPoints.width * safeScale,
            height: displayPoints.height * safeScale
        )
        // 偶数对齐：origin 向下取偶，size 向上取偶
        var x = evenFloor(px.minX)
        var y = evenFloor(px.minY)
        var width = evenCeil(px.width)
        var height = evenCeil(px.height)
        // 夹取到显示器像素范围内（防御异常选区）
        let maxX = evenFloor(CGFloat(displayPixelSize.width))
        let maxY = evenFloor(CGFloat(displayPixelSize.height))
        x = min(max(0, x), max(0, maxX - 2))
        y = min(max(0, y), max(0, maxY - 2))
        width = min(max(2, width), maxX - x)
        height = min(max(2, height), maxY - y)
        width = evenFloor(width)
        height = evenFloor(height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// 显示器像素矩形（左上原点）→ SCKit sourceRect（点，左上原点）。
    public static func sourceRectPoints(fromPixelRect pixelRect: CGRect, scale: CGFloat) -> CGRect {
        let safeScale = scale > 0 ? scale : 1
        return CGRect(
            x: pixelRect.minX / safeScale,
            y: pixelRect.minY / safeScale,
            width: pixelRect.width / safeScale,
            height: pixelRect.height / safeScale
        )
    }

    // MARK: - 私有

    private static func evenFloor(_ value: CGFloat) -> CGFloat {
        CGFloat(Int(value / 2) * 2)
    }

    private static func evenCeil(_ value: CGFloat) -> CGFloat {
        evenFloor(value) + (value.truncatingRemainder(dividingBy: 2) > 0 ? 2 : 0)
    }
}
