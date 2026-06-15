# VibeVoice 診斷：按住 Command 說中文卻沒有文字輸入

App 會編譯且能跑，但「按住 Command 說話 → 放開 → 沒有文字」。這幾乎都是
**執行期 / 權限**問題，不是編譯問題。以下依「最可能」排序，每項都附上
在 Console.app 要找的 `[VibeVoice]` log 行，以及要檢查的系統設定開關。

> 看 log 的方法：開 **Console.app** → 左側選你的 Mac → 搜尋框輸入
> `VibeVoice` → 按一次熱鍵並說話。對照下面各項的關鍵字。

---

## 1. 點一下 vs 真的按住（TAP-VS-HOLD）—— 最常見

太短的錄音被當成誤觸丟掉。原本門檻 `0.3s` 對「點一下就放」太嚴，
整句會被丟。已降到 **0.2s**，並加上明確 log。

- **如何確認**：log 出現
  `[VibeVoice][Flow] recording DISCARDED — too short (dur=0.0xx s ...)`
  → 代表你只是「點」而不是「按住」。
- **怎麼做**：**按住** Command 不放，把話講完，**再**放開。
- 若門檻仍嫌嚴，可再把 `AppState.minDurationSec` 調更低（勿移除此 guard）。

## 2. 輔助使用權限沒給（ACCESSIBILITY）—— 第二常見，「辨識到卻打不出來」

TextInserter 用 CGEvent 把字打進前景 app，這需要 **輔助使用**
（Accessibility）權限。沒授權時按鍵被系統靜默丟棄：log 顯示有辨識結果、
HUD 也顯示文字，但前景 app **完全沒有字**。

- **如何確認**：
  - 選單列點開 VibeVoice → 看「**輔助使用權限：未授權**」。
  - 或 log 出現
    `[VibeVoice][Flow] insert called BUT 輔助使用權限未授權`
    或 `[VibeVoice][Insert] insert called · len=N ... AXTrusted=false`。
- **怎麼做**：**系統設定 → 隱私權與安全性 → 輔助使用** →
  把 VibeVoice 打開（選單裡有「開啟 系統設定 → 輔助使用」快捷鈕）。
  授權後在選單按「**重新檢查權限**」，或重啟 app。

## 3. 輸入監控沒給（INPUT MONITORING）—— 熱鍵根本沒觸發

熱鍵靠攔截全域鍵盤事件，需要 **輸入監控**（Input Monitoring）權限。
沒給的話按 Command 完全不會進入錄音流程。

- **如何確認**：按住 Command 說話，log **完全沒有**
  `[VibeVoice][Flow] press→startRecording` 這行 → 熱鍵沒被收到。
- **怎麼做**：**系統設定 → 隱私權與安全性 → 輸入監控** → 開啟 VibeVoice，
  然後重啟 app。
  （此權限由 HotKeyManager 處理，不在本次修改範圍。）

## 4. 按左 Command 還是右 Command

HotKeyManager 現在「左右 Command 皆可」（keyCode 54 與 55 都接受），所以
單純按錯邊不再是問題。但要注意觸發條件是「Command 為**唯一**按住的
modifier」：若同時按著 Shift / Option / Control，會被視為一般快捷鍵而**不**觸發。

- **如何確認**：同第 3 點——按 Command 說話卻沒有 `press→startRecording` log。
  若 log 有 `press` 但沒有 `release→finalize`，多半是放開時夾帶了其他 modifier。
- **怎麼做**：單獨按住一顆 Command（不要同時壓 Shift/Option/Control），說完再放開。

## 5. 模型還沒載入完成 / 下載失敗（MODEL NOT READY）

`modelReady=false` 時 `startRecording` 會直接 return；WhisperKit 首次
要下載模型，網路差或失敗就一直不就緒。

- **如何確認**：
  - 選單看「**模型：載入中…**」一直沒變成「已就緒」。
  - log 出現 `[VibeVoice][Flow] startRecording SKIPPED (... modelReady=false)`。
- **怎麼做**：等模型下載完（選單變「模型：已就緒」）。確認有網路；
  必要時看 Transcriber 的 log 是否報下載錯誤。

---

## 麥克風（次要，但會造成空辨識）

若麥克風權限沒給或裝置無聲，會錄到空音訊：

- log `[VibeVoice][Flow] mic.start() FAILED: ...` → 麥克風啟動失敗。
- log `[VibeVoice][Flow] finalize done · finalLen=0` 且
  `insert SKIPPED — empty transcription` → 有錄到但辨識為空（沒收到音）。
- 檢查 **系統設定 → 隱私權與安全性 → 麥克風** 是否已授權 VibeVoice。

---

## 一眼判讀流程（理想的成功 log 順序）

```
[VibeVoice][Flow] press→startRecording · status=idle modelReady=true
[VibeVoice][Flow] poll preview len=N dur=...
[VibeVoice][Flow] release→finalize · dur=1.2xx s samples=...
[VibeVoice][Flow] finalize done · finalLen=N dur=...
[VibeVoice][Flow] accessibilityTrusted=true
[VibeVoice][Flow] insert called · len=N mode=directType
[VibeVoice][Insert] insert called · len=N mode=directType ... AXTrusted=true
```

對照你實際缺哪一行，就知道卡在哪一關：
- 缺第 1 行 → 熱鍵沒觸發（第 3 / 4 項）。
- 走到 `DISCARDED — too short` → 第 1 項（沒按住）。
- 走到 `輔助使用權限未授權` / `AXTrusted=false` → 第 2 項。
- `finalLen=0` / `empty transcription` → 模型或麥克風（第 5 項 / 麥克風）。

> 隱私：所有 log 只記**文字長度**與模式，**從不**記錄辨識到的內容。
