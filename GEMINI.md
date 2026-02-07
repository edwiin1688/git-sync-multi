# Project Context & Guidelines (GEMINI.md)

本文件紀錄 `git-sync-multi` 專案的開發規範、檔案路徑共識與運作邏輯，供 AI 代理人參考。

## 📂 目錄架構規範
所有腳本開發應遵循以下路徑約定：

- **`logs/`**: 所有日誌檔案 (`*.log`)、錯誤紀錄、與過程偵錯資料均應存放在此。
- **`ini/`**: 所有使用者設定檔 (`*.txt`) 與對應的範本檔 (`*.example`) 均應存放在此。
- **`out/`**: 腳本執行後的最終資料產出物（如導出的專案清單）應存放在此。
- **根目錄**: 僅存放核心腳本 (`*.ps1`) 為原則。

## 🔐 運作特徵與習慣
開發或修改腳本時，請確保具備以下邏輯：

### 1. 啟動自我檢查
- **載入環境變數**: 啟動時必須優先執行 `Load-Env` 從 `.env` 取得配置。
- **切換 GitHub 帳號**: 若環境變數定義了 `GITHUB_ACCOUNT`，必須自動執行 `gh auth switch -u $GITHUB_ACCOUNT` 確保權限正確。

### 2. 智慧過濾 (Smart Filtering)
執行批次處理、狀態檢查或同步時，具備以下過濾共識（除非使用者另有要求）：
- **跳過 Private (私有)** 專案。
- **跳過 Fork (分支)** 專案。
- **跳過 已完成專案**: 若 GitHub Description 以 `✅` 開頭，視為已完成並過濾。
- **靜默處理**: 被過濾的項應記錄於 `logs/`，減少終端機干擾。

### 3. 效能優化
- **平行處理**: 涉及網路等待（如 `git pull`, `git status`）的批次操作，應優先使用 PowerShell 7 的 `ForEach-Object -Parallel` 進行優化。

### 4. 自動化自愈
- **自動復原雜訊**: 對於 `.python-version` 或 `setup_git_sync.ps1` 這類環境產生的唯一變動，腳本應具備自動執行 `git checkout` 或 `git clean` 以還原乾淨狀態的能力。
- **自動同步圖示**: 若異動僅包含 Windows 目錄圖示檔案 (`desktop.ini`, `folderico-green.ico`)，應自動執行 commit (訊息：`feat: 更新目錄 icon`) 與 pull。

---
*本文件將隨專案演進持續更新。*
