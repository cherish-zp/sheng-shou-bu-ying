import XCTest

/// TDD: 快捷键设置面板纯逻辑 —— 录制捕获（Esc 取消 / 纯修饰键忽略 / 组合键入绑）、
/// 冲突提示文案、注册失败警告文案。设置页录制交互的可测核心。
final class HotkeySettingsLogicTests: XCTestCase {

    // MARK: - 录制捕获

    func test_capture_escCancels() {
        XCTAssertEqual(HotkeyCapture.resolve(keyCode: 53, shiftHeld: false), .cancel)
        XCTAssertEqual(HotkeyCapture.resolve(keyCode: 53, shiftHeld: true), .cancel, "⇧Esc 也取消")
    }

    func test_capture_pureModifierKeyIgnored() {
        // 左右 Command(55/54)/Shift(56/60)/Option(58/61)/Control(59/62) + CapsLock(57)/Fn(63)：
        // 按下不产生绑定，录制继续等待组合键
        for keyCode: UInt32 in [54, 55, 56, 57, 58, 59, 60, 61, 62, 63] {
            XCTAssertEqual(HotkeyCapture.resolve(keyCode: keyCode, shiftHeld: false),
                           .ignore, "键码 \(keyCode) 应识别为纯修饰键")
        }
    }

    func test_capture_letterBindsWithoutShift() {
        XCTAssertEqual(HotkeyCapture.resolve(keyCode: 0, shiftHeld: false),
                       .bind(HotkeyBinding(keyCode: 0, usesShift: false)))
    }

    func test_capture_letterWithShiftCapturesShift() {
        XCTAssertEqual(HotkeyCapture.resolve(keyCode: 0, shiftHeld: true),
                       .bind(HotkeyBinding(keyCode: 0, usesShift: true)), "按住 ⇧ 录制应叠加 shift")
    }

    // MARK: - 冲突提示文案

    func test_conflictMessage_reportsConflictingTitle() {
        var candidate = HotkeyPreferences.withDefaults()
        candidate.bindings["screenshot"] = HotkeyBinding(keyCode: 7)   // 与剪贴板历史同为 X
        XCTAssertEqual(HotkeySettingsLogic.conflictMessage(candidate: candidate, changingId: "screenshot"),
                       "与「剪贴板历史」冲突，未保存")
    }

    func test_conflictMessage_noConflictReturnsNil() {
        let candidate = HotkeyPreferences.withDefaults()
        XCTAssertNil(HotkeySettingsLogic.conflictMessage(candidate: candidate, changingId: "screenshot"))
    }

    func test_conflictMessage_unrelatedIdIgnoresExistingConflict() {
        var candidate = HotkeyPreferences.withDefaults()
        candidate.bindings["screenshot"] = HotkeyBinding(keyCode: 7)   // 方案里已存在一组冲突
        XCTAssertNil(HotkeySettingsLogic.conflictMessage(candidate: candidate, changingId: "translate"),
                     "改动的功能不在冲突组内时不提示")
    }

    func test_conflictMessage_clearingOtherBindingResolvesConflict() {
        var candidate = HotkeyPreferences.withDefaults()
        candidate.bindings["screenshot"] = HotkeyBinding(keyCode: 7)
        candidate.bindings["clipboardHistory"] = nil                    // 对方已清除 → 冲突消失
        XCTAssertNil(HotkeySettingsLogic.conflictMessage(candidate: candidate, changingId: "screenshot"))
    }

    // MARK: - 注册失败警告文案

    func test_failureMessage_listsFailedTitles() {
        let failures = ["screenshot": Hotkey(keyCode: 0), "translate": Hotkey(keyCode: 17)]
        let message = HotkeySettingsLogic.failureMessage(failures: failures)
        XCTAssertNotNil(message)
        XCTAssertTrue(message!.contains("2 个快捷键注册失败"), "实际：\(message!)")
        XCTAssertTrue(message!.contains("截图"), "应列出失败功能名：\(message!)")
        XCTAssertTrue(message!.contains("翻译"), "应列出失败功能名：\(message!)")
    }

    func test_failureMessage_emptyReturnsNil() {
        XCTAssertNil(HotkeySettingsLogic.failureMessage(failures: [:]))
    }

    // MARK: - 设置窗口接线（快捷键 pane）

