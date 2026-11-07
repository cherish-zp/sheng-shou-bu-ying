import XCTest

/// TDD: 浮引快捷键面板纯逻辑 —— 浮引键盘布局行序、键位字符→键码对照、
/// panelSummon 面板呼出键（默认 F1 / 旧 JSON 兼容 / 显式清除保持 nil）、
/// 应用启动绑定存储（add 覆盖 / remove / 键码查询 / 与功能绑定冲突检测）、
/// 面板键位合并视图（功能优先 → 应用 → 空键位）。
final class HotkeyPanelTests: XCTestCase {

    // MARK: - 浮引键盘布局

    func test_layout_fourRowsInFloatPanelOrder() {
        XCTAssertEqual(HotkeyPanelLayout.rows.count, 4, "浮引键盘 = 4 行")
        XCTAssertEqual(HotkeyPanelLayout.rows[0],
                       ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="],
                       "第一行 = 数字行")
        XCTAssertEqual(HotkeyPanelLayout.rows[1],
                       ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
                       "第二行 = Q 行")
        XCTAssertEqual(HotkeyPanelLayout.rows[2],
                       ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
                       "第三行 = A 行")
        XCTAssertEqual(HotkeyPanelLayout.rows[3],
                       ["Z", "X", "C", "V", "B", "N", "M"],
                       "第四行 = Z 行")
    }

    // MARK: - 键位字符 → 键码对照

    func test_keyCodes_spotCheck() {
        // 数字行（HIToolbox kVK_ANSI_*）
        XCTAssertEqual(HotkeyPanelKeyCodes.keyCode(for: "1"), 18)
        XCTAssertEqual(HotkeyPanelKeyCodes.keyCode(for: "5"), 23)
        XCTAssertEqual(HotkeyPanelKeyCodes.keyCode(for: "6"), 22)
        XCTAssertEqual(HotkeyPanelKeyCodes.keyCode(for: "0"), 29)
        XCTAssertEqual(HotkeyPanelKeyCodes.keyCode(for: "-"), 27)
        XCTAssertEqual(HotkeyPanelKeyCodes.keyCode(for: "="), 24)
        // 字母行
        XCTAssertEqual(HotkeyPanelKeyCodes.keyCode(for: "Q"), 12)
        XCTAssertEqual(HotkeyPanelKeyCodes.keyCode(for: "P"), 35)
        XCTAssertEqual(HotkeyPanelKeyCodes.keyCode(for: "A"), 0)
        XCTAssertEqual(HotkeyPanelKeyCodes.keyCode(for: "L"), 37)
        XCTAssertEqual(HotkeyPanelKeyCodes.keyCode(for: "Z"), 6)
        XCTAssertEqual(HotkeyPanelKeyCodes.keyCode(for: "X"), 7)
        XCTAssertEqual(HotkeyPanelKeyCodes.keyCode(for: "C"), 8)
        XCTAssertEqual(HotkeyPanelKeyCodes.keyCode(for: "M"), 46)
    }

    func test_keyCodes_coverEveryLayoutKey() {
        for row in HotkeyPanelLayout.rows {
            for key in row {
                XCTAssertNotNil(HotkeyPanelKeyCodes.keyCode(for: key), "布局键 \(key) 必须有键码对照")
            }
        }
    }

    // MARK: - panelSummon（面板呼出键）

    func test_panelSummon_defaultIsF1NoModifier() {
        XCTAssertEqual(HotkeyPreferences.withDefaults().panelSummon, Hotkey(keyCode: 122),
                       "默认 F1、无修饰键")
    }

    func test_panelSummon_legacyJSONWithoutField_fallsBackToDefaultF1() throws {
        // 旧版本 JSON：只有 primaryModifier + bindings，无 panelSummon 字段
        let legacy = """
        {"primaryModifier":"option","bindings":{"screenshot":{"keyCode":0,"usesShift":false}}}
        """
        let prefs = try JSONDecoder().decode(HotkeyPreferences.self, from: Data(legacy.utf8))
        XCTAssertEqual(prefs.panelSummon, Hotkey(keyCode: 122), "旧 JSON 缺字段应回落 F1 默认")
    }

    func test_panelSummon_explicitNullAfterClear_staysNil() throws {
        // 用户在设置页清除呼出键 → 显式 null，不得回落 F1
        var prefs = HotkeyPreferences.withDefaults()
        prefs.panelSummon = nil
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(HotkeyPreferences.self, from: data)
        XCTAssertNil(decoded.panelSummon, "显式清除（null）应保持 nil")
    }

