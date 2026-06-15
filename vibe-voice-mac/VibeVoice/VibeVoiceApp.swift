import SwiftUI
import AppKit

// VibeVoice — M1 MacBook 語音輸入（vibe coding）
// menu bar app：按住右 Command 說話 → WhisperKit 本地辨識 → 直接鍵入前景 app。
@main
struct VibeVoiceApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuView(state: state)
        } label: {
            Image(systemName: state.status.symbolName)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuView: View {
    @ObservedObject var state: AppState

    var body: some View {
        Text("VibeVoice — \(state.status.label)")

        Divider()

        // 安全相關：直接鍵入不碰剪貼簿；關掉才走剪貼簿後備
        Toggle("直接鍵入（不碰剪貼簿，較安全）", isOn: $state.useDirectTyping)
        Toggle("貼上後自動送出 (Enter)", isOn: $state.pressEnterAfterPaste)

        Divider()

        // 自我診斷狀態列
        Text(state.modelReady
             ? "模型：已就緒 · 熱詞 \(state.hotwordCount) 個"
             : "模型：載入中…（未就緒時錄音會被略過）")
            .font(.caption)
        Text(state.accessibilityTrusted
             ? "輔助使用權限：已授權"
             : "輔助使用權限：未授權（文字無法鍵入！）")
            .font(.caption)
        Text("用法：按住 Command 說話，說完再放開")
            .font(.caption2)
        Text("熱詞檔：~/.vibevoice/hotwords.txt")
            .font(.caption2)

        if !state.accessibilityTrusted {
            Button("開啟 系統設定 → 輔助使用") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        Button("重新檢查權限") { state.refreshAccessibilityStatus() }

        Divider()

        Button("結束") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
