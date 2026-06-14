import SwiftUI

// VibeVoice — M1 MacBook 語音輸入（vibe coding）
// menu bar app：按住 Right Command 說話 → WhisperKit 本地辨識 → 自動貼到前景 app。
@main
struct VibeVoiceApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuView(state: state)
        } label: {
            // 狀態圖示：閒置 / 錄音中 / 辨識中
            Image(systemName: state.status.symbolName)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuView: View {
    @ObservedObject var state: AppState

    var body: some View {
        Text("VibeVoice — \(state.status.label)")
        if !state.lastText.isEmpty {
            Text("最近：\(state.lastText.prefix(40))")
                .font(.caption)
        }
        Divider()
        Toggle("貼上後自動送出 (Enter)", isOn: $state.pressEnterAfterPaste)
        Divider()
        Text(state.modelReady ? "模型已就緒 (large-v3-turbo)" : "模型載入中…")
            .font(.caption)
        Button("結束") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