    // MARK: - 应用启动绑定

    private func makeApp(_ bundleID: String, _ name: String, _ keyCode: UInt32,
                         shift: Bool = false) -> AppLaunchBinding {
        AppLaunchBinding(bundleID: bundleID, name: name, keyCode: keyCode, usesShift: shift)
    }

    func test_appStore_addOverridesSameKeyCode() {
        var store = AppLaunchBindingStore()
        store.add(makeApp("com.apple.safari", "Safari", 12))
        store.add(makeApp("com.apple.mail", "Mail", 12))
        XCTAssertEqual(store.bindings.count, 1, "同键码只保留一条")
        XCTAssertEqual(store.bindings.first?.bundleID, "com.apple.mail", "后写覆盖先写")
    }

    func test_appStore_addDifferentKeyCodesKeepsBoth() {
        var store = AppLaunchBindingStore()
        store.add(makeApp("com.apple.safari", "Safari", 12))
        store.add(makeApp("com.apple.mail", "Mail", 13))
        XCTAssertEqual(store.bindings.count, 2)
    }

    func test_appStore_removeByBundleID() {
        var store = AppLaunchBindingStore()
        store.add(makeApp("com.apple.safari", "Safari", 12))
        store.add(makeApp("com.apple.mail", "Mail", 13))
        store.remove(bundleID: "com.apple.safari")
        XCTAssertEqual(store.bindings.map(\.bundleID), ["com.apple.mail"])
    }

    func test_appStore_bindingForKeyCode() {
        var store = AppLaunchBindingStore()
        store.add(makeApp("com.apple.safari", "Safari", 12))
        XCTAssertEqual(store.binding(forKeyCode: 12)?.bundleID, "com.apple.safari")
        XCTAssertNil(store.binding(forKeyCode: 13))
    }

    func test_appStore_conflictsWithFunctionBindings_sameKeySameShift() {
        let prefs = HotkeyPreferences.withDefaults()   // 截图 = A(0) 无 shift、剪贴板 = X(7)
        // 直接构造（add 同键码会覆盖，无法并置多条同键码样本）
        let store = AppLaunchBindingStore(bindings: [
            makeApp("com.conflict", "冲突", 0),                     // 同键码同 shift → 冲突
            makeApp("com.shiftDiff", "shift 不同", 0, shift: true),  // 同键码异 shift → 不冲突
            makeApp("com.free", "空闲键", 3),                       // F 未绑 → 不冲突
        ])
        XCTAssertEqual(store.conflicts(with: prefs), [makeApp("com.conflict", "冲突", 0)],
                       "冲突 = 与功能绑定 HotkeyBinding(keyCode:usesShift:) 等价")
    }

    func test_appStore_persistence_roundTripWithInjectedDefaults() {
        let suite = "HotkeyPanelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var store = AppLaunchBindingStore()
        store.add(makeApp("com.apple.safari", "Safari", 12))
        store.save(defaults: defaults)

        XCTAssertEqual(AppLaunchBindingStore.load(defaults: defaults), store)
        XCTAssertEqual(AppLaunchBindingStore.load(defaults: defaults).bindings.first?.name, "Safari")
    }

