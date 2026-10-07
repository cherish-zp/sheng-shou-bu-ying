import Foundation

/// 面板显隐状态：hidden → showing → shown → hiding → hidden。
public enum TransferShelfPanelVisibility: Equatable {
    case hidden
    case showing
    case shown
    case hiding
}

/// 面板显隐状态机：show/hide 交错打断时保证最终状态唯一。
///
/// 动画本身仍由控制器用 NSAnimationContext 驱动；本类型裁决「能否起动画」、
/// 「完成后落到哪个状态」。核心是代数（generation）计数：每次 begin 都自增，
/// 被打断一方的迟到完成回调（generation 不匹配）直接失效——
/// 此前 hidePanel 凭 alphaValue == 0 判 orderOut、show/hide 互相踩踏。
public struct TransferShelfPanelVisibilityMachine {
    public private(set) var state: TransferShelfPanelVisibility = .hidden
    private var generation = 0

    public init() {}

    /// 开始显示（总是允许，可打断进行中的隐藏/再显示）。
    /// 返回本次动画的代数标识，完成回调须带回校验。
    @discardableResult
    public mutating func beginShow() -> Int {
        generation += 1
        state = .showing
        return generation
    }

    /// 显示动画完成。仅当代数仍是当前（未被 hide 打断）时生效，返回是否生效。
    @discardableResult
    public mutating func endShow(generation gen: Int) -> Bool {
        guard gen == generation, state == .showing else { return false }
        state = .shown
        return true
    }

    /// 开始隐藏；仅从 shown/showing 允许（.hiding 已在隐藏、.hidden 无需重复），
    /// 拒绝时返回 nil（调用方不应起动画）。
    public mutating func beginHideIfPossible() -> Int? {
        guard state == .shown || state == .showing else { return nil }
        generation += 1
        state = .hiding
        return generation
    }

    /// 隐藏动画完成。仅当代数仍是当前（未被 show 打断）时生效；
    /// 生效时调用方才 orderOut（避免把重新显示的面板收掉）。
    @discardableResult
    public mutating func endHide(generation gen: Int) -> Bool {
        guard gen == generation, state == .hiding else { return false }
        state = .hidden
        return true
    }

    /// 复位到 hidden（模块停用等场景），并使所有在途完成回调失效。
    public mutating func reset() {
        generation += 1
        state = .hidden
    }
}
