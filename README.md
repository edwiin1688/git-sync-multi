# git-sync-multi
批次管理多個 Git 專案的同步與備份工具。

## 🛠️ 工具清單

### 1. batch_gh_create.ps1 (批次 GitHub 倉庫建立)
這個工具可以讓您在多個 GitHub 帳號下快速同步建立多個 Repository，並自動處理權限與本地關聯。

#### 功能特點
- **多帳號自動切換**：自動偵測 `gh auth status` 中的帳號並執行 `gh auth switch`。
- **雙檔案配置**：透過 `accounts.txt` 管理帳號，`projects.txt` 管理專案名稱與參數。
- **智慧過濾**：自動跳過已存在的專案，若為私人或 Fork 專案會發出明顯警告。
- **自動關聯**：若本地已存在資料夾且無遠端關聯，自動執行 `git init`、`commit` 並推送到新建立的遠端。

#### 使用方法
- 在 `accounts.txt` 填入 GitHub 帳號清單。
- 在 `projects.txt` 填入專案資訊（例如：`my-repo --public`）。
- 執行：`./batch_gh_create.ps1`
- **日誌紀錄**：所有的成功、跳過或錯誤原因都會紀錄在 `create_log.log`。

---

### 2. batch_git_pull.ps1 (批次更新)
自動掃描指定目錄下的所有子資料夾，若發現為 Git 倉庫，則自動執行 `git pull` 以同步遠端更新。

#### 使用方法
- 在 PowerShell 中執行：`./batch_git_pull.ps1`
- **錯誤記錄**：若執行過程中發生錯誤，將會記錄在 `git_pull_errors.log` 中。

---

### 3. batch_create_git_sync.ps1 (批次初始化)
批次為每個子目錄建立 `setup_git_sync.ps1` 同步設定腳本。

#### 功能說明
- 掃描 `ROOT_PATH` 下的所有子目錄，若無 `setup_git_sync.ps1` 則根據範本產生檔案。

#### 使用方法
- 在 PowerShell 中執行：`./batch_create_git_sync.ps1`

---

### 4. batch_git_status.ps1 (批次狀態檢查)
檢查 `ROOT_PATH` 下所有 Git 專案是否有未提交的異動。

#### 使用方法
- 在 PowerShell 中執行：`./batch_git_status.ps1`

---

### 5. batch_git_remote.ps1 (批次遠端檢查與導出)
掃描 `ROOT_PATH` 下所有 Git 專案的遠端位址 (`git remote -v`)，並自動分類與導出可用清單。

#### 功能特點
- **雙 Log 分流**：
    - **`git_remote_list.log`**: 紀錄標準 2 筆遠端 (fetch/push) 的專案。
    - **`git_remote_debug.log`**: 紀錄擁有 3 筆以上遠端位址的複雜專案。
- **自動導出清單**：自動將標準公開專案導出至 **`extracted_projects.txt`**。
- **智慧過濾**：
    - 自動排除 **Private (私人)** 與 **Fork** 專案。
    - 自動排除 Description 開頭為 **✅** 的已完成專案。
- **格式相容**：導出的內容格式完全符合 `projects.txt` 要求。

#### 使用方法
- 在 PowerShell 中執行：`./batch_git_remote.ps1`
- **結果檔案**：
    - 標準清單：`git_remote_list.log`
    - 調試合併：`git_remote_debug.log`
    - 導出專案：`extracted_projects.txt`

---

## ⚙️ 配置說明

### 1. 環境變數 (.env)
請將 `.env.example` 複製為 `.env` 並根據您的環境修改：
```text
ROOT_PATH="D:\github\chiisen\"      # 所有專案存放的根目錄
GITHUB_ACCOUNT=your_username        # 您的主要 GitHub 帳號
```

### 2. 帳號清單 (accounts.txt)
列出所有受管理的 GitHub 帳號（需已透過 `gh auth login` 登入）：
- 格式：每行一個帳號名稱。
- 範例請參考 `accounts.txt.example`。

### 3. 專案清單 (projects.txt)
列出您想要巡檢或建立的專案名稱與 `gh` 參數：
- 格式：`[專案名稱] [可選參數]`。
- 範例請參考 `projects.txt.example`。
- **支援參數**：可加入 `--public`, `--private`, `--description "..."`, `--license mit` 等所有 GitHub CLI 支援的參數。

---

## � 日誌紀錄 (Logs)

本工具產生的日誌檔案均已加入 `.gitignore`，不會被上傳：

- **`create_log.log`**: 記錄 `batch_gh_create.ps1` 的執行結果，包含專案詳細資訊與本地遠端位址。
- **`git_remote_list.log`**: 記錄掃描到的標準 2 筆遠端 (fetch/push) 專案。
- **`git_remote_debug.log`**: 記錄擁有多重遠端位址的專案，方便調試。
- **`extracted_projects.txt`**: 根據過濾條件導出的可用專案清單，其格式符合 `projects.txt`。
- **`git_pull_errors.log`**: 記錄 `batch_git_pull.ps1` 執行失敗的倉庫。
- **`git_status_changed.log`**: 記錄 `batch_git_status.ps1` 偵測到有異動的檔案清單。

> 💡 **提示**：所有 Log 與導出檔案在每次對應的腳本啟動時，都會自動清空舊資料。

---

## 📄 檔案結構
- `batch_gh_create.ps1`: 核心建立與同步工具。
- `batch_git_pull.ps1`: 批次更新工具。
- `batch_create_git_sync.ps1`: 批次同步腳本初始化工具。
- `batch_git_status.ps1`: 批次異動檢查工具。
- `batch_git_remote.ps1`: 批次遠端位址掃描工具。
- `accounts.txt.example`: 帳號清單範本。
- `projects.txt.example`: 專案清單範本。
- `.env.example`: 環境變數範本。


