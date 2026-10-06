import CoreGraphics
import Foundation

/// 放大镜取样网格计算（纯逻辑）：把「光标位置 + 放大倍数 + 放大镜尺寸」
/// 换算为源位图上的像素取样坐标网格。
/// 坐标约定：位图像素坐标、左上原点（与 CGImage 内存布局一致）；
/// 屏幕点坐标（NS 全局、左下原点）→ 像素坐标的换算也在此统一封装，
/// 保证 Retina scaleFactor 与 y 翻转只算一遍。
public enum ColorMagnifierGridMath {

    /// 屏幕全局点（NS 坐标、左下原点）→ 该屏预捕获位图像素坐标（左上原点）。
    /// 缩放比用位图尺寸 / 屏幕点尺寸的比例（即 backingScaleFactor 的等效值），
    /// 兼容位图与屏幕点尺寸非严格整数倍的设备；入参退化时返回 .zero（调用方以越界防御兜底）。
    public static func cursorPixel(cursorInScreen: CGPoint,
                                   screenFrame: CGRect,
                                   imagePixelSize: CGSize) -> CGPoint {
        guard screenFrame.width > 0, screenFrame.height > 0,
              imagePixelSize.width > 0, imagePixelSize.height > 0 else { return .zero }
        let viewX = cursorInScreen.x - screenFrame.origin.x
        let viewY = cursorInScreen.y - screenFrame.origin.y
        let scaleX = imagePixelSize.width / screenFrame.width
        let scaleY = imagePixelSize.height / screenFrame.height
        return CGPoint(x: viewX * scaleX, y: (screenFrame.height - viewY) * scaleY)
    }

    /// 光标像素位置 → 放大镜取样网格（行优先、自上而下，每格 1 个源像素，已夹取到位图内）。
    /// - Parameters:
    ///   - cursorPixel: 光标在源位图中的像素坐标（可含小数，内部取整到最近像素）。
    ///   - imageSize: 源位图像素尺寸。
    ///   - magnification: 放大倍数（9 = 9×；<=0 时按 1 处理）。
    ///   - magnifierRadiusInPoints: 放大镜显示半径（点）。覆盖的源像素半径 =
    ///     显示半径 × backingScale ÷ 放大倍数（Retina 下屏幕点先换算为设备像素）。
    ///   - backingScale: 屏幕 backingScaleFactor（1 = 普通屏，2 = Retina）。
    /// 网格为 (2*step+1)×(2*step+1)；光标贴近边缘时越界格被夹取到边界像素（边缘拉伸显示）。
    public static func samplePoints(cursorPixel: CGPoint,
                                    imageSize: CGSize,
                                    magnification: CGFloat,
                                    magnifierRadiusInPoints: CGFloat,
                                    backingScale: CGFloat) -> [[CGPoint]] {
        guard imageSize.width >= 1, imageSize.height >= 1, magnifierRadiusInPoints >= 0 else { return [] }
        let mag = Swift.max(magnification, 1)
        let scale = Swift.max(backingScale, 1)
        let radiusInPixels = magnifierRadiusInPoints * scale / mag
        let step = Int(radiusInPixels.rounded(.up))
        let centerX = Int(cursorPixel.x.rounded())
        let centerY = Int(cursorPixel.y.rounded())
        let maxX = Int(imageSize.width) - 1
        let maxY = Int(imageSize.height) - 1
        var rows: [[CGPoint]] = []
        for dy in -step...step {
            var row: [CGPoint] = []
            row.reserveCapacity(2 * step + 1)
            for dx in -step...step {
                let x = Swift.min(Swift.max(centerX + dx, 0), maxX)
                let y = Swift.min(Swift.max(centerY + dy, 0), maxY)
                row.append(CGPoint(x: x, y: y))
            }
            rows.append(row)
        }
        return rows
    }
}
