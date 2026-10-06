import XCTest

/// TDD: 设置窗口布局回归 - 右侧贴图面板必须位于左侧分类栏右侧且不重叠，
/// 分类栏保持 180pt，面板内容不得溢出面板边界。
/// 背景：曾把 arrangedSubview 钉满父视图四边，与 NSSplitView 内部约束冲突，
/// Auto Layout 断链后整窗内容堆叠错乱。
final class SettingsWindowLayoutTests: XCTestCase {

    private func makeLaidOutSplitView(selectedCategory: Int? = nil) -> NSSplitView {
        let window = makeSettingsWindow()
        if let selectedCategory {
            if let tableView = findTableView(in: window.contentView!) {
                tableView.selectRowIndexes(IndexSet(integer: selectedCategory), byExtendingSelection: false)
            }
        }
        window.contentView?.layoutSubtreeIfNeeded()
        guard let split = window.contentView?.subviews.compactMap({ $0 as? NSSplitView }).first else {
            fatalError("设置窗口内应存在 NSSplitView")
        }
        XCTAssertEqual(split.arrangedSubviews.count, 5, "应有「分类栏 + 通用 + 片段 + 贴图 + 录屏」五个子视图")
        return split
    }

    private func makeSettingsWindow() -> SettingsWindow {
        let defaults = UserDefaults(suiteName: "SettingsWindowLayoutTests")!
        defaults.removePersistentDomain(forName: "SettingsWindowLayoutTests")
        let registry = AppModuleRegistry(
            hotkeyManager: HotkeyManager(registrar: FakeHotkeyRegistrar()),
            configDefaults: defaults
        )
        return SettingsWindow(moduleRegistry: registry, onModuleStateChanged: { _, _ in })
    }

    func test_layout_pinPaneSitsRightOfSidebar() {
        let split = makeLaidOutSplitView(selectedCategory: 2)
        let sidebar = split.arrangedSubviews[0]
        let pane = split.arrangedSubviews[3]
        XCTAssertGreaterThanOrEqual(
            pane.frame.minX, sidebar.frame.maxX - 0.5,
            "贴图面板应在分类栏右侧，不得与分类栏重叠（实际 pane.minX=\(pane.frame.minX), sidebar.maxX=\(sidebar.frame.maxX)）"
        )
    }

    func test_layout_sidebarWidthIs180() {
        let split = makeLaidOutSplitView()
        let sidebar = split.arrangedSubviews[0]
        XCTAssertEqual(
            sidebar.frame.width, 180, accuracy: 0.5,
            "分类栏宽度应为 180pt（实际 \(sidebar.frame.width)）"
        )
    }

    func test_layout_paneContentFitsInsidePane() {
        let split = makeLaidOutSplitView()
        let pane = split.arrangedSubviews[3]
        guard let stack = pane.subviews.compactMap({ $0 as? NSStackView }).first else {
            return XCTFail("贴图面板内应有纵向内容栈")
        }
        XCTAssertLessThanOrEqual(
            stack.frame.maxX, pane.bounds.maxX + 0.5,
            "内容栈不得超出面板右边界"
        )
        XCTAssertLessThanOrEqual(
            stack.frame.maxY, pane.bounds.maxY + 0.5,
            "内容栈不得超出面板上边界"
        )
        // AppKit y 轴向上：纵向栈自上而下 = y 递减；相邻视图不得互相重叠
        let views = stack.arrangedSubviews
        for i in 1..<views.count {
            XCTAssertGreaterThanOrEqual(
                views[i - 1].frame.minY, views[i].frame.maxY - 0.5,
                "第 \(i - 1)、\(i) 个设置项在纵向堆叠中重叠"
            )
        }
    }

    // MARK: - 面板内部控件（用户可见的叠压回归）

    /// 收集面板内关键控件的「面板坐标系」frame：标题/说明标签 + 全部单选按钮。
    private func paneControls(in pane: NSView) -> [(name: String, frame: NSRect)] {
        var controls: [(name: String, frame: NSRect)] = []

        func walk(_ view: NSView) {
            for sub in view.subviews {
                if let button = sub as? NSButton {
                    controls.append((button.title, button.superview!.convert(button.frame, to: pane)))
                } else if let label = sub as? NSTextField, sub.superview is NSStackView {
                    controls.append((label.stringValue, label.superview!.convert(label.frame, to: pane)))
                }
                walk(sub)
            }
        }
        walk(pane)
        return controls
    }

