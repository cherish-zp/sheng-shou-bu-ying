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

    /// F2 = kVK_F2(120)，中转站面板手动呼出默认快捷键。
    public static let f2 = Hotkey(keyCode: 120)

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

    /// 字母/数字键码 → 显示字符（快捷键组合键标注用）。
    /// 键码对照 HIToolbox kVK_ANSI_*：A=0 起、S=1、D=2、F=3、H=4、G=5、Z=6、X=7、C=8、
    /// V=9、B=11、Q=12、W=13、E=14、R=15、Y=16、T=17、数字 1=18…0=29、O=31、U=32、
    /// I=34、P=35、L=37、J=38、K=40、N=45、M=46。
    public static func letterLabel(for keyCode: UInt32) -> String? {
        let letters: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 28: "8", 29: "0", 31: "O",
            32: "U", 34: "I", 35: "P", 36: "⏎", 37: "L", 38: "J", 39: "'",
            40: "K", 41: ";", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
            49: "␣", 51: "⌫", 53: "⎋",
        ]
        return letters[keyCode]
    }
}
