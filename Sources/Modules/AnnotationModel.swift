import CoreGraphics
import Foundation

/// 标注类型：矩形、箭头、文字、马赛克、画笔、序号。
public enum AnnotationType: String, Codable, CaseIterable {
    case rectangle
    case arrow
    case text
    case mosaic
    case pen
    case counter
}

/// 标注颜色：预设调色板 + 自定义 RGB 颜色。
public enum AnnotationColor: Codable, Equatable, Hashable {
    case red, green, blue, purple, white, black
    case custom(red: CGFloat, green: CGFloat, blue: CGFloat)

    /// 预设颜色列表（颜色选择面板展示用），顺序：红、绿、蓝、紫、白、黑。
    public static let presets: [AnnotationColor] = [.red, .green, .blue, .purple, .white, .black]

    /// 返回颜色的 RGB 分量（0-1），用于绘制和色块展示。
    public var rgbComponents: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        switch self {
        case .red: return (1.0, 0.231, 0.188)
        case .green: return (0.203, 0.780, 0.349)
        case .blue: return (0.0, 0.478, 1.0)
        case .purple: return (0.5, 0.0, 0.5)
        case .white: return (1.0, 1.0, 1.0)
        case .black: return (0.0, 0.0, 0.0)
        case .custom(let r, let g, let b): return (r, g, b)
        }
    }
}

/// 单个标注：类型 + 点序列 + 可选文字 + 颜色 + 线宽。
/// - 矩形：points[0]=origin, points[1]=对角点
/// - 箭头：points[0]=起点, points[1]=终点
/// - 文字：points[0]=左上角定位点，text 存内容
/// - 马赛克：points[0]=origin, points[1]=对角点
/// - 画笔：points 为自由绘制路径点序列（多点）
/// - 序号：points[0]=徽章圆心，text 存序号字符串（"1"、"2"…）
public struct Annotation: Codable, Equatable, Identifiable {
    public let id: UUID
    public var type: AnnotationType
    public var points: [CGPoint]
    public var text: String?
    public var color: AnnotationColor
    public var strokeWidth: CGFloat

    public init(
        id: UUID = UUID(),
        type: AnnotationType,
        points: [CGPoint],
        text: String? = nil,
        color: AnnotationColor = .red,
        strokeWidth: CGFloat = 3
    ) {
        self.id = id
        self.type = type
        self.points = points
        self.text = text
        self.color = color
        self.strokeWidth = strokeWidth
    }
}

/// 标注集合：管理添加/删除/撤销/清空，支持 Codable 序列化。
public final class AnnotationModel: Codable {
    public private(set) var annotations: [Annotation] = []
    /// 下一个序号标注的序号（从 1 起）。重新选中序号工具时由外部调 resetCounter() 复位。
    public private(set) var counterNext: Int = 1

    public init() {}

    public var count: Int { annotations.count }

    /// 是否有可撤销的标注（用于启用/禁用撤销按钮）。
    public var canUndo: Bool { !annotations.isEmpty }

    public func add(_ annotation: Annotation) {
        annotations.append(annotation)
    }

    public func remove(at index: Int) {
        guard annotations.indices.contains(index) else { return }
        annotations.remove(at: index)
    }

    /// 撤销最后一个标注，返回被移除的标注（空时返回 nil）。
    /// 撤销序号标注时序号回退（下一个序号重用被撤销的编号），撤销其他类型不影响序号。
    @discardableResult
    public func undo() -> Annotation? {
        let popped = annotations.popLast()
        if popped?.type == .counter {
            counterNext = max(1, counterNext - 1)
        }
        return popped
    }

    public func clear() {
        annotations.removeAll()
    }

    // MARK: - 序号标注

    /// 重新选中序号工具时复位序号，下一次放置从 1 开始。
    public func resetCounter() {
        counterNext = 1
    }

    /// 创建并追加一个序号标注：实心圆徽章 + 白色序号，圆心为点击点（相对选区原点的局部坐标），
    /// 颜色跟随当前主题色；序号自动递增。
    @discardableResult
    public func addCounter(at point: CGPoint, color: AnnotationColor) -> Annotation {
        let annotation = Annotation(
            type: .counter,
            points: [point],
            text: String(counterNext),
            color: color
        )
        annotations.append(annotation)
        counterNext += 1
        return annotation
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case annotations
        case counterNext
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        annotations = try container.decode([Annotation].self, forKey: .annotations)
        // 旧版本数据无该字段时默认从 1 开始
        counterNext = try container.decodeIfPresent(Int.self, forKey: .counterNext) ?? 1
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(annotations, forKey: .annotations)
        try container.encode(counterNext, forKey: .counterNext)
    }

    /// 选颜色时确定使用的标注工具：未选工具则默认矩形，使「点颜色即可画框」。
    public static func defaultTool(whenColorSelected currentTool: AnnotationType?) -> AnnotationType? {
        currentTool ?? .rectangle
    }

    /// 创建文字标注：空文本返回 nil（不创建无效标注）。
    public static func textAnnotation(at point: CGPoint, text: String, color: AnnotationColor) -> Annotation? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Annotation(type: .text, points: [point], text: trimmed, color: color)
    }
}
