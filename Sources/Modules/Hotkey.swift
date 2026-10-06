import Foundation

/// Carbon 修饰键位常量（值与 HIToolbox 的 cmdKey/shiftKey/optionKey/controlKey 一致）。
/// 自定义常量避免在测试目标里 import Carbon。
public enum ModifierKey {
    public static let command: UInt32 = 0x0100
    public static let shift: UInt32 = 0x0200
    public static let option: UInt32 = 0x0800
    public static let control: UInt32 = 0x1000
    /// 只保留四个主修饰键，丢弃 alphaLock/fnKey 等位。
    public static let mask: UInt32 = command | shift | option | control
}

/// 全局热键：Carbon 虚拟键码 + 规范化修饰键。Codable 便于持久化与快捷键设置。
public struct Hotkey: Codable, Equatable, Hashable {
    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32 = 0) {
        self.keyCode = keyCode
        self.modifiers = modifiers & ModifierKey.mask
    }

    /// F1 = kVK_F1(122)，截图默认快捷键。
    public static let f1 = Hotkey(keyCode: 122)

    /// F3 = kVK_F3(99)，贴图默认快捷键（截图选区完成后按 F3 贴图到桌面）。
    public static let f3 = Hotkey(keyCode: 99)

    /// F4 = kVK_F4(118)，录屏默认快捷键。
    public static let f4 = Hotkey(keyCode: 118)

    /// F5 = kVK_F5(96)，取色器默认快捷键。
    public static let f5 = Hotkey(keyCode: 96)

    /// F6 = kVK_F6(97)，恢复所有「鼠标穿透」贴图的快捷键。
    public static let f6 = Hotkey(keyCode: 97)

    /// 功能键显示名（F1/F2/F3...），用于菜单栏快捷键标注；非功能键返回 nil。
    /// 键码对照 HIToolbox Events.h：F4=118、F7=98、F8=100、F10=109、F11=103、F12=111。
    public var functionKeyLabel: String? {
        switch keyCode {
        case 122: return "F1"
        case 120: return "F2"
        case 99:  return "F3"
        case 118: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:  return nil
        }
    }
}
