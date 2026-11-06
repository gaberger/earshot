import Foundation

/// The global shortcut that starts and stops dictation: one virtual key code and a set of modifiers.
///
/// It is a pure value type with no Carbon or AppKit in it, so the rules can be tested without a window
/// server. Modifiers use the Carbon masks (what the hot key registration API wants); `carbonModifiers`
/// converts from the Cocoa flag bits a key-recording field sees.
///
/// It fails toward "do not steal typing". A shortcut that fires while the user writes an email is
/// worse than one that cannot be chosen, so `isValid` insists on Control or Option (or a function key),
/// and refuses the few combinations macOS already owns. A stored value that no longer passes falls back
/// to the default rather than registering something surprising.
struct HotKey: Equatable {
    var keyCode: UInt32
    /// Carbon modifier mask: command 256, shift 512, option 2048, control 4096.
    var modifiers: UInt32

    private static let command: UInt32 = 256
    private static let shift: UInt32 = 512
    private static let option: UInt32 = 2048
    private static let control: UInt32 = 4096
    private static let escape: UInt32 = 53

    /// Control+Option+Space.
    static let `default` = HotKey(keyCode: 49, modifiers: control | option)

    static let keyCodeKey = "dictationKeyCode"
    static let modifiersKey = "dictationModifiers"

    // MARK: validity

    /// Virtual key codes of F1...F20 (ANSI keyboard).
    private static let functionKeys: [UInt32: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    /// Whether this combination may be used as the dictation shortcut.
    var isValid: Bool {
        let known = HotKey.command | HotKey.shift | HotKey.option | HotKey.control
        if modifiers & ~known != 0 { return false }
        if keyCode == HotKey.escape { return false }
        if HotKey.functionKeys[keyCode] != nil { return true }
        let hasControl = modifiers & HotKey.control != 0
        let hasOption = modifiers & HotKey.option != 0
        if !hasControl && !hasOption { return false }
        // Control+Space and Control+Tab belong to macOS (input source, tab switching).
        if (keyCode == 49 || keyCode == 48) && hasControl && !hasOption { return false }
        return true
    }

    // MARK: display

    private static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    /// The shortcut as a person reads it: modifiers in macOS order (⌃⌥⇧⌘), then the key.
    var display: String {
        var text = ""
        if modifiers & HotKey.control != 0 { text += "⌃" }
        if modifiers & HotKey.option != 0 { text += "⌥" }
        if modifiers & HotKey.shift != 0 { text += "⇧" }
        if modifiers & HotKey.command != 0 { text += "⌘" }
        let name = HotKey.keyNames[keyCode] ?? HotKey.functionKeys[keyCode] ?? "Key \(keyCode)"
        return text + name
    }

    // MARK: Cocoa flags

    /// Converts Cocoa modifier flag bits (shift 1<<17, control 1<<18, option 1<<19, command 1<<20)
    /// to a Carbon mask. Every other bit (caps lock, fn, numeric pad) is ignored.
    static func carbonModifiers(fromCocoa raw: UInt) -> UInt32 {
        var mask: UInt32 = 0
        if raw & (1 << 17) != 0 { mask |= shift }
        if raw & (1 << 18) != 0 { mask |= control }
        if raw & (1 << 19) != 0 { mask |= option }
        if raw & (1 << 20) != 0 { mask |= command }
        return mask
    }

    // MARK: persistence

    /// The saved shortcut, or the default when nothing is saved, the stored values are not
    /// non-negative integers, or the combination is no longer valid.
    static func load(from defaults: UserDefaults = .standard) -> HotKey {
        guard let code = defaults.object(forKey: keyCodeKey) as? Int,
              let mods = defaults.object(forKey: modifiersKey) as? Int,
              code >= 0, mods >= 0,
              code <= Int(UInt32.max), mods <= Int(UInt32.max)
        else { return .default }
        let key = HotKey(keyCode: UInt32(code), modifiers: UInt32(mods))
        return key.isValid ? key : .default
    }

    /// Saves this shortcut. Returns false, writing nothing, when it is not valid.
    @discardableResult
    func save(to defaults: UserDefaults = .standard) -> Bool {
        guard isValid else { return false }
        defaults.set(Int(keyCode), forKey: HotKey.keyCodeKey)
        defaults.set(Int(modifiers), forKey: HotKey.modifiersKey)
        return true
    }

    /// Forgets the saved shortcut, so `load` returns the default.
    static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: keyCodeKey)
        defaults.removeObject(forKey: modifiersKey)
    }
}
