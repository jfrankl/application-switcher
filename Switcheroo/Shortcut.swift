import Foundation
import AppKit

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32      // Carbon/Quartz virtual key code
    var modifiers: NSEvent.ModifierFlags

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection([.command, .option, .control, .shift, .capsLock, .function])
    }

    // Custom Codable to handle NSEvent.ModifqierFlags (not Codable by default)
    private enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiersRaw
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.keyCode = try c.decode(UInt32.self, forKey: .keyCode)
        let raw = try c.decode(UInt.self, forKey: .modifiersRaw)
        self.modifiers = NSEvent.ModifierFlags(rawValue: raw)
        // Normalize to allowed set (same as in designated init)
        self.modifiers = self.modifiers.intersection([.command, .option, .control, .shift, .capsLock, .function])
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(keyCode, forKey: .keyCode)
        try c.encode(modifiers.rawValue, forKey: .modifiersRaw)
    }

    // Human-readable display, e.g. "⌘⇧K" or "F12" or "A"
    var displayString: String {
        var parts: [String] = []

        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option)  { parts.append("⌥") }
        if modifiers.contains(.shift)   { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        if modifiers.contains(.function){ parts.append("fn") }

        let key = Shortcut.keyString(for: keyCode) ?? "Key \(keyCode)"
        parts.append(key)
        return parts.joined()
    }

    // Default shortcut (your previous F12)
    static let `default` = Shortcut(keyCode: 111, modifiers: []) // F12

    // MARK: - Persistence

    private static let defaultsKey = "UserShortcut"

    static func load() -> Shortcut {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let s = try? JSONDecoder().decode(Shortcut.self, from: data) {
            return s
        }
        return .default
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Shortcut.defaultsKey)
        }
    }

    // MARK: - Key name helpers

    static func keyString(for keyCode: UInt32) -> String? {
        // Function keys
        if (122...126).contains(Int(keyCode)) || keyCode == 96 || keyCode == 97 || keyCode == 98 || keyCode == 100 || keyCode == 109 || keyCode == 111 {
            // Common Apple key codes: F1=122 ... F12=111
            if let fIdx = functionKeyIndex(from: keyCode) {
                return "F\(fIdx)"
            }
        }

        // Special keys
        switch keyCode {
        case 36: return "⏎" // Return
        case 48: return "⇥" // Tab
        case 49: return "␣" // Space
        case 51: return "⌫" // Delete
        case 53: return "⎋" // Escape
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            break
        }

        // Try to map letters/numbers by using TIS/UCKey translation (optional).
        // For simplicity, map common A-Z and 0-9 via US key codes.
        if let s = usKeyLabel(for: keyCode) {
            return s.uppercased()
        }
        return nil
    }

    private static func functionKeyIndex(from keyCode: UInt32) -> Int? {
        // Mapping common mac key codes to F-keys
        let map: [UInt32: Int] = [
            122: 1, 120: 2, 99: 3, 118: 4, 96: 5, 97: 6, 98: 7, 100: 8, 101: 9, 109: 10, 103: 11, 111: 12
        ]
        return map[keyCode]
    }

    private static func usKeyLabel(for keyCode: UInt32) -> String? {
        // Minimal mapping for letters/numbers on US layout
        let usMap: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
            20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
            29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
            39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
            50: "`"
        ]
        return usMap[keyCode]
    }
}
