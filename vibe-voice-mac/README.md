# VibeVoice — M1 MacBook 語音輸入（vibe coding）

按住 **右 Command** 說話 → WhisperKit 在本地（M1 ANE/GPU）辨識中英混雜語音 →
自動貼到最前景的 app（終端機 / 編輯器 / Claude Code）。

完全離線（模型首次下載後），push-to-talk，低延遲。

## 架構

```
按住 右Cmd (HotKeyManager, flagsChanged 全域監聽)
  → AudioRecorder 錄 16kHz mono WAV
放開 右Cmd
  → Transcriber: WhisperKit large-v3-turbo 本地辨識 (Core ML, 跑在 ANE)
  → Paster: 寫剪貼簿 + 模擬 Cmd+V 貼到前景 app（可選自動 Enter）
```

| 檔案 | 職責 |
|------|------|
| `VibeVoiceApp.swift` | MenuBarExtra menu bar app 入口 + 選單 UI |
| `AppState.swift` | 串接：權限、載模型、錄音→辨識→貼上 狀態機 |
| `HotKeyManager.swift` | 右 Cmd push-to-talk（全域鍵盤監聽）|
| `AudioRecorder.swift` | AVAudioRecorder 錄 16k/mono/16-bit WAV |
| `Transcriber.swift` | WhisperKit 封裝（本地推論）|
| `Paster.swift` | 剪貼簿 + CGEvent 模擬 Cmd+V 貼字 |

## 在 Xcode 建專案的步驟

1. **建立 App**：Xcode → New Project → macOS → **App**，介面選 **SwiftUI**，語言 **Swift**。
   命名 `VibeVoice`。
2. **刪掉**範本的 `ContentView.swift` 和預設的 `VibeVoiceApp.swift`，把本資料夾 `VibeVoice/` 裡的 6 個 `.swift` 拖進去。
3. **加入 WhisperKit 套件**：File → Add Package Dependencies → 貼上
   `https://github.com/argmaxinc/WhisperKit` → Add。
4. **Info.plist / 權限說明字串**（Target → Info）：
   - `NSMicrophoneUsageDescription` = `需要麥克風來做語音輸入`
   - 把 `Application is agent (UIElement)` (`LSUIElement`) 設為 `YES` → 純 menu bar、不在 Dock 出現。
5. **Signing & Capabilities**：
   - 若用 **App Sandbox**，勾 **Audio Input** 與 **Outgoing Connections (Client)**（模型下載要）。
     ⚠️ 注意：Sandbox 會擋 CGEvent 全域送鍵/監聽——**開發階段建議先「關掉 App Sandbox」**讓貼字與熱鍵能動，之後要上架再處理。
6. **Build & Run**。第一次跑會：
   - 跳出麥克風授權 → 允許。
   - 背景下載 large-v3-turbo 模型（約幾百 MB，等選單顯示「模型已就緒」）。
7. **手動授權兩個權限**（System Settings → Privacy & Security）：
   - **Input Monitoring**：勾 VibeVoice（收得到全域右 Cmd）。
   - **Accessibility**：勾 VibeVoice（CGEvent 才送得出 Cmd+V）。
   勾完重啟 app。

## 使用

對著任何輸入框（終端機的 Claude Code、Cursor、瀏覽器…），**按住右 Cmd 講話，放開**，文字就貼進去。
選單可切換「貼上後自動送出 (Enter)」——對 Claude Code CLI 很順。

## 之後可以加的（升級方向）

- **熱詞 / initial prompt**：把專案常用詞（框架名、變數名、repo 名）塞進 `DecodingOptions.promptTokens`，技術詞辨識大幅提升。
- **串流預覽**：改用 WhisperKit 的串流 API 邊講邊顯示。
- **LLM 清理層**：辨識後丟一次小模型把口語整理成乾淨指令（多數情況直接貼原文給 Claude 就夠，非必要）。
- **吞掉熱鍵 / 自訂鍵**：想用一般鍵（如 F5）當對講鍵時，改用 `CGEventTap` 攔截避免打出字元。
- **省記憶體**：弱機把模型改 `base` 或 `small` 先測流程，再換 turbo。
