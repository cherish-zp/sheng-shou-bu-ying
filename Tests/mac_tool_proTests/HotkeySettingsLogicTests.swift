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
        XCTAssertTrue(panes[1].subviews.contains { $0 is FlowingGlassView },
                      "快捷键面板应注入流光玻璃")
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
}
