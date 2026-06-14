import AppKit

// 把文字貼到「最前景的 app」：寫進剪貼簿 → 模擬 Cmd+V。
// 需要權限：System Settings → Privacy & Security → Accessibility 勾選本 app，
// 否則 CGEvent 送出的按鍵會被系統忽略。
enum Paster {
    static func paste(_ text: String, pressEnter: Bool) {
        let pasteboard = NSPasteboard.general

        // 備份使用者原本的剪貼簿，貼完還原（避免蓋掉他複製的東西）
        let previous = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 給剪貼簿一點時間落地，再送 Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            sendKey(virtualKey: 9, flags: .maskCommand)   // 9 = 'v'
            if pressEnter {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    sendKey(virtualKey: 36, flags: [])    // 36 = Return
                }
            }
            // 還原剪貼簿（等 Cmd+V 讀完）
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if let previous {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
            }
        }
    }

    private static func sendKey(virtualKey: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
