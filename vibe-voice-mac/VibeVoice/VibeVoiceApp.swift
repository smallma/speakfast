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

        Text(state.modelReady
             ? "模型已就緒 · 熱詞 \(state.hotwordCount) 個"
             : "模型載入中…")
            .font(.caption)
        Text("熱詞檔：~/.vibevoice/hotwords.txt")
            .font(.caption2)

        Divider()

        Button("結束") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
