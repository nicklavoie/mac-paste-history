import Carbon
import AppKit
import Foundation

struct HotKey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let defaultShortcut = HotKey(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("Control") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("Option") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("Shift") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("Command") }
        parts.append(Self.displayName(for: keyCode))
        return parts.joined(separator: " + ")
    }

    static func fromNSEvent(keyCode: UInt16, modifierFlags: UInt) -> HotKey {
        var carbonModifiers: UInt32 = 0
        if modifierFlags & UInt(NSEvent.ModifierFlags.command.rawValue) != 0 {
            carbonModifiers |= UInt32(cmdKey)
        }
        if modifierFlags & UInt(NSEvent.ModifierFlags.shift.rawValue) != 0 {
            carbonModifiers |= UInt32(shiftKey)
        }
        if modifierFlags & UInt(NSEvent.ModifierFlags.option.rawValue) != 0 {
            carbonModifiers |= UInt32(optionKey)
        }
        if modifierFlags & UInt(NSEvent.ModifierFlags.control.rawValue) != 0 {
            carbonModifiers |= UInt32(controlKey)
        }
        return HotKey(keyCode: UInt32(keyCode), modifiers: carbonModifiers)
    }

    private static func displayName(for keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z", UInt32(kVK_Space): "Space",
            UInt32(kVK_Return): "Return", UInt32(kVK_Escape): "Escape", UInt32(kVK_Tab): "Tab"
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }
}

final class HotKeyManager {
    static let shared = HotKeyManager()

    var action: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private init() {
        installEventHandler()
    }

    func register(_ hotKey: HotKey) {
        unregister()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: fourCharacterCode("PHSV"), id: 1)
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.action?()
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }
}

private func fourCharacterCode(_ string: String) -> OSType {
    var result: OSType = 0
    for scalar in string.unicodeScalars.prefix(4) {
        result = (result << 8) + OSType(scalar.value)
    }
    return result
}