    private func makeSettingsWindow() -> SettingsWindow {
        let defaults = UserDefaults(suiteName: "HotkeySettingsLogicTests")!
        defaults.removePersistentDomain(forName: "HotkeySettingsLogicTests")
        let registry = AppModuleRegistry(
            hotkeyManager: HotkeyManager(registrar: FakeHotkeyRegistrar()),
            configDefaults: defaults
        )
        return SettingsWindow(moduleRegistry: registry, onModuleStateChanged: { _, _ in })
    }

    private func findTableView(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for sub in view.subviews {
            if let found = findTableView(in: sub) { return found }
        }
        return nil
    }

    func test_settingsWindow_sidebarListsHotkeyAfterGeneral() {
        let window = makeSettingsWindow()
        window.contentView?.layoutSubtreeIfNeeded()
        guard let table = findTableView(in: window.contentView!) else {
            return XCTFail("设置窗口内应有分类列表")
        }
        XCTAssertEqual(table.numberOfRows, 5, "侧栏应有五个分类")
        let general = table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView
        let hotkey = table.view(atColumn: 0, row: 1, makeIfNecessary: true) as? NSTableCellView
        XCTAssertEqual(general?.textField?.stringValue, "通用")
        XCTAssertEqual(hotkey?.textField?.stringValue, "快捷键", "「快捷键」应紧跟「通用」")
    }

    func test_settingsWindow_selectingHotkeyShowsPane() {
        let window = makeSettingsWindow()
        window.contentView?.layoutSubtreeIfNeeded()
        guard let table = findTableView(in: window.contentView!) else {
            return XCTFail("设置窗口内应有分类列表")
        }
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        window.contentView?.layoutSubtreeIfNeeded()

        guard let split = window.contentView?.subviews.compactMap({ $0 as? NSSplitView }).first else {
            return XCTFail("设置窗口内应有 NSSplitView")
        }
        XCTAssertEqual(split.arrangedSubviews.count, 6, "分类栏 + 五个分类面板")
        let panes = Array(split.arrangedSubviews.dropFirst())
        XCTAssertFalse(panes[1].isHidden, "选中「快捷键」时其面板应可见")
        XCTAssertTrue(panes[1] is HotkeySettingsPaneView, "index 1 应为快捷键面板")
        for (index, pane) in panes.enumerated() where index != 1 {
            XCTAssertTrue(pane.isHidden, "分类 \(index) 的面板在选中「快捷键」时应隐藏")
        }
        // 流光玻璃统一在窗口级一层（contentView 底层），pane 内不再重复注入
        XCTAssertTrue(window.contentView!.subviews.contains { $0 is FlowingGlassView },
                      "设置窗口应注入流光玻璃（窗口级一层）")
        XCTAssertFalse(panes[1].subviews.contains { $0 is FlowingGlassView },
                       "pane 内不得重复注入玻璃（避免多层叠加）")
    }

    func test_hotkeyPane_threeModifierSegmentsAndThirteenRows() {
        let window = makeSettingsWindow()
        window.contentView?.layoutSubtreeIfNeeded()

        guard let split = window.contentView?.subviews.compactMap({ $0 as? NSSplitView }).first else {
            return XCTFail("设置窗口内应有 NSSplitView")
        }
        let pane = split.arrangedSubviews[2]
        XCTAssertTrue(pane is HotkeySettingsPaneView)

        var segments: [NSSegmentedControl] = []
        var bindingButtons: [NSButton] = []
        var clearButtons: [NSButton] = []

        func walk(_ view: NSView) {
            if let control = view as? NSSegmentedControl {
                segments.append(control)
            }
            if let button = view as? NSButton {
                let id = button.identifier?.rawValue
                if let id, id.hasSuffix(".clear") {
                    clearButtons.append(button)
                } else if let id, HotkeyPreferences.catalog.contains(where: { $0.id == id }) {
                    bindingButtons.append(button)
                }
            }
            for sub in view.subviews { walk(sub) }
        }
        walk(pane)

        XCTAssertEqual(segments.count, 1, "应有一个主修饰键分段控件")
        XCTAssertEqual(segments.first?.segmentCount, 3, "主修饰键三选：⌥/⌃/⌘")
        XCTAssertEqual(bindingButtons.count, 13, "应有 13 个功能组合键按钮")
        XCTAssertEqual(clearButtons.count, 13, "应有 13 个 × 清除按钮")
    }

