#!/bin/bash
# 一鍵在 macOS 上產生並開啟 VibeVoice 的 Xcode 專案。
# 用法：在這個資料夾執行  ./setup.sh
# 完全不需要在 Xcode 裡打字——產生後只要按 Xcode 左上的 ▶ (Run)。

set -e
cd "$(dirname "$0")"

# 1) 確認 xcodegen（用 project.yml 產生 .xcodeproj，免在 Xcode UI 裡手動設定）
if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "→ 安裝 xcodegen..."
    brew install xcodegen
  else
    echo "需要 xcodegen，但找不到 Homebrew。"
    echo "請先安裝 Homebrew: https://brew.sh   然後執行: brew install xcodegen"
    exit 1
  fi
fi

# 2) 產生專案
echo "→ 產生 VibeVoice.xcodeproj ..."
xcodegen generate

# 3) 開啟 Xcode
open VibeVoice.xcodeproj

cat <<'NOTE'

✅ 已開啟 Xcode。接下來（全部只需「點擊」）：
  1. 等 Xcode 解析 Swift Packages（會自動抓 WhisperKit，需網路，第一次稍久）。
  2. 點左上的 ▶ (Run) 建置並執行。
  3. 跳出麥克風授權 → 允許。
  4. 首次會下載語音模型（幾百 MB），選單列圖示就緒後再用。
  5. System Settings → Privacy & Security：
       - Input Monitoring 勾 VibeVoice
       - Accessibility   勾 VibeVoice
     勾完重開 app。
  6. 在 TextEdit 點一下，按住「右 Command」說話，放開 → 文字鍵入。

NOTE
