import AVKit
import AppKit

/// 录屏预览面板：AVPlayer 播放 + 保存 / 复制 / 关闭按钮行。
/// 层级 screenSaver+4（预览惯例），非模态；ESC 关闭由模块的本地监听处理。
final class RecordingPreviewPanel: NSPanel {

    var onSave: (() -> Void)?
    var onCopy: (() -> Void)?
    var onClose: (() -> Void)?

    private var playerView: AVPlayerView?

    init(fileURL: URL) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                   styleMask: [.titled, .closable, .resizable],
                   backing: .buffered, defer: false)
        title = "录屏预览"
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 4)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 520))
        contentView = content

        let playerView = AVPlayerView(frame: content.bounds)
        playerView.autoresizingMask = [.width, .height]
        playerView.player = AVPlayer(url: fileURL)
        content.addSubview(playerView)
        self.playerView = playerView

        let saveButton = NSButton(title: "保存到 ~/Movies/Recordings", target: self, action: #selector(saveClicked))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        let copyButton = NSButton(title: "复制", target: self, action: #selector(copyClicked))
        copyButton.bezelStyle = .rounded
        let closeButton = NSButton(title: "关闭", target: self, action: #selector(closeClicked))
        closeButton.bezelStyle = .rounded

        let stack = NSStackView(views: [saveButton, copyButton, closeButton])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: content.topAnchor),
            playerView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: stack.topAnchor, constant: -10),
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }

    /// 预览关闭/释放时停止播放。
    func stopPlayback() {
        playerView?.player?.pause()
        playerView?.player = nil
    }

    // MARK: - 动作

    @objc private func saveClicked() { onSave?() }
    @objc private func copyClicked() { onCopy?() }
    @objc private func closeClicked() { onClose?() }
}
