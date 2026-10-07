import XCTest

/// TDD: 面板显隐状态机——show/hide 交错打断时保证最终状态唯一。
/// 此前 hidePanel 凭 alphaValue == 0 判 orderOut、且 hide 进行中再 show 会
/// 互相踩踏（旧完成回调迟到时错乱收起/不收起）。状态机用代数(generation)
/// 让被打断一方的迟到完成回调失效。
final class TransferShelfPanelVisibilityTests: XCTestCase {

    func test_initialStateIsHidden() {
        let machine = TransferShelfPanelVisibilityMachine()
        XCTAssertEqual(machine.state, .hidden)
    }

    func test_showThenCompleteReachesShown() {
        var machine = TransferShelfPanelVisibilityMachine()
        let generation = machine.beginShow()
        XCTAssertEqual(machine.state, .showing)
        XCTAssertTrue(machine.endShow(generation: generation))
        XCTAssertEqual(machine.state, .shown)
    }

    func test_hideThenCompleteReachesHidden() {
        var machine = TransferShelfPanelVisibilityMachine()
        machine.beginShow()
        machine.endShow(generation: 1)
        let generation = machine.beginHideIfPossible()
        XCTAssertNotNil(generation)
        XCTAssertEqual(machine.state, .hiding)
        XCTAssertTrue(machine.endHide(generation: generation!))
        XCTAssertEqual(machine.state, .hidden)
    }

    func test_hideDuringShowInterruptsAndLateShowCompletionIsIgnored() {
        var machine = TransferShelfPanelVisibilityMachine()
        let showGeneration = machine.beginShow()
        let hideGeneration = machine.beginHideIfPossible()
        XCTAssertEqual(machine.state, .hiding, "hide 应能打断进行中的 show")

        // 迟到的 show 完成回调不得把状态改回 shown
        XCTAssertFalse(machine.endShow(generation: showGeneration))
        XCTAssertEqual(machine.state, .hiding)
        XCTAssertTrue(machine.endHide(generation: hideGeneration!))
        XCTAssertEqual(machine.state, .hidden, "打断后的最终状态必须唯一：hidden")
    }

    func test_showDuringHideInterruptsAndLateHideCompletionIsIgnored() {
        var machine = TransferShelfPanelVisibilityMachine()
        machine.beginShow()
        machine.endShow(generation: 1)
        let hideGeneration = machine.beginHideIfPossible()
        let showGeneration = machine.beginShow()
        XCTAssertEqual(machine.state, .showing, "show 应能打断进行中的 hide")

        // 迟到的 hide 完成回调不得 orderOut（状态机层表现为不得落到 hidden）
        XCTAssertFalse(machine.endHide(generation: hideGeneration!))
        XCTAssertEqual(machine.state, .showing)
        XCTAssertTrue(machine.endShow(generation: showGeneration))
        XCTAssertEqual(machine.state, .shown)
    }

    func test_secondHideWhileAlreadyHidingIsRejected() {
        var machine = TransferShelfPanelVisibilityMachine()
        machine.beginShow()
        machine.endShow(generation: 1)
        XCTAssertNotNil(machine.beginHideIfPossible())
        XCTAssertNil(machine.beginHideIfPossible(), "已在隐藏中，重复 hide 不应再起动画")
        XCTAssertEqual(machine.state, .hiding)
    }

    func test_hideFromHiddenIsRejected() {
        var machine = TransferShelfPanelVisibilityMachine()
        XCTAssertNil(machine.beginHideIfPossible(), "hidden 状态下无需隐藏")
        XCTAssertEqual(machine.state, .hidden)
    }

    func test_resetReturnsToHiddenAndInvalidatesPendingGeneration() {
        var machine = TransferShelfPanelVisibilityMachine()
        let showGeneration = machine.beginShow()
        machine.reset()
        XCTAssertEqual(machine.state, .hidden)
        XCTAssertFalse(machine.endShow(generation: showGeneration), "reset 后旧代完成回调必须失效")
    }

    func test_showCompletionFromOlderCycleIsIgnored() {
        var machine = TransferShelfPanelVisibilityMachine()
        let firstShow = machine.beginShow()
        let secondShow = machine.beginShow()
        XCTAssertFalse(machine.endShow(generation: firstShow))
        XCTAssertTrue(machine.endShow(generation: secondShow))
        XCTAssertEqual(machine.state, .shown)
    }
}
