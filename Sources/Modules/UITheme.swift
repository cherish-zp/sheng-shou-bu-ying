import AppKit

/// UI 设计令牌：对标浮引的深色面板风格（深底 + 彩色分类点缀 + 系统蓝强调）。
/// 所有新功能窗口统一从此取色，保证视觉一致；变更只改这里。
public enum UITheme {

    // MARK: - 面板基调（深色，不随系统外观切换）

    /// 面板底色（流光玻璃由 FlowingGlassView 承担，此处为兜底浅色）。
    public static let panelBackground = NSColor(srgbRed: 0.97, green: 0.95, blue: 0.99, alpha: 0.6)
    /// 卡片底色（白色半透明，玻璃上再叠一层）。
    public static let cardBackground = NSColor.white.withAlphaComponent(0.45)
    /// 卡片悬停底色。
    public static let cardHover = NSColor.white.withAlphaComponent(0.7)
    /// 描边/分隔（深色低透明）。
    public static let hairline = NSColor.black.withAlphaComponent(0.10)

    // MARK: - 文字

    public static let textPrimary = NSColor(srgbRed: 0.12, green: 0.10, blue: 0.16, alpha: 1)
    public static let textSecondary = NSColor.black.withAlphaComponent(0.5)

    // MARK: - 强调与语义色

    /// 主强调色（系统蓝，对齐浮引 AccentColor）。
    public static let accent = NSColor.systemBlue
    public static let destructive = NSColor.systemRed
    public static let success = NSColor.systemGreen
    public static let warning = NSColor.systemOrange

    // MARK: - 分类色板（浮引 8 色马卡龙板，用于模块/条目分类点缀）

    public static let categoryPalette: [NSColor] = [
        NSColor(srgbRed: 0xE8 / 255, green: 0x73 / 255, blue: 0x4A / 255, alpha: 1),
        NSColor(srgbRed: 0xD9 / 255, green: 0xA0 / 255, blue: 0x3C / 255, alpha: 1),
        NSColor(srgbRed: 0xD9 / 255, green: 0x57 / 255, blue: 0x5C / 255, alpha: 1),
        NSColor(srgbRed: 0xD8 / 255, green: 0x5B / 255, blue: 0x64 / 255, alpha: 1),
        NSColor(srgbRed: 0x8B / 255, green: 0x6C / 255, blue: 0xD9 / 255, alpha: 1),
        NSColor(srgbRed: 0x4A / 255, green: 0x87 / 255, blue: 0xD9 / 255, alpha: 1),
        NSColor(srgbRed: 0x3F / 255, green: 0xA8 / 255, blue: 0xB8 / 255, alpha: 1),
        NSColor(srgbRed: 0x33 / 255, green: 0xA0 / 255, blue: 0x7A / 255, alpha: 1),
    ]

    /// 按稳定 key（如工具 id）散列取分类色，同一 key 永远同色。
    public static func categoryColor(for key: String) -> NSColor {
        let index = abs(key.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % categoryPalette.count
        return categoryPalette[index]
    }

    // MARK: - 截图套件工具条（深色 chrome）

    /// 工具条/浮层底色（流光化：玻璃由 FlowingGlassView 承担，此为兜底浅色）。
    public static let toolbarBackground = NSColor.white.withAlphaComponent(0.55)
    /// 工具条上的次级控件底（深色低透明叠加）。
    public static let toolbarControl = NSColor.black.withAlphaComponent(0.06)
    /// 工具条分隔线。
    public static let toolbarSeparator = NSColor.black.withAlphaComponent(0.10)
    /// 工具条文字/单色图标色（玻璃上为深色）。
    public static let chromeText = textPrimary

    // MARK: - 几何

    public static let panelCornerRadius: CGFloat = 14
    public static let cardCornerRadius: CGFloat = 10
    public static let controlCornerRadius: CGFloat = 6

    // MARK: - 便捷样式

    /// 把窗口居中到目标屏（默认鼠标所在屏——用户视线所在处）。
    public static func center(_ window: NSWindow, on screen: NSScreen? = nil) {
        let target = screen
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        guard let target = target else { return }
        let frame = window.frame
        window.setFrameOrigin(NSPoint(
            x: target.frame.midX - frame.width / 2,
            y: target.frame.midY - frame.height / 2))
    }

    /// 窗口流光化：透明底 + 浅色外观 + 异步注入流光玻璃背景层。
    /// 所有功能窗口 show/init 时必须调用；contentView 稍后设置也能生效（异步兜底）。
    public static func applyDark(_ window: NSWindow) {
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: .aqua)
        DispatchQueue.main.async {
            guard let content = window.contentView else { return }
            // 已注入过则跳过（幂等）
            if content.subviews.contains(where: { $0 is FlowingGlassView }) { return }
            let glass = FlowingGlassView(frame: content.bounds)
            glass.autoresizingMask = [.width, .height]
            content.addSubview(glass, positioned: .below, relativeTo: nil)
        }
    }

    /// 滚动区深色化：关闭白底（NSScrollView 默认白）、清表格底色、去交替行浅色条。
    public static func darkScroll(_ scroll: NSScrollView) {
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        if let table = scroll.documentView as? NSTableView {
            table.backgroundColor = .clear
            table.usesAlternatingRowBackgroundColors = false
        }
    }

    /// 给面板视图统一上深色底 + 圆角 + 描边。
    public static func stylePanel(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.cornerRadius = panelCornerRadius
        view.layer?.borderWidth = 1
        view.layer?.borderColor = hairline.cgColor
    }

    /// 给卡片视图统一卡片样式。
    public static func styleCard(_ view: NSView, tint: NSColor? = nil) {
        view.wantsLayer = true
        view.layer?.backgroundColor = cardBackground.cgColor
        view.layer?.cornerRadius = cardCornerRadius
        view.layer?.borderWidth = 1
        view.layer?.borderColor = hairline.cgColor
        if let tint = tint {
            view.layer?.borderColor = tint.withAlphaComponent(0.45).cgColor
        }
    }
}
