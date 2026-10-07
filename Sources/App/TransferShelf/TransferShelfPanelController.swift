import AppKit

/// 文件中转站面板控制器：顶部毛玻璃面板，接收文件拖入暂存 URL 引用，
/// 条目可拖出到 Finder/其他 App，点击定位，右键管理。
/// 本文件只保留控制器职责；视图分别为 ShelfView / ItemView / HotZoneView。
final class TransferShelfPanelController: NSObject {

    private var shelfPanel: NSPanel?
    private var hotZonePanel: NSPanel?
    /// 热区视图（拖拽会话激活时创建）；internal 供注入交互测试断言。
    private(set) var hotZoneView: TransferShelfHotZoneView?
    /// 暂存面板内容视图；internal 供显示同步与注入交互测试断言。
    private(set) var shelfView: TransferShelfShelfView?
    private var hideWorkItem: DispatchWorkItem?
    private var isDragSessionActive = false
    /// 面板可见期间的失效巡检定时器：文件被移走/删除后自动移除条目。
    private var validityTimer: Timer?
    /// 显隐状态机：show/hide 打断与迟到完成回调的唯一裁决（见 TransferShelfPanelVisibilityMachine）。
    private var visibility = TransferShelfPanelVisibilityMachine()
    /// 测试可断言的当前显隐状态。
    var visibilityState: TransferShelfPanelVisibility { visibility.state }

    /// internal 只读，供测试断言注入路径下 store 的变化。
    private(set) var store: TransferShelfStore {
        didSet {
            guard !isRestoringPersisted else { return }
            persist()
        }
    }
    /// 恢复持久化数据期间抑制 didSet 的 persist（避免冗余回写）。
    private var isRestoringPersisted = false
    // 持久化路径为存储属性:测试注入临时路径,避免污染真实的暂存库。
    private let storageURL: URL
    /// 失效巡检队列：fileExists IO 在后台执行，结果回主线程应用。
    private let purgeQueue: DispatchQueue
    private static let defaultPurgeQueue = DispatchQueue(
        label: "com.zp.shengshoubuying.transfer-shelf.purge", qos: .utility
    )

    /// 模块持有：默认存储路径，启动时恢复持久化数据。
    override convenience init() {
        self.init(store: TransferShelfStore(), storageURL: Self.defaultStorageURL, loadsPersisted: true)
    }

    /// 测试注入点：显式给定 store 与持久化路径，跳过真实文件的加载。
    convenience init(store: TransferShelfStore, storageURL: URL) {
        self.init(store: store, storageURL: storageURL, loadsPersisted: false)
    }

    /// 测试注入点：从给定路径恢复持久化数据（验证加载/损坏备份路径）。
    convenience init(storageURL: URL, maxCount: Int = 20) {
        self.init(store: TransferShelfStore(maxCount: maxCount), storageURL: storageURL, loadsPersisted: true)
    }

    private init(store: TransferShelfStore, storageURL: URL, loadsPersisted: Bool) {
        self.store = store
        self.storageURL = storageURL
        self.purgeQueue = Self.defaultPurgeQueue
        super.init()
        if loadsPersisted {
            loadPersisted()
        }
    }

    private static var defaultStorageURL: URL {
        let dir = AppSupportDirectory.url
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("transfer_shelf.json")
    }

    // MARK: - 对外接口

