// Tests for HotKey. Run: bash EarshotApp/Tests/run.sh
// The numbers are written out on purpose (Carbon modifier masks, Cocoa flag bits, virtual key codes),
// so the tests do not just restate the constants in HotKey.swift.
//   Carbon:  command 256, shift 512, option 2048, control 4096
//   Cocoa:   shift 1<<17, control 1<<18, option 1<<19, command 1<<20
//   Keys:    A 0, S 1, D 2, F 3, 1 18, Return 36, Tab 48, Space 49, Delete 51, Escape 53, F5 96, F1 122, Left 123
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

func suite() -> UserDefaults {
    let name = "HotKeyTests-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

@main struct HotKeyTests {
    static func main() {
        // MARK: default
        let d = HotKey.default
        checkTrue("default is Control+Option+Space", d.keyCode == 49 && d.modifiers == 4096 + 2048, "\(d)")
        checkTrue("the default is itself valid", d.isValid)
        checkTrue("the default reads ⌃⌥Space", d.display == "⌃⌥Space", d.display)

        // MARK: which combinations are allowed
        func hk(_ k: UInt32, _ m: UInt32) -> HotKey { HotKey(keyCode: k, modifiers: m) }
        checkTrue("Option+D is valid", hk(2, 2048).isValid)
        checkTrue("Control+Shift+S is valid", hk(1, 4096 + 512).isValid)
        checkTrue("Control+Option+Command+1 is valid", hk(18, 4096 + 2048 + 256).isValid)
        checkTrue("a bare function key is valid", hk(96, 0).isValid)
        checkTrue("a function key with Shift is valid", hk(122, 512).isValid)
        checkTrue("a letter with no modifier is not (it would steal typing)", !hk(0, 0).isValid)
        checkTrue("Shift+letter is not (it is a capital letter)", !hk(0, 512).isValid)
        checkTrue("Command+letter alone is not (it is every app's shortcut)", !hk(1, 256).isValid && !hk(8, 256 + 512).isValid)
        checkTrue("Command+Space is not (Spotlight)", !hk(49, 256).isValid)
        checkTrue("Control+Space is not (switches input source)", !hk(49, 4096).isValid)
        checkTrue("Control+Tab is not (switches tabs)", !hk(48, 4096).isValid)
        checkTrue("Escape is never a hotkey", !hk(53, 4096).isValid && !hk(53, 0).isValid)
        checkTrue("a Control+Option+Space variant with Shift is fine", hk(49, 4096 + 2048 + 512).isValid)

        // MARK: how it reads
        checkTrue("modifiers print in the macOS order ⌃⌥⇧⌘", hk(18, 256 + 512 + 2048 + 4096).display == "⌃⌥⇧⌘1", hk(18, 256 + 512 + 2048 + 4096).display)
        checkTrue("a letter prints as a capital", hk(2, 2048).display == "⌥D", hk(2, 2048).display)
        checkTrue("a function key prints by name", hk(96, 0).display == "F5" && hk(96, 4096).display == "⌃F5")
        checkTrue("an unknown key code still prints something", !hk(250, 4096).display.isEmpty)

        // MARK: Cocoa flags to Carbon modifiers
        let ctrl: UInt = 1 << 18, opt: UInt = 1 << 19, shift: UInt = 1 << 17, cmd: UInt = 1 << 20
        checkTrue("converts each flag", HotKey.carbonModifiers(fromCocoa: ctrl) == 4096
                  && HotKey.carbonModifiers(fromCocoa: opt) == 2048
                  && HotKey.carbonModifiers(fromCocoa: shift) == 512
                  && HotKey.carbonModifiers(fromCocoa: cmd) == 256)
        checkTrue("combines flags", HotKey.carbonModifiers(fromCocoa: ctrl | opt) == 6144)
        checkTrue("ignores caps lock, fn and numeric pad bits", HotKey.carbonModifiers(fromCocoa: (1 << 16) | (1 << 23) | (1 << 21) | ctrl) == 4096)
        checkTrue("no flags is no modifiers", HotKey.carbonModifiers(fromCocoa: 0) == 0)

        // MARK: saving and loading
        var u = suite()
        checkTrue("nothing saved loads the default", HotKey.load(from: u) == .default)
        let mine = hk(2, 2048)
        checkTrue("a valid key saves", mine.save(to: u))
        checkTrue("and loads back the same", HotKey.load(from: u) == mine)
        checkTrue("an invalid key is refused and not saved", !hk(0, 0).save(to: u) && HotKey.load(from: u) == mine)
        u = suite(); u.set("space", forKey: HotKey.keyCodeKey); u.set("lots", forKey: HotKey.modifiersKey)
        checkTrue("saved values of the wrong type fall back to the default", HotKey.load(from: u) == .default)
        u = suite(); u.set(0, forKey: HotKey.keyCodeKey); u.set(0, forKey: HotKey.modifiersKey)
        checkTrue("a saved key that is no longer valid falls back to the default", HotKey.load(from: u) == .default)
        u = suite(); u.set(-5, forKey: HotKey.keyCodeKey); u.set(2048, forKey: HotKey.modifiersKey)
        checkTrue("a negative saved key code falls back to the default", HotKey.load(from: u) == .default)
        u = suite(); _ = mine.save(to: u); HotKey.reset(in: u)
        checkTrue("reset brings back the default", HotKey.load(from: u) == .default)

        print("\(checks) checks, \(failures) failed")
        if checks < 30 { print("VACUOUS: only \(checks) checks ran, need 30"); exit(1) }
        exit(failures == 0 ? 0 : 1)
    }
}
