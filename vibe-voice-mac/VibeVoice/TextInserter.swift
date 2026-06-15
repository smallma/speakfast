import AppKit
import CoreGraphics
import ApplicationServices

// 把辨識文字送進最前景的 app。
//
// 預設用「直接鍵入」(.directType)：透過 CGEvent 的 Unicode 注入逐段打字，
// 全程不碰系統剪貼簿 —— 你口述的敏感內容（密碼 / token / 私訊）不會留進
// 剪貼簿歷史，也不會蓋掉你原本複製的東西。這是相對「剪貼簿貼上」的安全升級。
//
// 後備 .clipboardPaste：少數 app 對合成 Unicode 鍵入支援不佳時可改用。
// 它會備份並還原你原本的剪貼簿，把暴露窗口降到最低。
//
// 需要權限：Accessibility（CGEvent 才送得出按鍵）。
enum InsertMode {
    case directType
    case clipboardPaste
}

enum TextInserter {
    static func insert(_ text: String, mode: InsertMode, pressEnter: Bool) {
        // 只記長度，絕不記內容（可能是密碼 / 私訊）。
        let modeName = (mode == .directType) ? "directType" : "clipboardPaste"
        NSLog("[VibeVoice][Insert] insert called · len=\(text.count) mode=\(modeName) pressEnter=\(pressEnter) AXTrusted=\(AXIsProcessTrusted())")
        // 鍵盤注入要序列化、且有微小間隔，放背景跑避免卡住 UI / main runloop。
        DispatchQueue.global(qos: .userInitiated).async {
            switch mode {
            case .directType:
                directType(text)
            case .clipboardPaste:
                clipboardPaste(text)
            }
            if pressEnter {
                usleep(120_000)
                tapKey(virtualKey: 36, flags: [])   // 36 = Return
            }
        }
    }

    // MARK: - 直接鍵入（不碰剪貼簿）

    private static func directType(_ text: String) {
        let src = CGEventSource(stateID: .combinedSessionState)
        // 單一事件能附帶的 UTF-16 長度有限制，分段送（每段 ~18 個單位最穩）。
        let units = Array(text.utf16)
        let chunkSize = 18
        var i = 0
        while i < units.count {
            let end = min(i + chunkSize, units.count)
            var buf = Array(units[i..<end])
            if let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: &buf)
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
                up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: &buf)
                up.post(tap: .cghidEventTap)
            }
            usleep(4_000) // 4ms，讓前景 app 來得及消化
            i = end
        }
    }

    // MARK: - 剪貼簿後備（備份→貼上→還原，最小暴露）

    private static func clipboardPaste(_ text: String) {
        let pb = NSPasteboard.general
        let previous = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)
        usleep(50_000)
        tapKey(virtualKey: 9, flags: .maskCommand)   // 9 = 'v'
        usleep(350_000)
        // 還原使用者原本剪貼簿，並清掉我們寫進去的敏感內容
        pb.clearContents()
        if let previous { pb.setString(previous, forType: .string) }
    }

    // MARK: - 單鍵

    private static func tapKey(virtualKey: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
