import XCTest

/// TDD: ⌥A 截图「按了没反应」的 Space 合成竞态规格。
/// 背景（2026-11-18 diag.log 实证）：11 次取消集中在三个密集重试段，每次
/// 按下后 2-3 秒内即 ESC——overlay 窗口创建成功（日志齐全）但用户看不见。
/// 根因：setActivationPolicy(.accessory) 异步生效，overlay 紧接着 orderFront
/// 时 policy 未被 WindowServer 接受，窗口按 .regular 应用的 fullScreenAuxiliary
/// 处理，在其他应用的全屏 Space 上不合成。本规格规定：①显示前确认 policy
/// 生效；②显示后程序化自检可见性并逐级自愈。
final class ScreenshotSpacePlanTests: XCTestCase {

    // MARK: - policy 生效确认轮询

    /// 轮询参数：总等待 ≤ 0.25s（截图呼出必须跟手，不能让用户察觉延迟）。
    func test_policyWait_totalBudgetWithin250ms() {
        let total = Double(ScreenshotSpacePlan.policyWaitMaxAttempts)
            * ScreenshotSpacePlan.policyWaitInterval
        XCTAssertLessThanOrEqual(total, 0.25,
            "policy 确认总等待不得超过 250ms，否则截图呼出明显迟滞")
    }

    func test_policyWait_positiveParameters() {
        XCTAssertGreaterThan(ScreenshotSpacePlan.policyWaitMaxAttempts, 0)
        XCTAssertGreaterThan(ScreenshotSpacePlan.policyWaitInterval, 0)
    }

    /// 显示后可见性自检延迟：给合成器留出时间，又不拖慢用户操作。
    func test_visibilityCheckDelay_saneWindow() {
        XCTAssertGreaterThanOrEqual(ScreenshotSpacePlan.visibilityCheckDelay, 0.3)
        XCTAssertLessThanOrEqual(ScreenshotSpacePlan.visibilityCheckDelay, 1.0)
    }

    // MARK: - 可见性自检逐级自愈（defense-in-depth）

    /// 可见 → 任何尝试轮次都保持现状。
    func test_visibility_visible_alwaysKeep() {
        for attempt in 0...3 {
            XCTAssertEqual(ScreenshotSpacePlan.visibilityAction(isVisible: true, attempt: attempt),
                           .keep, "attempt=\(attempt) 可见时不得干预")
        }
    }

    /// 首次不可见 → 重新 orderFront（最轻的修复）。
    func test_visibility_invisible_firstAttempt_reorderFront() {
        XCTAssertEqual(ScreenshotSpacePlan.visibilityAction(isVisible: false, attempt: 0),
                       .reorderFront)
    }

    /// 仍不可见 → 放弃 canJoinAllSpaces，改用跟随当前 Space 重建（全屏 Space 合成兜底）。
    func test_visibility_invisible_secondAttempt_rebuildMoveActiveSpace() {
        XCTAssertEqual(ScreenshotSpacePlan.visibilityAction(isVisible: false, attempt: 1),
                       .rebuildMoveActiveSpace)
    }

    /// 两级修复无效 → 结束会话并显式提示（用户至少得到「为什么不出现」的反馈，
    /// 而不是对着无反应的屏幕反复按 ⌥A）。
    func test_visibility_invisible_thirdAttempt_cancelWithNotice() {
        XCTAssertEqual(ScreenshotSpacePlan.visibilityAction(isVisible: false, attempt: 2),
                       .cancelWithNotice)
        XCTAssertEqual(ScreenshotSpacePlan.visibilityAction(isVisible: false, attempt: 5),
                       .cancelWithNotice, "后续轮次保持结束会话，不得无限重试")
    }

    /// 用户可见的提示文案：说明发生了什么 + 怎么办。
    func test_invisibleNoticeText() {
        let text = ScreenshotSpacePlan.invisibleNotice
        XCTAssertTrue(text.contains("截图"), "提示必须点名截图功能：\(text)")
        XCTAssertTrue(text.contains("重试"), "提示必须给出重试指引：\(text)")
    }
}