    /// 回归：功能组合键按钮构造后必须带当前绑定文案（此前 bindingButtons 字典
    /// 未填充、refreshLabel 全部 no-op，13 个按钮 title 恒空——真机上只见空按钮）。
    func test_functionBindingButtons_showCurrentBindingLabels() {
        let window = makeSettingsWindow()
        window.contentView?.layoutSubtreeIfNeeded()

        guard let pane = window.contentView?.subviews.compactMap({ $0 as? NSSplitView }).first?.arrangedSubviews[2],
              pane is HotkeySettingsPaneView else {
            return XCTFail("未找到快捷键面板")
        }
        let prefs = HotkeyPreferences.load()
        var checked = 0
        func walk(_ view: NSView) {
            if let button = view as? NSButton, let id = button.identifier?.rawValue,
               HotkeyPreferences.catalog.contains(where: { $0.id == id }) {
                let expected = prefs.displayLabel(for: id) ?? "无"
                XCTAssertEqual(button.title, expected,
                               "\(id) 按钮应显示当前绑定「\(expected)」，不得为空")
                checked += 1
            }
            for sub in view.subviews { walk(sub) }
        }
        walk(pane)
        XCTAssertEqual(checked, 13, "应校验全部 13 个按钮")
    }

    /// 回归：滚动文档必须以 0 常量钉 clip view（NSClipView 自动管理滚动约束，
    /// 手动非零常量会被冲突打破——真机实证 28pt 边距被吃掉、内容贴死分割条），
    /// 视觉边距（28pt）由内层内容容器承担（与通用/贴图 pane 同一布局模式）。
    func test_hotkeyPane_documentView_zeroPinnedAndInnerPadding() {
        let window = makeSettingsWindow()
        window.contentView?.layoutSubtreeIfNeeded()

        guard let pane = window.contentView?.subviews.compactMap({ $0 as? NSSplitView }).first?.arrangedSubviews[2] else {
            return XCTFail("未找到快捷键面板")
        }
        guard let scroll = findScrollView(in: pane) else {
            return XCTFail("快捷键面板应有内容滚动区")
        }
        guard let doc = scroll.documentView else {
            return XCTFail("滚动区应有文档视图")
        }
        // 跨视图约束由公共祖先持有（此处为 scroll.contentView），递归收集全部约束再过滤
        var allConstraints: [NSLayoutConstraint] = []
        func collect(_ view: NSView) {
            allConstraints.append(contentsOf: view.constraints)
            for sub in view.subviews { collect(sub) }
        }
        collect(pane)
        // 文档视图四向钉 clip view 的常量必须全为 0（leading/top/widing/bottom≥）
        let docEdgeConstraints = allConstraints.filter { $0.firstItem === doc && $0.secondItem === scroll.contentView }
        XCTAssertGreaterThanOrEqual(docEdgeConstraints.count, 3, "文档应钉 clip view 至少三向")
        for c in docEdgeConstraints {
            XCTAssertEqual(c.constant, 0, "文档钉 clip view 的常量必须为 0（非零会与滚动约束冲突被打破）")
        }
        // 视觉边距由内层内容容器承担：内层栈 leading == 文档 leading + 28、top ≥ 16
        let inner = doc.subviews.first
        XCTAssertNotNil(inner, "文档内应有内容容器")
        let innerLeading = allConstraints.filter {
            $0.firstItem === inner && $0.firstAttribute == .leading
                && $0.secondItem === doc && $0.relation == .equal
        }
        XCTAssertEqual(innerLeading.map(\.constant).min(), 28, "内容容器应距文档左缘 28pt（与其他 pane 一致）")
        let innerTop = allConstraints.filter {
            $0.firstItem === inner && $0.firstAttribute == .top
                && $0.secondItem === doc && $0.relation == .equal
        }
        XCTAssertLessThanOrEqual(innerTop.map(\.constant).min() ?? 999, 20,
                                 "内容容器顶部间距不得过大（此前真机空白 230pt 的回归网）")
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews {
            if let found = findScrollView(in: sub) { return found }
        }
        return nil
    }
}