    func test_appStore_load_corruptedDataFallsBackToEmpty() {
        let suite = "HotkeyPanelTests.Corrupt.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not-json".utf8), forKey: "appLaunchBindings")
        XCTAssertEqual(AppLaunchBindingStore.load(defaults: defaults), AppLaunchBindingStore())
    }

    // MARK: - 功能 SF Symbol 映射

    func test_symbolMapping_allCatalogIdsHaveSymbols() {
        for entry in HotkeyPreferences.catalog {
            XCTAssertNotNil(HotkeyPanelContent.symbolName(for: entry.id),
                            "功能 \(entry.id) 缺 SF Symbol 映射")
        }
        XCTAssertEqual(HotkeyPanelContent.symbolName(for: "hotkeyPanel"), "keyboard")
        XCTAssertEqual(HotkeyPanelContent.symbolName(for: "screenshot"), "camera.viewfinder")
    }

    // MARK: - 面板键位合并视图

    func test_cell_functionBound_showsFunctionWithCatalogTitleAndSymbol() {
        let prefs = HotkeyPreferences.withDefaults()   // 截图绑在 A(0)
        let cell = HotkeyPanelContent.cell(for: "A", prefs: prefs, appStore: AppLaunchBindingStore())
        XCTAssertEqual(cell, .function(id: "screenshot", title: "截图", symbolName: "camera.viewfinder"))
    }

    func test_cell_appBound_showsApp() {
        var store = AppLaunchBindingStore()
        store.add(makeApp("com.apple.safari", "Safari", 12))
        let cell = HotkeyPanelContent.cell(for: "Q", prefs: .withDefaults(), appStore: store)
        XCTAssertEqual(cell, .app(bundleID: "com.apple.safari", name: "Safari"))
    }

    func test_cell_unbound_showsEmptyWithKeyLabel() {
        let cell = HotkeyPanelContent.cell(for: "W", prefs: .withDefaults(), appStore: AppLaunchBindingStore())
        XCTAssertEqual(cell, .empty(keyLabel: "W"))
    }

    func test_cell_functionTakesPriorityOverApp() {
        var store = AppLaunchBindingStore()
        store.add(makeApp("com.apple.safari", "Safari", 7))   // X 键位被剪贴板历史占用
        let cell = HotkeyPanelContent.cell(for: "X", prefs: .withDefaults(), appStore: store)
        XCTAssertEqual(cell, .function(id: "clipboardHistory", title: "剪贴板历史", symbolName: "clipboard"))
    }

    func test_cell_functionWithShiftStillMatchesByKeyCode() {
        // 面板键帽无 shift 语义：同键码的功能绑定（⌥⇧A）也点亮键帽
        var prefs = HotkeyPreferences.withDefaults()
        prefs.bindings["screenshot"] = HotkeyBinding(keyCode: 0, usesShift: true)
        let cell = HotkeyPanelContent.cell(for: "A", prefs: prefs, appStore: AppLaunchBindingStore())
        XCTAssertEqual(cell, .function(id: "screenshot", title: "截图", symbolName: "camera.viewfinder"))
    }

    func test_cell_lowercaseInputMatchesUppercaseLayout() {
        let prefs = HotkeyPreferences.withDefaults()
        let cell = HotkeyPanelContent.cell(for: "a", prefs: prefs, appStore: AppLaunchBindingStore())
        XCTAssertEqual(cell, .function(id: "screenshot", title: "截图", symbolName: "camera.viewfinder"),
                       "键位字符大小写不敏感")
    }
}

// MARK: - 绑定菜单可选功能（用户定案：未绑键位只列完全未绑定的功能）

extension HotkeyPanelTests {

    func test_bindableFunctions_defaultPrefsIsEmpty() {
        // 默认 13 个功能全部有键位 → 未绑键位的菜单不应列出任何功能
        XCTAssertTrue(HotkeyPanelContent.bindableFunctions(prefs: .withDefaults()).isEmpty)
    }

    func test_bindableFunctions_listsOnlyUnbound() {
        var prefs = HotkeyPreferences.withDefaults()
        prefs.bindings["screenshot"] = nil          // 清空截图绑定
        prefs.bindings["translate"] = nil
        let bindable = HotkeyPanelContent.bindableFunctions(prefs: prefs)
        XCTAssertEqual(bindable.map(\.id).sorted(), ["screenshot", "translate"],
                       "只列出完全没有键位的功能")
    }

    func test_bindableFunctions_rebindingSameKeyDoesNotReappear() {
        // 功能绑在别的键位上也不得出现在未绑键菜单（换键走右键「更换绑定」）
        var prefs = HotkeyPreferences.withDefaults()
        prefs.bindings["screenshot"] = HotkeyBinding(keyCode: 99)   // 挪到别的键
        XCTAssertFalse(HotkeyPanelContent.bindableFunctions(prefs: prefs).contains { $0.id == "screenshot" })
    }
}

// MARK: - 快速片段面板显示序（用户报告「只剩一个」回归网）

extension HotkeyPanelTests {

    private func makeSnippets(_ keys: [String]) -> [Snippet] {
        keys.map { Snippet(key: $0, content: "内容-\($0)") }
    }

    /// 空 query：全量按 key 排序（不得只剩部分条目）。
    func test_displayed_emptyQueryShowsAll() {
        let all = makeSnippets(["ftp下载", "车联网", "nacos密码", "FTP解压密码"])
        let displayed = HotkeyPanelContent.displayed(snippets: all, query: "")
        XCTAssertEqual(displayed.count, 4, "空搜索必须显示全部片段")
    }

