import Foundation

/// 贴图呼吸灯样式变更通知：设置窗口切换后，已打开的贴图立即生效。
public extension Notification.Name {
    static let pinIndicatorStyleDidChange =
        Notification.Name("com.zp.shengshoubuying.pin-indicator-style-did-change")
}

/// 贴图呼吸灯样式：顶部横条（默认）或左上角圆点。
public enum PinIndicatorStyle: String, Codable, Equatable, CaseIterable {
    /// 顶部横条呼吸灯，宽度与贴图等宽，高度/距顶部距离/颜色可配置。
    case topBar
    /// 左上角圆点闪烁指示（兼关闭按钮）。
    case cornerDot
}

/// 呼吸灯横条外观取值范围与默认值（纯逻辑，便于单测）。
public enum PinIndicatorAppearance {
    /// 默认呼吸灯高度（点）。
    public static let defaultHeight: CGFloat = 4
    /// 默认距贴图顶部间距（点）。
    public static let defaultTopInset: CGFloat = 2
    /// 呼吸灯高度可调范围。
    public static let heightRange: ClosedRange<CGFloat> = 1...8
    /// 距顶部间距可调范围。
    public static let topInsetRange: ClosedRange<CGFloat> = 0...10

    /// 呼吸最低不透明度：低于此值灯体会淡成"幻影弧线"（用户曾误认为显示缺陷）。
    public static let breathMinOpacity: CGFloat = 0.45
    /// 呼吸最高不透明度。
    public static let breathMaxOpacity: CGFloat = 1.0

    public static func clamped(height: CGFloat) -> CGFloat {
        Swift.max(heightRange.lowerBound, Swift.min(heightRange.upperBound, height))
    }

    public static func clamped(topInset: CGFloat) -> CGFloat {
        Swift.max(topInsetRange.lowerBound, Swift.min(topInsetRange.upperBound, topInset))
    }
}

/// 贴图设置状态（可扩展更多字段）。
/// 解码时缺失字段回退默认（兼容旧版本配置文件）。
public struct PinSettingsState: Codable, Equatable {
    public var indicatorStyle: PinIndicatorStyle
    /// 呼吸灯横条高度（点）。
    public var indicatorHeight: CGFloat
    /// 呼吸灯横条距贴图顶部间距（点）。
    public var indicatorTopInset: CGFloat
    /// 呼吸灯颜色（hex，不含 #）。
    public var indicatorColorHex: String

    public init(indicatorStyle: PinIndicatorStyle = .topBar,
                indicatorHeight: CGFloat = PinIndicatorAppearance.defaultHeight,
                indicatorTopInset: CGFloat = PinIndicatorAppearance.defaultTopInset,
                indicatorColorHex: String = PinIndicatorColor.defaultHex) {
        self.indicatorStyle = indicatorStyle
        self.indicatorHeight = PinIndicatorAppearance.clamped(height: indicatorHeight)
        self.indicatorTopInset = PinIndicatorAppearance.clamped(topInset: indicatorTopInset)
        self.indicatorColorHex = indicatorColorHex
    }

    private enum CodingKeys: String, CodingKey {
        case indicatorStyle, indicatorHeight, indicatorTopInset, indicatorColorHex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            indicatorStyle: try container.decodeIfPresent(PinIndicatorStyle.self, forKey: .indicatorStyle) ?? .topBar,
            indicatorHeight: try container.decodeIfPresent(CGFloat.self, forKey: .indicatorHeight)
                ?? PinIndicatorAppearance.defaultHeight,
            indicatorTopInset: try container.decodeIfPresent(CGFloat.self, forKey: .indicatorTopInset)
                ?? PinIndicatorAppearance.defaultTopInset,
            indicatorColorHex: try container.decodeIfPresent(String.self, forKey: .indicatorColorHex)
                ?? PinIndicatorColor.defaultHex
        )
    }
}

/// 贴图设置持久化：JSON 存 Application Support，损坏/缺失回退默认。
/// 通过 fileURL 注入便于单测；副作用（文件系统）藏在此处。
public struct PinSettingsStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// App 默认存储位置。
    public static func defaultStore() -> PinSettingsStore {
        let dir = AppSupportDirectory.url
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return PinSettingsStore(fileURL: dir.appendingPathComponent("pin_settings.json"))
    }

    public func load() -> PinSettingsState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(PinSettingsState.self, from: data) else {
            return PinSettingsState()
        }
        return state
    }

    public func save(_ state: PinSettingsState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
