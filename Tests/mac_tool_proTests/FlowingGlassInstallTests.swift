import XCTest
import AppKit

/// TDD: 统一流光注入点 —— 全部面板/窗口/子面板共用一个入口，杜绝各处自拼
/// （此前：工具条手动插、延时/画布/调色板子面板用静态底色、中转站渐变被误删）。
final class FlowingGlassInstallTests: XCTestCase {

    func test_install_addsGlassAtBottom() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 80))
        let label = NSTextField(labelWithString: "content")
        view.addSubview(label)

        UITheme.installFlowingGlass(in: view)

        XCTAssertTrue(view.subviews.contains(where: { $0 is FlowingGlassView }),
                      "必须注入流光玻璃")
        XCTAssertEqual(view.subviews.first is FlowingGlassView, true, "玻璃必须在最底层（内容之下）")
    }

    func test_install_isIdempotent() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 80))
        UITheme.installFlowingGlass(in: view)
        UITheme.installFlowingGlass(in: view)
        UITheme.installFlowingGlass(in: view)

        let glassCount = view.subviews.filter { $0 is FlowingGlassView }.count
        XCTAssertEqual(glassCount, 1, "重复注入必须幂等")
    }

    func test_installedGlass_tracksBounds() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 80))
        UITheme.installFlowingGlass(in: view)
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 300)

        let glass = try! XCTUnwrap(view.subviews.first { $0 is FlowingGlassView })
        XCTAssertEqual(glass.frame.width, 400, "玻璃必须跟随宿主尺寸（autoresizing）")
        XCTAssertEqual(glass.frame.height, 300)
    }
}
