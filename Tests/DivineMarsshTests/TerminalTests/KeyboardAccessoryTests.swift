import Testing
import Foundation
@testable import DivineMarssh

@Suite("KeyMapping Tests")
struct KeyMappingTests {

    @Test("Esc key returns escape byte")
    func escKey() {
        let bytes = KeyMapping.bytes(for: .esc)
        #expect(bytes == [0x1b])
    }

    @Test("Tab key returns tab byte")
    func tabKey() {
        let bytes = KeyMapping.bytes(for: .tab)
        #expect(bytes == [0x09])
    }

    @Test("Ctrl key returns nil (toggle, not a data key)")
    func ctrlKeyReturnsNil() {
        let bytes = KeyMapping.bytes(for: .ctrl)
        #expect(bytes == nil)
    }

    @Test("Arrow up returns correct escape sequence")
    func arrowUp() {
        let bytes = KeyMapping.bytes(for: .arrowUp)
        #expect(bytes == [0x1b, 0x5b, 0x41])
    }

    @Test("Arrow down returns correct escape sequence")
    func arrowDown() {
        let bytes = KeyMapping.bytes(for: .arrowDown)
        #expect(bytes == [0x1b, 0x5b, 0x42])
    }

    @Test("Arrow left returns correct escape sequence")
    func arrowLeft() {
        let bytes = KeyMapping.bytes(for: .arrowLeft)
        #expect(bytes == [0x1b, 0x5b, 0x44])
    }

    @Test("Arrow right returns correct escape sequence")
    func arrowRight() {
        let bytes = KeyMapping.bytes(for: .arrowRight)
        #expect(bytes == [0x1b, 0x5b, 0x43])
    }

    @Test("Pipe key returns pipe character")
    func pipeKey() {
        let bytes = KeyMapping.bytes(for: .pipe)
        #expect(bytes == Array("|".utf8))
    }

    @Test("Tilde key returns tilde character")
    func tildeKey() {
        let bytes = KeyMapping.bytes(for: .tilde)
        #expect(bytes == Array("~".utf8))
    }

    @Test("Slash key returns slash character")
    func slashKey() {
        let bytes = KeyMapping.bytes(for: .slash)
        #expect(bytes == Array("/".utf8))
    }

    @Test("All AccessoryKey cases have defined behavior")
    func allKeysCovered() {
        for key in AccessoryKey.allCases {
            if key == .ctrl {
                #expect(KeyMapping.bytes(for: key) == nil)
            } else {
                #expect(KeyMapping.bytes(for: key) != nil)
            }
        }
    }
}

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
