# VibeVoice — M1 MacBook 語音輸入（vibe coding）

按住 **右 Command** 說話 → WhisperKit 在本地（M1 ANE/GPU）辨識中英混雜語音 →
**直接鍵入**最前景的 app（終端機 / 編輯器 / Claude Code）。

完全離線（模型首次下載後），push-to-talk，低延遲，預設不碰剪貼簿。

## 架構

```
按住 右Cmd (HotKeyManager, flagsChanged 全域監聽)
  → AudioRecorder 錄 16kHz mono WAV
放開 右Cmd        （錄音中按 Esc 可取消）
  → Transcriber: WhisperKit large-v3-turbo 本地辨識 (Core ML, 跑在 ANE)
                 + 熱詞注入 + 幻覺過濾
  → TextInserter: CGEvent Unicode 直接鍵入前景 app（不碰剪貼簿）
```

| 檔案 | 職責 |
|------|------|
| `VibeVoiceApp.swift` | MenuBarExtra menu bar app 入口 + 選單 UI |
| `AppState.swift` | 串接：權限、載模型、錄音→辨識→輸入 狀態機；設定持久化 |
| `HotKeyManager.swift` | 右 Cmd push-to-talk + Esc 取消（全域鍵盤監聽）|
| `AudioRecorder.swift` | AVAudioRecorder 錄 16k/mono/16-bit WAV，回傳長度 |
| `Transcriber.swift` | WhisperKit 封裝（本地推論）+ 熱詞 + 幻覺過濾 |
| `Vocabulary.swift` | 熱詞清單（`~/.vibevoice/hotwords.txt` 或內建預設）|
| `TextInserter.swift` | 直接鍵入（不碰剪貼簿）／剪貼簿後備 |

## 安全與隱私設計

- **預設「直接鍵入」不碰剪貼簿**：口述的敏感內容（密碼 / token / 私訊）不會留進
  剪貼簿歷史，也不會蓋掉你原本複製的東西。需要時可在選單切到剪貼簿後備
  （它會備份並還原你的剪貼簿，把暴露窗口降到最低）。
- **本地辨識**：唯一的網路行為是「首次下載模型」，之後語音不離開本機。
- **不記錄內容**：辨識文字不寫進 log、也不顯示在選單，避免敏感口述外流。
- **暫存錄音保證刪除**：每次辨識後（含失敗 / 取消）都會刪掉 temp WAV。
- **誤觸保護**：< 0.3 秒的錄音（手滑按一下）直接忽略，連模型都不跑。

## 好用設計

- **熱詞注入**：把你的技術術語（框架名、變數名、repo 名）餵給 Whisper，
  技術詞辨識大升。編輯 `~/.vibevoice/hotwords.txt`（一行一個詞，`#` 為註解），
  下次辨識即生效；檔案不存在時用 `Vocabulary.swift` 的預設清單。
- **幻覺過濾**：Whisper 對靜音 / 極短音常吐「謝謝大家 / Thank you」之類垃圾，過濾掉。
- **Esc 取消** 與 **自動 Enter**（對 Claude Code CLI 很順）。
- 設定（直接鍵入 / 自動 Enter）持久化,重開保留。

## 在 Xcode 建專案的步驟

1. **建立 App**：Xcode → New Project → macOS → **App**，介面 **SwiftUI**，語言 **Swift**，命名 `VibeVoice`。
2. **刪掉**範本的 `ContentView.swift` 和預設 `VibeVoiceApp.swift`，把本資料夾 `VibeVoice/` 裡的 7 個 `.swift` 拖進去。
3. **加入 WhisperKit 套件**：File → Add Package Dependencies → `https://github.com/argmaxinc/WhisperKit` → Add。
4. **Info.plist / 權限說明字串**（Target → Info）：
   - `NSMicrophoneUsageDescription` = `需要麥克風來做語音輸入`
   - `Application is agent (UIElement)` (`LSUIElement`) = `YES` → 純 menu bar、不進 Dock。
5. **建置設定（一次到位，務必照做）**：
   - **macOS Deployment Target ≥ 13.0**（`MenuBarExtra` 需要 macOS 13）。
   - **Swift Language Version = Swift 5**（Xcode 新專案的預設值；別切到 Swift 6 語言模式，
     否則嚴格並行檢查會把跨 actor 的非 Sendable 物件報成錯）。
   - **Signing & Capabilities → 開發階段先關掉 App Sandbox**
     （Sandbox 會擋 CGEvent 全域監聽/送鍵，熱鍵與直接鍵入會失效）。
6. **Build & Run** → 允許麥克風 → 等選單顯示「模型已就緒」（首次下載 large-v3-turbo，約幾百 MB）。
7. **手動授權**（System Settings → Privacy & Security）：
   - **Input Monitoring**：勾 VibeVoice（收得到全域右 Cmd / Esc）。
   - **Accessibility**：勾 VibeVoice（CGEvent 才送得出按鍵）。
   勾完重啟 app。

## 使用

對著任何輸入框（終端機的 Claude Code、Cursor、瀏覽器…），**按住右 Cmd 講話、放開**，
文字就鍵入進去。錄音中反悔就按 **Esc**。

## API 驗證狀態

所有 WhisperKit 介面已逐一對照官方原始碼（`main`）確認簽名相符：
`WhisperKit(_:)`、`WhisperKitConfig(model:)`、
`DecodingOptions(task:language:temperature:usePrefillPrompt:promptTokens:)`、
`transcribe(audioPath:decodeOptions:) -> [TranscriptionResult]`、
`tokenizer.encode(text:)`、`tokenizer.specialTokens.specialTokenBegin`、`TranscriptionResult.text`。
（無法在非 macOS 環境實際編譯，但 API 與 Swift/AppKit/AVFoundation 用法均已人工核對。）

## 之後可再加（升級方向）

- **串流邊講邊出字**：改用 WhisperKit 串流 API。
- **LLM 清理層**：把口語整理成乾淨指令（多數情況直接貼原文給 Claude 就夠，非必要）。
- **自訂對講鍵**：想換成一般鍵（如 F5）時，用 `CGEventTap` 攔截避免打出字元。
- **省記憶體**：弱機把 `Transcriber.swift` 的模型改 `base` / `small` 先測流程。