    /// 显示面板。手动呼出优先用上次记忆的位置（无记录时顶部中央），
    /// 拖拽呼出维持顶部热区定位。
    @discardableResult
    func showPanel(manual: Bool = false) -> Bool {
        purgeInvalidItems()
        let panel = shelfPanel ?? makePanel()
        shelfPanel = panel
        // 面板可能刚重建(应用重启/自动隐藏后复用),必须与暂存库同步,
        // 否则库内已有条目时面板仍显示空态占位。
        shelfView?.render(items: store.items)
        if manual {
            applyManualPosition(panel)
        } else {
            applyTargetPosition(panel, display: true)
        }
        cancelScheduledHide()

        // 从顶部上方滑入 + 淡入 + 微缩放（0.96→1）；状态机先记录代数，被 hide 打断时迟到完成回调失效。
        let generation = visibility.beginShow()
        var startFrame = panel.frame
        startFrame.origin.y += TransferShelfLayoutSpec.slideInOffset
        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = TransferShelfLayoutSpec.fadeInDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(targetFrame(for: panel), display: true)
            panel.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            self?.visibility.endShow(generation: generation)
        })
        // 微缩放回弹（0.96→1）：transform 经 CATransaction 隐式动画
        if let contentLayer = panel.contentView?.layer {
            contentLayer.setAffineTransform(
                CGAffineTransform(scaleX: TransferShelfLayoutSpec.appearScale,
                                  y: TransferShelfLayoutSpec.appearScale)
            )
            CATransaction.begin()
            CATransaction.setAnimationDuration(TransferShelfLayoutSpec.fadeInDuration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            contentLayer.setAffineTransform(.identity)
            CATransaction.commit()
        }
        if !isDragSessionActive {
            scheduleHide(after: manual ? 5 : 3.5)
        }
        startValidityTimer()
        installSpaceMonitor()
        return true
    }

    /// 手动呼出定位：有记忆位置用记忆值（clamp 到目标屏可见区），否则顶部中央；
    /// 无论是否有记忆，定位后都记录本次位置（下次 F2 出现在同一处）。
    private func applyManualPosition(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen = screen else {
            applyTargetPosition(panel, display: true)
            return
        }
        let visible = screen.visibleFrame
        let size = shelfView?.preferredPanelSize() ?? panel.frame.size
        let height = min(size.height, visible.height - TransferShelfLayoutSpec.topGap * 2)
        let frameSize = NSSize(width: size.width, height: height)
        let defaults = UserDefaults.standard
        let saved = TransferShelfManualPosition.savedOrigin(in: defaults)
        let origin = TransferShelfManualPosition.clampedOrigin(
            saved ?? NSPoint(x: visible.midX - frameSize.width / 2,
                             y: visible.maxY - frameSize.height - TransferShelfLayoutSpec.topGap),
            visibleFrame: visible,
            panelSize: frameSize
        )
        panel.setFrame(NSRect(origin: origin, size: frameSize), display: true)
        if let shelfView = shelfView {
            shelfView.frame = NSRect(x: 0, y: 0, width: frameSize.width, height: frameSize.height)
        }
        TransferShelfManualPosition.save(origin: origin, in: defaults)
    }

    /// 全局拖拽会话开始：仅激活顶部热区，面板等文件真正拖入热区再出现，
    /// 避免拖动窗口等非文件拖拽时误弹面板。
    /// 不在这里做失效巡检——巡检含文件 IO，不能拖累拖拽启动；
    /// 巡检发生在 showPanel 与可见期定时器中。
    func dragSessionStarted() {
        isDragSessionActive = true
        cancelScheduledHide()
        activateHotZone()
    }

    /// 拖拽过程中鼠标进入顶部热区（几何兜底）：呼出面板。
    func hotZoneHovered() {
        guard isDragSessionActive else { return }
        showPanel()
    }

    /// 全局拖拽会话结束：面板停留片刻后滑出，禁用热区。
    func dragSessionEnded() {
        isDragSessionActive = false
        deactivateHotZone()
        scheduleHide(after: 3)
    }

    /// 模块停用：立即收起面板与热区，停止一切调度（监听由 Module 停止）。
    func deactivate() {
        isDragSessionActive = false
        cancelScheduledHide()
        stopValidityTimer()
        removeSpaceMonitor()
        visibility.reset()
        hotZonePanel?.orderOut(nil)
        hotZonePanel?.ignoresMouseEvents = true
        shelfPanel?.orderOut(nil)
    }

    // MARK: - 失效条目清理

    /// 移除文件已不存在（被移走/重命名/删除）的条目。
    /// fileExists IO 放到后台队列，结果回主线程应用——此前在主线程同步
    /// fileExists，任何 ≥30pt 的拖动（dragSessionStarted）都会触发主线程 IO。
    private func purgeInvalidItems() {
        guard !store.items.isEmpty else { return }
        let snapshot = store.items
        purgeQueue.async { [weak self] in
            // 只有 file 条目依赖文件存在性；text/image/link 的合成 URL 查不到文件，不能参与巡检
            let missingURLs = Set(
                snapshot.filter {
                    $0.kind == .file && !FileManager.default.fileExists(atPath: $0.url.path)
                }.map(\.url)
            )
            DispatchQueue.main.async { [weak self] in
                self?.removeInvalidItems(missingURLs: missingURLs)
            }
        }
    }

    /// 后台巡检结果回主线程应用：移除失效条目，面板可见时刷新渲染与定位。
    private func removeInvalidItems(missingURLs: Set<URL>) {
        guard !missingURLs.isEmpty else { return }
        let removed = store.purgeInvalid { !missingURLs.contains($0) }
        guard !removed.isEmpty else { return }
        DiagLog.write("TransferShelf purged \(removed.count) invalid item(s): \(removed.map(\.name).joined(separator: ", "))")
        if let panel = shelfPanel, panel.isVisible {
            shelfView?.render(items: store.items)
            applyTargetPosition(panel, display: true)
        }
    }

    /// 面板可见期间开启失效巡检（每 2s），隐藏时停止。
    private func startValidityTimer() {
        stopValidityTimer()
        validityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.purgeInvalidItems()
        }
    }

    private func stopValidityTimer() {
        validityTimer?.invalidate()
        validityTimer = nil
    }

    // MARK: - 面板构建

    private func makePanel() -> NSPanel {
        let shelf = TransferShelfShelfView(
            frame: NSRect(x: 0, y: 0,
                          width: TransferShelfLayoutSpec.emptyPanelWidth,
                          height: TransferShelfLayoutSpec.emptyPanelHeight)
        )
        // 去单例：视图经闭包回到本控制器，init(store:storageURL:) 注入路径即可覆盖视图交互。
        shelf.onAccept = { [weak self] urls in self?.accept(urls: urls) }
        shelf.onIntake = { [weak self] result in self?.accept(intake: result) }
        shelf.onRemove = { [weak self] id in self?.removeItem(id: id) }
        shelf.onClearAll = { [weak self] in self?.clearAll() }
        shelf.validateForDrag = { [weak self] id in self?.validateItemForDrag(id: id) ?? true }
        shelf.onInteracting = { [weak self] in self?.cancelScheduledHide() }
        shelf.quickLookSource = { [weak self] in self?.store.items ?? [] }
        shelfView = shelf

        let panel = NSPanel(
            contentRect: shelf.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        // fullScreenAuxiliary：全屏 App 的 Space 里面板也不被盖住（Yoink 标配行为）
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = shelf
        return panel
    }

    /// 顶部热区：拖拽会话期间激活，内容拖入即呼出/落入即入列（四类内容）。
    private func makeHotZonePanel() -> NSPanel {
        let view = TransferShelfHotZoneView(
            frame: NSRect(x: 0, y: 0,
                          width: TransferShelfLayoutSpec.hotZoneWidth,
                          height: TransferShelfLayoutSpec.hotZoneHeight)
        )
        view.onContentEntered = { [weak self] in
            self?.showPanel()
        }
        view.onContentDropped = { [weak self] result in
            self?.accept(intake: result)
        }
        hotZoneView = view

        let panel = NSPanel(
            contentRect: view.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.contentView = view
        return panel
    }

    private func activateHotZone() {
        let panel = hotZonePanel ?? makeHotZonePanel()
        hotZonePanel = panel
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen = screen else { return }
        let visible = screen.visibleFrame
        panel.setFrame(
            NSRect(
                x: visible.midX - TransferShelfLayoutSpec.hotZoneWidth / 2,
                y: visible.maxY - TransferShelfLayoutSpec.hotZoneHeight,
                width: TransferShelfLayoutSpec.hotZoneWidth,
                height: TransferShelfLayoutSpec.hotZoneHeight
            ),
            display: false
        )
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
    }

    private func deactivateHotZone() {
        hotZonePanel?.ignoresMouseEvents = true
        hotZonePanel?.orderOut(nil)
    }

    // MARK: - 定位

    /// 面板目标位置：贴住鼠标所在屏幕顶部中央（高度按可见区封顶）。
    private func targetFrame(for panel: NSPanel) -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen = screen else { return panel.frame }
        let visible = screen.visibleFrame
        let size = shelfView?.preferredPanelSize() ?? panel.frame.size
        let height = min(size.height, visible.height - TransferShelfLayoutSpec.topGap * 2)
        return NSRect(
            x: visible.midX - size.width / 2,
            y: visible.maxY - height - TransferShelfLayoutSpec.topGap,
            width: size.width,
            height: height
        )
    }

    /// 把面板摆到目标位置并让内容视图铺满（此前 position/positionedFrame 重复计算）。
    private func applyTargetPosition(_ panel: NSPanel, display: Bool) {
        panel.setFrame(targetFrame(for: panel), display: display)
        if let shelfView = shelfView {
            shelfView.frame = NSRect(x: 0, y: 0, width: panel.frame.width, height: panel.frame.height)
        }
    }

    // MARK: - 显示/隐藏调度

    private func scheduleHide(after delay: TimeInterval) {
        cancelScheduledHide()
        let item = DispatchWorkItem { [weak self] in
            self?.hidePanel()
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelScheduledHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    /// 隐藏面板（滑出 + 淡出）。返回是否真正开始了隐藏动画——
    /// 重复隐藏/已隐藏时拒绝（不再重启动画），show 进行中可被打断；
    /// 完成回调经状态机代数校验后才 orderOut，保证最终状态唯一。
    @discardableResult
    func hidePanel() -> Bool {
        stopValidityTimer()
        removeSpaceMonitor()
        guard let panel = shelfPanel, let generation = visibility.beginHideIfPossible() else {
            return false
        }
        var endFrame = panel.frame
        endFrame.origin.y += TransferShelfLayoutSpec.slideInOffset
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = TransferShelfLayoutSpec.fadeOutDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(endFrame, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            // 代数不匹配说明 hide 已被 show 打断：不得收起新一轮显示的面板。
            if self.visibility.endHide(generation: generation) {
                panel.orderOut(nil)
            }
        })
        return true
    }

    // MARK: - 持久化

    private func persist() {
        guard let data = store.encode() else {
            DiagLog.write("TransferShelf: encode failed, skip persist")
            return
        }
        do {
            try data.write(to: storageURL, options: .atomic)
        } catch {
            DiagLog.write("TransferShelf: persist failed: \(error.localizedDescription)")
        }
    }

    private func loadPersisted() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        guard let loaded = TransferShelfStore.load(from: data, maxCount: store.maxCount) else {
            // 解码失败不再无声清空：备份损坏文件便于排查，并以空库继续。
            quarantineCorruptFile()
            return
        }
        // 恢复即回写是冗余 IO（didSet 会 persist），用标志抑制。
        isRestoringPersisted = true
        store = loaded
        isRestoringPersisted = false
    }

    /// 把损坏的持久化文件改名备份为 .corrupt-yyyyMMddHHmmss。
    private func quarantineCorruptFile() {
        let stamp = Self.corruptStampFormatter.string(from: Date())
        let backupURL = storageURL.appendingPathExtension("corrupt-\(stamp)")
        do {
            try FileManager.default.moveItem(at: storageURL, to: backupURL)
            DiagLog.write("TransferShelf: 持久化文件损坏，已备份为 \(backupURL.lastPathComponent)")
        } catch {
            DiagLog.write("TransferShelf: 损坏文件备份失败: \(error.localizedDescription)")
        }
    }

    private static let corruptStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter
    }()

    // MARK: - 条目操作（供视图闭包回调）

    /// 接收拖入的文件 URL（ShelfView.onAccept 旧通道，单测注入使用）。
    func accept(urls: [URL]) {
        accept(intake: TransferItemKindIntake.result(
            fileURLs: urls, pngData: nil, text: nil, urlStrings: []
        ))
    }

    /// 接收拖入解析结果（四类条目 + 拒绝提示）：合法条目入列，
    /// 超限载荷弹 HUD 提示；去重也重新渲染。
    func accept(intake: TransferIntakeResult) {
        if let rejection = intake.rejectionMessage {
            TransientHudToast.show(text: rejection)
        }
        var changed = false
        for item in intake.items {
            if store.add(item: item) != nil {
                changed = true
            }
        }
        // 去重(拖入已暂存的同一内容)也要重新渲染:面板可能尚未显示库内
        // 条目,静默返回会让用户以为拖入失败。
        guard let panel = shelfPanel else { return }
        shelfView?.render(items: store.items)
        applyTargetPosition(panel, display: true)
        guard changed || intake.rejectionMessage != nil else { return }
        cancelScheduledHide()
        if !isDragSessionActive {
            scheduleHide(after: 3.5)
        }
    }

    /// 清空全部暂存条目（头部垃圾桶按钮）。
    func clearAll() {
        let count = store.items.count
        store.clear()
        shelfView?.render(items: store.items)
        if let panel = shelfPanel {
            applyTargetPosition(panel, display: true)
        }
        if count > 0 {
            TransientHudToast.show(text: "已清空 \(count) 项")
        }
    }

    /// 移除条目（条目视图删除按钮 / 右键菜单经闭包回调）。
    func removeItem(id: UUID) {
        if store.remove(id: id) {
            shelfView?.render(items: store.items)
            if let panel = shelfPanel {
                applyTargetPosition(panel, display: true)
            }
        }
    }

    /// 拖出兜底校验：仅 file 条目检查文件存在（不存在时移除条目），
    /// text/image/link 内容自带在条目上，直接放行。
    func validateItemForDrag(id: UUID) -> Bool {
        guard let item = store.items.first(where: { $0.id == id }) else { return false }
        guard item.kind == .file else { return true }
        if FileManager.default.fileExists(atPath: item.url.path) { return true }
        DiagLog.write("TransferShelf drag blocked for missing file: \(item.name)")
        removeItem(id: id)
        return false
    }

    // MARK: - Space 键 Quick Look

    /// 面板可见期间的本地 keyDown 监听：Space 打开 hover 条目的 Quick Look。
    /// 注意 nonactivatingPanel 通常不持有 key，此路径主要在面板交互后短暂生效；
    /// 常规入口是条目右键「快速查看」。
    private var spaceMonitor: Any?

    private func installSpaceMonitor() {
        guard spaceMonitor == nil else { return }
        spaceMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, event.keyCode == 49, self.shelfPanel?.isVisible == true else {
                return event
            }
            if self.shelfView?.toggleQuickLookForHovered() == true {
                self.cancelScheduledHide()
                return nil
            }
            return event
        }
    }

    private func removeSpaceMonitor() {
        if let monitor = spaceMonitor {
            NSEvent.removeMonitor(monitor)
            spaceMonitor = nil
        }
    }
}
