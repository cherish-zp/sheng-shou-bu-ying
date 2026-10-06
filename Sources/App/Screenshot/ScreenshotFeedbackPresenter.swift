import AppKit

/// 截图结果反馈层：成功用轻量 Toast（苹果风毛玻璃 HUD），失败用 NSAlert 承载错误细节。
///
/// 与 CopyToastPresenter 的差异（故独立实现而非直接复用）：
/// 1. 文案可定制——保存需展示目标文件名，复制为「已复制到剪贴板」；
/// 2. Toast 可点击——保存成功后点击在 Finder 中定位文件；
/// 3. 层级取 screenSaver+3——CopyToastPresenter 用 .statusBar，会被全屏截图
///    覆盖层（screenSaver）遮挡，长截图结果窗流程中必须抬高层级。
final class ScreenshotFeedbackPresenter {

    /// Toast 外观与节奏（对齐 CopyToastSpec 的苹果风参数）。
    private enum Spec {
        static let fadeInDuration: TimeInterval = 0.18
        static let visibleDuration: TimeInterval = 1.6
        static let fadeOutDuration: TimeInterval = 0.28
        static let cornerRadius: CGFloat = 14
        static let topGap: CGFloat = 8
        static let iconSize: CGFloat = 18
        static let symbolName = "checkmark.circle.fill"
    }

    private var toastPanel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?
    /// 展示代数：连续 show 时旧 Toast 的定时隐藏作废。
    private var generation = 0
    /// 当前 Toast 的点击回调（保存成功时在 Finder 中定位文件）。
    private var toastClickHandler: (() -> Void)?

    // MARK: - 公开 API

    /// 保存成功：Toast「已保存到 <文件名>」，点击 Toast 在 Finder 中定位该文件。
    func showSaved(url: URL) {
        DiagLog.write("Feedback.showSaved: \(url.path)")
        showToast(text: "已保存到 \(url.lastPathComponent)") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    /// 复制成功：Toast「已复制到剪贴板」。
    func showCopied() {
        DiagLog.write("Feedback.showCopied")
        showToast(text: "已复制到剪贴板", clickHandler: nil)
    }

    /// 保存失败：NSAlert 弹窗（Toast 不适合承载错误细节）。
    func showSaveFailed(message: String) {
        DiagLog.write("Feedback.showSaveFailed: \(message)")
        presentAlert(title: "保存失败", message: message)
    }

    /// 长截图失败：NSAlert 弹窗。
    func showCaptureFailed(message: String) {
        DiagLog.write("Feedback.showCaptureFailed: \(message)")
        presentAlert(title: "长截图失败", message: message)
    }

    // MARK: - Toast

    private func showToast(text: String, clickHandler: (() -> Void)? = nil) {
        DispatchQueue.main.async { [weak self] in
            self?.presentToast(text: text, clickHandler: clickHandler)
        }
    }

    private func presentToast(text: String, clickHandler: (() -> Void)?) {
        generation += 1
        let currentGeneration = generation
        hideWorkItem?.cancel()
        hideWorkItem = nil

        // 每次重建面板：宽度随文案自适应，重建成本远低于动态约束更新
        let panel = makeToastPanel(text: text, clickable: clickHandler != nil)
        toastPanel = panel
        toastClickHandler = clickHandler
        position(panel)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Spec.fadeInDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        })

        let item = DispatchWorkItem { [weak self, weak panel] in
            guard let self = self, self.generation == currentGeneration else { return }
            self.dismiss(panel)
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Spec.fadeInDuration + Spec.visibleDuration, execute: item)
    }

    /// 构建毛玻璃 Toast 面板：图标 + 文案，宽度按文本实测自适应。
    private func makeToastPanel(text: String, clickable: Bool) -> NSPanel {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let textWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        // 左右内边距 14 + 图标 18 + 图标与文字间距 7；超长文件名截断（byTruncatingMiddle）
        let panelWidth = min(460, 14 + Spec.iconSize + 7 + textWidth + 14)
        let panelHeight: CGFloat = 44

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // 高于全屏截图覆盖层（screenSaver），避免被遮挡
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        panel.hidesOnDeactivate = false

        let visual = NSVisualEffectView()
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = Spec.cornerRadius
        visual.layer?.masksToBounds = true
        visual.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = visual

        let symbol = NSImage(systemSymbolName: Spec.symbolName, accessibilityDescription: text) ?? NSImage()
        let icon = NSImageView(image: symbol)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(icon)

        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(label)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: visual.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: visual.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: Spec.iconSize),
            icon.heightAnchor.constraint(equalToConstant: Spec.iconSize),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
            label.centerYAnchor.constraint(equalTo: visual.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: visual.trailingAnchor, constant: -14),
        ])

        if clickable {
            let click = NSClickGestureRecognizer(target: self, action: #selector(toastClicked(_:)))
            visual.addGestureRecognizer(click)
        }
        return panel
    }

    /// 点击 Toast：立即消失并执行回调（Finder 定位）。
    @objc private func toastClicked(_ sender: NSClickGestureRecognizer) {
        generation += 1
        hideWorkItem?.cancel()
        hideWorkItem = nil
        toastPanel?.orderOut(nil)
        toastPanel = nil
        let handler = toastClickHandler
        toastClickHandler = nil
        handler?()
    }

    /// Toast 定位：主屏菜单栏下方居中。
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.maxY - panel.frame.height - Spec.topGap
        )
        panel.setFrameOrigin(origin)
    }

    private func dismiss(_ panel: NSPanel?) {
        guard let panel = panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Spec.fadeOutDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self = self, self.toastPanel === panel, panel.alphaValue == 0 else { return }
            panel.orderOut(nil)
        })
    }

    // MARK: - Alert

    /// 模态错误提示：层级抬到 screenSaver+3，避免被截图覆盖层遮挡。
    private func presentAlert(title: String, message: String) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "好")
            alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
            alert.runModal()
        }
    }
}
