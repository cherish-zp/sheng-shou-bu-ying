import AppKit
import Speech
import AVFoundation

/// 语音听写：SFSpeechRecognizer（zh-CN）+ 麦克风实时转写，结果一键复制。
final class DictationWindowController: NSObject, SFSpeechRecognizerDelegate {
    let window: NSWindow
    private let transcriptView: NSTextView
    private let statusLabel: NSTextField
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var isRecording = false

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
                          styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
        let transcript = NSTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 200))
        transcriptView = transcript
        statusLabel = NSTextField(labelWithString: "未在录音")
        super.init()

        window.title = "语音听写"
        window.isReleasedWhenClosed = false
        UITheme.applyDark(window)
        window.center()
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 320))
        content.autoresizingMask = [.width, .height]
        window.contentView = content
        UITheme.stylePanel(content)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        UITheme.styleCard(scroll)
        transcript.font = .systemFont(ofSize: 14)
        transcript.textColor = UITheme.textPrimary
        transcript.drawsBackground = false
        transcript.isEditable = false
        transcript.autoresizingMask = [.width]
        scroll.documentView = transcript
        content.addSubview(scroll)

        let toggle = NSButton(title: "开始听写", target: self, action: #selector(toggleDictation))
        toggle.bezelStyle = .rounded
        toggle.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(toggle)

        let copy = NSButton(title: "复制全文", target: self, action: #selector(copyTranscript))
        copy.bezelStyle = .rounded
        copy.controlSize = .small
        copy.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(copy)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = UITheme.textSecondary
        content.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: toggle.topAnchor, constant: -10),
            toggle.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            toggle.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            copy.leadingAnchor.constraint(equalTo: toggle.trailingAnchor, constant: 8),
            copy.centerYAnchor.constraint(equalTo: toggle.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: toggle.centerYAnchor),
        ])
    }

    func showPanel() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleDictation() {
        isRecording ? stop() : start()
    }

    private func start() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self = self, status == .authorized else {
                    self?.statusLabel.stringValue = "需要语音识别权限"
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async { granted ? self.beginRecording() : self.fail() }
                }
            }
        }
    }

    private func beginRecording() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        do { try audioEngine.start() } catch {
            statusLabel.stringValue = "麦克风启动失败"
            return
        }
        isRecording = true
        (window.contentView?.subviews.compactMap { $0 as? NSButton }.first)?.title = "停止"
        statusLabel.stringValue = "听写中…"

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, _ in
            guard let self = self, let result = result else { return }
            self.transcriptView.string = result.bestTranscription.formattedString
            self.transcriptView.scrollToEndOfDocument(nil)
        }
    }

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?

    private func fail() {
        statusLabel.stringValue = "需要麦克风权限"
    }

    private func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
        (window.contentView?.subviews.compactMap { $0 as? NSButton }.first)?.title = "开始听写"
        statusLabel.stringValue = "已停止"
    }

    @objc private func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcriptView.string, forType: .string)
        statusLabel.stringValue = "已复制全文"
    }
}
