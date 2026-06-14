import AppKit

// Push-to-talk：用「右 Command」當對講機鍵。
// 選右 Cmd 的好處：它是 modifier，按住/放開不會在前景 app 打出任何字元，
// 所以不需要攔截吞掉事件（不像 F5 那種一般鍵會被輸入框收到）。
//
// 另外監聽 Esc：錄音中按 Esc 可取消這次（不辨識、不貼上）。
//
// 需要權限：System Settings → Privacy & Security → Input Monitoring（或 Accessibility）
// 要把這個 app 勾起來，全域鍵盤事件才收得到。
final class HotKeyManager {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?

    private var isDown = false
    private let rightCommandKeyCode: UInt16 = 54   // 右 Command
    private let escapeKeyCode: UInt16 = 53         // Esc

    func start() {
        NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handle(event)
        }
        NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        if event.type == .keyDown {
            if event.keyCode == escapeKeyCode, isDown {
                isDown = false
                onCancel?()
            }
            return
        }
        // flagsChanged：右 Cmd 的按下 / 放開
        guard event.keyCode == rightCommandKeyCode else { return }
        let commandHeld = event.modifierFlags.contains(.command)
        if commandHeld && !isDown {
            isDown = true
            onPress?()
        } else if !commandHeld && isDown {
            isDown = false
            onRelease?()
        }
    }
}
