import AppKit

/// 拖拽会话期间激活的顶部热区视图：内容拖入（文件/文本/图片/链接）即呼出面板，
/// 落入即入列。通过闭包回调控制器，不直接引用单例。
final class TransferShelfHotZoneView: NSView {

    /// 可识别内容进入热区（呼出面板）。
    var onContentEntered: (() -> Void)?
    /// 内容落入热区（解析结果含四类条目与拒绝提示）→ 控制器 accept。
    var onContentDropped: ((TransferIntakeResult) -> Void)?

    /// 拖拽提示胶囊（拖入悬停期间可见，落下面板显示后即隐）。
    private let hintLabel = NSTextField(labelWithString: "拖到这里暂存")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .URL, .string, .tiff, .png])
        // 极淡背景确保窗口参与系统拖拽 hit-test（完全透明可能被跳过）
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.02).cgColor

        // 提示胶囊：白 10% 圆角底 + 淡入淡出
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .labelColor
        hintLabel.alignment = .center
        hintLabel.wantsLayer = true
        hintLabel.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.10).cgColor
        hintLabel.layer?.cornerRadius = TransferShelfLayoutSpec.hotHintSize.height / 2
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.alphaValue = 0
        addSubview(hintLabel)
        NSLayoutConstraint.activate([
            hintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            hintLabel.widthAnchor.constraint(equalToConstant: TransferShelfLayoutSpec.hotHintSize.width),
            hintLabel.heightAnchor.constraint(equalToConstant: TransferShelfLayoutSpec.hotHintSize.height),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func wantsPeriodicDraggingUpdates() -> Bool {
        false
    }

    private func setHintVisible(_ visible: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.allowsImplicitAnimation = true
            hintLabel.animator().alphaValue = visible ? 1 : 0
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let result = TransferItemKindIntake.result(from: sender.draggingPasteboard)
        guard !result.items.isEmpty || result.rejectionMessage != nil else { return [] }
        setHintVisible(true)
        onContentEntered?()
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setHintVisible(false)
    }

    /// 落入热区的内容交给控制器入列（含超限拒绝提示）；完全无法识别才吞掉。
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setHintVisible(false)
        let result = TransferItemKindIntake.result(from: sender.draggingPasteboard)
        guard !result.items.isEmpty || result.rejectionMessage != nil else { return false }
        onContentDropped?(result)
        return true
    }
}
