import AppKit

// Push-to-talk：用「Command」當對講機鍵（左右 Command 皆可）。
// 選 Cmd 的好處：它是 modifier，按住/放開不會在前景 app 打出任何字元，
// 所以不需要攔截吞掉事件（不像 F5 那種一般鍵會被輸入框收到）。
//
// 觸發條件：偵測到 Command 變成「唯一」按住的 modifier（沒有同時按 Shift /
// Option / Control）。這樣才不會干擾 Cmd+C、Cmd+Tab 等一般快捷鍵。
//   - 左 Command = keyCode 55，右 Command = keyCode 54，兩者都接受。
//   - 之前的程式只認 keyCode 54（右 Cmd），使用者按左 Cmd 時完全沒反應，
//     這就是「按住 Command 講中文卻沒有文字」的根因。
//
// 另外監聽 Esc：錄音中按 Esc 可取消這次（不辨識、不貼上）。
//
// ⚠️ 權限：全域 flagsChanged 監聽需要 Input Monitoring（或 Accessibility）權限。
// 在 System Settings → Privacy & Security → Input Monitoring（或 Accessibility）
// 把這個 app 勾起來，否則 global monitor 會「靜默地」收不到任何事件
// （不會報錯、也不會 crash，就是 handler 永遠不被呼叫）。
final class HotKeyManager {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?

    private var isDown = false
    private let leftCommandKeyCode: UInt16 = 55    // 左 Command
    private let rightCommandKeyCode: UInt16 = 54   // 右 Command
    private let escapeKeyCode: UInt16 = 53         // Esc

    // 持有 monitor 物件：不保留的話（尤其 local monitor）可能被釋放，熱鍵就失效。
    private var monitors: [Any] = []

    func start() {
        NSLog("[VibeVoice][HotKey] start(): installing global + local monitors for .flagsChanged/.keyDown")
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: { [weak self] event in
            self?.handle(event)
        }) {
            monitors.append(global)
            NSLog("[VibeVoice][HotKey] global monitor installed")
        } else {
            NSLog("[VibeVoice][HotKey] WARNING: failed to install global monitor (check Input Monitoring/Accessibility permission)")
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: { [weak self] event in
            self?.handle(event)
            return event
        }) {
            monitors.append(local)
            NSLog("[VibeVoice][HotKey] local monitor installed")
        } else {
            NSLog("[VibeVoice][HotKey] WARNING: failed to install local monitor")
        }
    }

    private func handle(_ event: NSEvent) {
        if event.type == .keyDown {
            if event.keyCode == escapeKeyCode, isDown {
                NSLog("[VibeVoice][HotKey] cancel: Esc pressed while recording (keyCode=\(event.keyCode) flags=\(event.modifierFlags.rawValue))")
                isDown = false
                onCancel?()
            }
            return
        }

        // flagsChanged：modifier 按下 / 放開。
        // 我們要的是「Command 變成唯一按住的 modifier」= push-to-talk 開始；
        // Command 不再按住（或有其他 modifier 加入）= push-to-talk 結束。
        //
        // 用 deviceIndependentFlagsMask 過濾掉低位的硬體狀態位，只看語意 modifier，
        // 避免左右鍵 / caps lock 等雜訊造成誤判。
        let relevant = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let commandHeld = relevant.contains(.command)
        let otherModifiers = relevant.intersection([.shift, .option, .control, .capsLock])
        // Command 是唯一作用中的 modifier 嗎？
        let commandIsSole = commandHeld && otherModifiers.isEmpty

        // 只在這次 flagsChanged 真的是左/右 Command 鍵造成時才當作「按下」。
        // （其他 modifier 的 flagsChanged 也會進來，這時 keyCode 不會是 Cmd 的 keyCode。）
        let isCommandKeyEvent = (event.keyCode == leftCommandKeyCode || event.keyCode == rightCommandKeyCode)

        if !isDown {
            // 還沒開始錄：只有當「Command 成為唯一 modifier」且這個事件就是 Command 鍵按下時才觸發。
            if commandIsSole && isCommandKeyEvent {
                NSLog("[VibeVoice][HotKey] press: Command down (keyCode=\(event.keyCode) flags=\(relevant.rawValue))")
                isDown = true
                onPress?()
            }
        } else {
            // 錄音中：Command 放開，或有其他 modifier 加入（例如 Cmd 之後又按了 Shift），就結束。
            if !commandHeld || !otherModifiers.isEmpty {
                NSLog("[VibeVoice][HotKey] release: Command no longer sole modifier (keyCode=\(event.keyCode) flags=\(relevant.rawValue))")
                isDown = false
                onRelease?()
            }
        }
    }
}
