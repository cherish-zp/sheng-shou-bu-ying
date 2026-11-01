import AppKit

/// 工具条按钮工厂（纯构造，TDD）：集中管理带标签按钮的样式与文案顺序。
/// 教训：`attributedTitle` 设置后再写 `title = ""` 会把标签覆盖成空串——
/// 延时子面板三个按钮曾因此"隐形"。顺序必须是 title 先、attributedTitle 后。
public enum ToolbarButtonFactory {

    /// 延时截图档位按钮：深色面板上的白色 "Ns" 标签，tag 携带秒数。
    public static func delayButton(seconds: Int, target: AnyObject?, action: Selector?) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 40, height: 28))
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.backgroundColor = UITheme.toolbarControl.cgColor
        button.title = ""
        button.tag = seconds
        button.toolTip = "\(seconds) 秒后截取当前画面"
        button.target = target
        button.action = action
        button.attributedTitle = NSAttributedString(string: "\(seconds)s", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UITheme.chromeText,
        ])
        return button
    }
}
