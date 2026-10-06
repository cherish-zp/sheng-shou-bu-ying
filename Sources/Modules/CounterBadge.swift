import CoreGraphics

/// 序号标注徽章几何：实心圆形徽章 + 白色序号，圆心即画布点击点。
/// 纯函数，供覆盖层绘制与最终图合成共用。
public enum CounterBadge {

    /// 徽章圆直径（视图点）。
    public static let diameter: CGFloat = 20

    /// 以点击点为中心的徽章圆 rect。
    public static func rect(centeredAt point: CGPoint) -> CGRect {
        CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2,
               width: diameter, height: diameter)
    }

    /// 序号文字字号：1-2 位 13pt，3 位 11pt，更多位 9pt（保证两位数内视觉均衡）。
    public static func fontSize(forDigits digits: Int) -> CGFloat {
        switch digits {
        case ..<3: return 13
        case 3: return 11
        default: return 9
        }
    }
}
