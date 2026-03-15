import Testing
import Foundation
@testable import DivineMarssh

@Suite("Ctrl Modifier Tests")
struct CtrlModifierTests {

    @Test("Ctrl+a produces 0x01")
    func ctrlA() {
        #expect(KeyMapping.applyCtrl(to: 0x61) == 0x01)
    }

    @Test("Ctrl+z produces 0x1a")
    func ctrlZ() {
        #expect(KeyMapping.applyCtrl(to: 0x7a) == 0x1a)
    }

    @Test("Ctrl+c produces 0x03")
    func ctrlC() {
        #expect(KeyMapping.applyCtrl(to: 0x63) == 0x03)
    }

    @Test("Ctrl+uppercase C produces 0x03")
    func ctrlUpperC() {
        #expect(KeyMapping.applyCtrl(to: 0x43) == 0x03)
    }

    @Test("Ctrl+[ produces ESC (0x1b)")
    func ctrlBracket() {
        #expect(KeyMapping.applyCtrl(to: 0x5b) == 0x1b)
    }

    @Test("Ctrl+@ produces NUL (0x00)")
    func ctrlAt() {
        #expect(KeyMapping.applyCtrl(to: 0x40) == 0x00)
    }

    @Test("Ctrl+\\ produces 0x1c")
    func ctrlBackslash() {
        #expect(KeyMapping.applyCtrl(to: 0x5c) == 0x1c)
    }

    @Test("Ctrl+] produces 0x1d")
    func ctrlRightBracket() {
        #expect(KeyMapping.applyCtrl(to: 0x5d) == 0x1d)
    }

    @Test("Ctrl+^ produces 0x1e")
    func ctrlCaret() {
        #expect(KeyMapping.applyCtrl(to: 0x5e) == 0x1e)
    }

    @Test("Ctrl+_ produces 0x1f")
    func ctrlUnderscore() {
        #expect(KeyMapping.applyCtrl(to: 0x5f) == 0x1f)
    }

    @Test("Ctrl with non-mappable character returns unchanged")
    func ctrlNonMappable() {
        #expect(KeyMapping.applyCtrl(to: 0x31) == 0x31) // '1'
        #expect(KeyMapping.applyCtrl(to: 0x20) == 0x20) // space
    }

    @Test("All lowercase letters produce correct control codes")
    func allLowercaseLetters() {
        for i: UInt8 in 0x61...0x7a {
            let expected = i - 0x60
            #expect(KeyMapping.applyCtrl(to: i) == expected)
        }
    }
}

@Suite("Hardware Key Mapping Tests")
struct HardwareKeyMappingTests {

    @Test("Cmd+key sends Meta (ESC prefix)")
    func cmdAsMeta() {
        let result = KeyMapping.hardwareKeyBytes(
            keyCode: .keyboardA,
            modifierFlags: .command,
            characters: "a"
        )
        #expect(result == [0x1b] + Array("a".utf8))
    }

    @Test("Cmd+c sends ESC c")
    func cmdC() {
        let result = KeyMapping.hardwareKeyBytes(
            keyCode: .keyboardC,
            modifierFlags: .command,
            characters: "c"
        )
        #expect(result == [0x1b, 0x63])
    }

    @Test("No modifier returns nil (pass to SwiftTerm)")
    func noModifier() {
        let result = KeyMapping.hardwareKeyBytes(
            keyCode: .keyboardA,
            modifierFlags: [],
            characters: "a"
        )
        #expect(result == nil)
    }

    @Test("Alt-only returns nil (SwiftTerm handles Option)")
    func altOnly() {
        let result = KeyMapping.hardwareKeyBytes(
            keyCode: .keyboardA,
            modifierFlags: .alternate,
            characters: "a"
        )
        #expect(result == nil)
    }

    @Test("Ctrl-only returns nil (SwiftTerm handles Ctrl)")
    func ctrlOnly() {
        let result = KeyMapping.hardwareKeyBytes(
            keyCode: .keyboardA,
            modifierFlags: .control,
            characters: "a"
        )
        #expect(result == nil)
    }

    @Test("Cmd with nil characters returns nil")
    func cmdNilCharacters() {
        let result = KeyMapping.hardwareKeyBytes(
            keyCode: .keyboardA,
            modifierFlags: .command,
            characters: nil
        )
        #expect(result == nil)
    }

    @Test("Cmd with empty characters returns nil")
    func cmdEmptyCharacters() {
        let result = KeyMapping.hardwareKeyBytes(
            keyCode: .keyboardA,
            modifierFlags: .command,
            characters: ""
        )
        #expect(result == nil)
    }
}