    func test_layout_paneControlsDoNotOverlapEachOther() {
        let split = makeLaidOutSplitView()
        let pane = split.arrangedSubviews[3]
        let controls = paneControls(in: pane)

        XCTAssertGreaterThanOrEqual(
            controls.count, 4,
            "面板内应找到标题、说明与两个单选按钮（实际 \(controls.count) 个）"
        )

        for i in 0..<controls.count {
            for j in (i + 1)..<controls.count {
                let a = controls[i].frame.insetBy(dx: 1, dy: 1)
                let b = controls[j].frame.insetBy(dx: 1, dy: 1)
                XCTAssertFalse(
                    a.intersects(b),
                    "「\(controls[i].name)」与「\(controls[j].name)」在面板内重叠：\(controls[i].frame) vs \(controls[j].frame)"
                )
            }
        }
    }

    func test_layout_groupBoxContainsBothRadios() {
        let split = makeLaidOutSplitView()
        let pane = split.arrangedSubviews[3]

        guard let box = findGroupBox(in: pane) else {
            return XCTFail("面板内应存在「呼吸灯样式」分组框")
        }
        let radios = paneControls(in: pane).filter { $0.name == "顶部横条呼吸灯" || $0.name == "左上角圆点" }
        XCTAssertEqual(radios.count, 2, "应有两个呼吸灯样式单选按钮")

        for radio in radios {
            let frameInBox = box.convert(radio.frame, from: pane)
            XCTAssertTrue(
                box.bounds.insetBy(dx: 2, dy: 2).contains(frameInBox),
                "单选按钮「\(radio.name)」溢出分组框：box.bounds=\(box.bounds) radio=\(frameInBox)"
            )
        }
    }

    private func findGroupBox(in view: NSView) -> NSBox? {
        if let box = view as? NSBox { return box }
        for sub in view.subviews {
            if let found = findGroupBox(in: sub) { return found }
        }
        return nil
    }

    // MARK: - 侧栏空白点击（回归：右侧面板被误隐藏）

    private func findTableView(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for sub in view.subviews {
            if let found = findTableView(in: sub) { return found }
        }
        return nil
    }

    func test_sidebar_disallowEmptySelection() {
        let window = makeSettingsWindow()
        window.contentView?.layoutSubtreeIfNeeded()
        let tableView = findTableView(in: window.contentView!)
        XCTAssertNotNil(tableView, "设置窗口内应有分类列表")
        XCTAssertFalse(
            tableView!.allowsEmptySelection,
            "分类列表不允许空选择：点击列表空白处不应取消选中"
        )
    }

    func test_sidebar_deselectKeepsPaneVisible() {
        let window = makeSettingsWindow()
        window.contentView?.layoutSubtreeIfNeeded()
        let split = window.contentView!.subviews.compactMap({ $0 as? NSSplitView }).first!
        let pane = split.arrangedSubviews[0]
        guard let tableView = findTableView(in: window.contentView!) else {
            return XCTFail("设置窗口内应有分类列表")
        }

        // 模拟点击列表空白处导致的取消选择（selectedRow → -1）
        tableView.selectRowIndexes(IndexSet(), byExtendingSelection: false)

        XCTAssertFalse(pane.isHidden, "取消选择时右侧详情面板不得消失")
        XCTAssertEqual(tableView.selectedRow, 0, "取消选择后应恢复选中首项（通用）")
    }

    func test_sidebar_cellsKeepLabelsVisible() {
        let window = makeSettingsWindow()
        window.contentView?.layoutSubtreeIfNeeded()
        guard let tableView = findTableView(in: window.contentView!) else {
            return XCTFail("设置窗口内应有分类列表")
        }

        for row in 0..<tableView.numberOfRows {
            let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView
            XCTAssertNotNil(cell?.textField, "分类单元格 \(row) 的标签必须保持存活")
        }
    }
}