    /// 非空 query：只显示匹配项（面板残留搜索词时用户看到的就是这个）。
    func test_displayed_queryFilters() {
        let all = makeSnippets(["ftp下载", "车联网", "nacos密码", "FTP解压密码"])
        let displayed = HotkeyPanelContent.displayed(snippets: all, query: "ftp")
        XCTAssertEqual(displayed.count, 2, "大小写不敏感匹配 ftp/FTP")
    }

    /// 排序稳定性：key 字典序（与匹配无关）。
    func test_displayed_sortedByKey() {
        let all = makeSnippets(["c片", "a片", "b片"])
        let displayed = HotkeyPanelContent.displayed(snippets: all, query: "")
        XCTAssertEqual(displayed.map(\.key), ["a片", "b片", "c片"])
    }
}

extension HotkeyPanelTests {

    /// 面板宽度随片段数自适应：少量片段收在空态宽 420，多了 clamp 到屏宽-48。
    func test_snippetPanelWidth_adapts() {
        XCTAssertEqual(HotkeyPanelContent.snippetPanelWidth(itemCount: 0, screenWidth: 1728), 420, accuracy: 0.1)
        // 2 条内容宽 460 > 下限 420 → 内容宽
        XCTAssertEqual(HotkeyPanelContent.snippetPanelWidth(itemCount: 2, screenWidth: 1728), 460, accuracy: 0.1)
        // 5 张卡：24+5×200+4×12+24 = 1108 > 420 → 内容宽
        XCTAssertEqual(HotkeyPanelContent.snippetPanelWidth(itemCount: 5, screenWidth: 1728),
                       5 * 200 + 4 * 12 + 48, accuracy: 0.1)
        // 20 张超屏：clamp 到屏宽-48
        XCTAssertEqual(HotkeyPanelContent.snippetPanelWidth(itemCount: 20, screenWidth: 1728),
                       1728 - 48, accuracy: 0.1)
    }
}

// MARK: - 快速片段 key 按钮网格（用户定案：多行换行、面板高随行数）

extension HotkeyPanelTests {

    /// 每行容量：1512 屏可用 1512-48=1464；(1464+8)/(140+8)=9.97 → 9。
    func test_snippetGrid_perRowCapacity() {
        XCTAssertEqual(HotkeyPanelContent.snippetGridPerRow(screenWidth: 1512), 9)
        XCTAssertEqual(HotkeyPanelContent.snippetGridPerRow(screenWidth: 500), 3,
                       "500-48=452；(452+8)/148=3.1 → 3")
        XCTAssertEqual(HotkeyPanelContent.snippetGridPerRow(screenWidth: 200), 1, "极窄保底 1")
    }

    func test_snippetGrid_rows() {
        let w = CGFloat(1512)
        XCTAssertEqual(HotkeyPanelContent.snippetGridRows(itemCount: 0, screenWidth: w), 0)
        XCTAssertEqual(HotkeyPanelContent.snippetGridRows(itemCount: 9, screenWidth: w), 1)
        XCTAssertEqual(HotkeyPanelContent.snippetGridRows(itemCount: 10, screenWidth: w), 2,
                       "10 张换第二行")
        XCTAssertEqual(HotkeyPanelContent.snippetGridRows(itemCount: 20, screenWidth: w), 3)
    }

    /// 面板高 = 顶栏 40 + 行数×44 + 行距×(rows-1) + 底 padding 12；空态 = 顶栏+空态文案带。
    func test_snippetPanelHeight_byRows() {
        let w = CGFloat(1512)
        XCTAssertEqual(HotkeyPanelContent.snippetPanelHeight(itemCount: 0, screenWidth: w),
                       40 + 40 + 12, accuracy: 0.1, "空态：顶栏 + 引导文案带 + padding")
        XCTAssertEqual(HotkeyPanelContent.snippetPanelHeight(itemCount: 9, screenWidth: w),
                       40 + 44 + 12, accuracy: 0.1)
        XCTAssertEqual(HotkeyPanelContent.snippetPanelHeight(itemCount: 10, screenWidth: w),
                       40 + 44 * 2 + 8 + 12, accuracy: 0.1)
    }
}
