# ==============================================================================
# 腳本名稱: batch_gh_create.ps1
# 功能描述: 批次 GitHub 倉庫建立工具。
#           快速在多個 GitHub 帳號下同步建立 Repository，並自動處理權限與本地關聯。
# ==============================================================================

# 定義載入 .env 的函式
function Load-Env {
    param($Path = ".env")
    $envPath = Join-Path $PSScriptRoot $Path
    if (Test-Path $envPath) {
        Get-Content $envPath | Where-Object { $_ -match '=' -and $_ -notmatch '^#' } | ForEach-Object {
            $parts = $_.Split('=', 2)
            if ($parts.Count -eq 2) {
                $name = $parts[0].Trim()
                $value = $parts[1].Trim().Trim('"').Trim("'")
                [System.Environment]::SetEnvironmentVariable($name, $value, "Process")
            }
        }
    }
}

# 檢查 gh CLI 是否可用
function Check-GhCli {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Error "找不到 GitHub CLI (gh)。請先安裝：https://cli.github.com/"
        return $false
    }
    return $true
}

# 清理 Description 中的控制字元
function Sanitize-Description {
    param([string]$Description)
    
    if ([string]::IsNullOrEmpty($Description)) { return "" }
    
    # 移除換行 (\r\n, \n) 和 Tab (\t) 等控制字元
    $cleanDesc = $Description -replace '[\r\n\t]+', ' '
    # 移除頭尾空白
    $cleanDesc = $cleanDesc.Trim()
    
    # 若有清理過 (內容改變)，加上 ⁉️ 提醒
    if ($cleanDesc -ne $Description.Trim()) {
        $cleanDesc = "⁉️ $cleanDesc"
    }
    
    return $cleanDesc
}

Load-Env

# 切換 GitHub 帳號 (確保權限正確)
if ($env:GITHUB_ACCOUNT) {
    Write-Host "切換 GitHub 帳號至: $env:GITHUB_ACCOUNT" -ForegroundColor Cyan
    gh auth switch -u $env:GITHUB_ACCOUNT 2>$null
}

Write-Host ">>> 批次 GitHub 倉庫建立工具" -ForegroundColor Yellow
Write-Host "功能：快速在多個 GitHub 帳號下同步建立 Repository，並自動處理權限與本地關聯。" -ForegroundColor Gray
Write-Host ""

if (-not (Check-GhCli)) { exit }

# 顯示當前 GitHub 帳號狀態
Write-Host "正在取得已登入帳號清單..." -ForegroundColor Gray
$ghAccounts = gh auth status 2>&1 | ForEach-Object {
    if ($_ -match 'account\s+(?<name>[^\s\(]+)') { $Matches['name'] }
}
Write-Host "偵測到帳號: $($ghAccounts -join ', ')" -ForegroundColor Gray

# 設定參數
$rootPath = if ($env:ROOT_PATH) { $env:ROOT_PATH } else { "D:\github\chiisen\" }
$mainAccount = $env:GITHUB_ACCOUNT
$logDir = Join-Path $PSScriptRoot "logs"
$outDir = Join-Path $PSScriptRoot "ini"
$accountsFile = Join-Path $outDir "accounts.txt"
$projectsFile = Join-Path $outDir "projects.txt"
$createLogPath = Join-Path $logDir "create_log.log"

# 確保資料夾存在
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

# 顯示主帳號資訊
if ($mainAccount) {
    Write-Host "設定之主帳號: $mainAccount" -ForegroundColor Cyan
}

# 1. 初始化日誌檔案 (清空舊資料)
$startTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
"--- GitHub Repository Creation Batch Start: $startTime ---`n根目錄: $rootPath`n主帳號: $mainAccount`n" | Out-File -FilePath $createLogPath -Encoding utf8

# 檢查檔案
if (-not (Test-Path $accountsFile)) {
    Write-Error "找不到 accounts.txt。請參考 accounts.txt.example 建立。"
    exit
}
if (-not (Test-Path $projectsFile)) {
    Write-Error "找不到 projects.txt。請參考 projects.txt.example 建立。"
    exit
}

# 讀取清單
$accounts = Get-Content -Path $accountsFile | Where-Object { $_ -match '^[^#\s]' }
$projects = Get-Content -Path $projectsFile | Where-Object { $_ -match '^[^#\s]' }

Write-Host "`n開始批次處理 GitHub 倉庫..." -ForegroundColor Cyan

foreach ($owner in $accounts) {
    $owner = $owner.Trim()
    
    # --- 多帳號切換邏輯 ---
    Write-Host "`n==========================================" -ForegroundColor Magenta
    if ($ghAccounts -contains $owner) {
        Write-Host "切換帳號至: $owner ..." -ForegroundColor Magenta
        gh auth switch --user $owner | Out-Null
        # 加入緩衝時間，確保帳號切換完全生效
        Start-Sleep -Seconds 3
    } else {
        Write-Host "注意: '$owner' 未在已登入帳號中，將使用目前活動帳號嘗試。" -ForegroundColor Yellow
    }

    foreach ($line in $projects) {
        # 解析專案行
        $trimmedLine = $line.Trim()
        if ($trimmedLine -match '^(?<name>[^\s]+)(\s+(?<params>.+))?$') {
            $repoName = $Matches['name']
            $extraParams = if ($Matches['params']) { $Matches['params'] } else { "--private" }
            
            # 對專案進行 Description 控制字元淨化
            if ($extraParams -match '--description\s+"([^"]*)"') {
                $originalDesc = $Matches[1]
                $sanitizedDesc = Sanitize-Description -Description $originalDesc
                
                if ($sanitizedDesc -ne $originalDesc) {
                    Write-Host "  ⚠️ Description 包含控制字元，已自動清理。" -ForegroundColor Yellow
                    $extraParams = $extraParams -replace '--description\s+"[^"]*"', "--description `"$sanitizedDesc`""
                }
            }
            
            $repoFull = "$owner/$repoName"
            $targetDir = Join-Path $rootPath $repoName

            Write-Host "`n------------------------------------------" -ForegroundColor Gray
            Write-Host "處理專案: $repoFull" -ForegroundColor Cyan

            # 1. 檢查 GitHub 倉庫狀態
            $repoInfoJson = gh repo view $repoFull --json description,isPrivate,isFork 2>$null | ConvertFrom-Json
            
            if ($null -ne $repoInfoJson) {
                $isPrivate = $repoInfoJson.isPrivate
                $isFork = $repoInfoJson.isFork
                $desc = if ($repoInfoJson.description) { $repoInfoJson.description } else { "(無說明)" }
                $visibility = if ($isPrivate) { "Private" } else { "Public" }

                # 顯示詳細資訊供除錯
                Write-Host "  -> 說明: $desc" -ForegroundColor Gray
                Write-Host "  -> 權限: $visibility" -ForegroundColor Gray
                Write-Host "  -> Fork: $(if ($isFork){'是'}else{'否'})" -ForegroundColor Gray

                # 新增：檢查本地遠端設定
                $remoteLogInfo = ""
                if (Test-Path $targetDir) {
                    $remotes = @(git -C $targetDir remote -v 2>$null | Where-Object { $_.Trim() -ne "" })
                    if ($remotes.Count -eq 2) {
                        Write-Host "  -> 遠端設定:" -ForegroundColor Gray
                        $remotes | ForEach-Object { 
                            Write-Host "     $_" -ForegroundColor Gray 
                        }
                        # 僅在標準兩筆情況下將遠端資訊存入日誌
                        $remoteLogInfo = "`n      遠端明細:`n      " + ($remotes -join "`n      ")
                    }
                }

                if ($isPrivate) {
                    Write-Host "警告: $repoFull 為私人專案，略過處理。" -ForegroundColor Red
                    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [WARN] SKIP PRIVATE: $repoFull (Desc: $desc)$remoteLogInfo" | Out-File -FilePath $createLogPath -Append
                    continue
                }
                
                if ($isFork) {
                    Write-Host "警告: $repoFull 為 Fork 專案，略過處理。" -ForegroundColor Red
                    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [WARN] SKIP FORK: $repoFull (Desc: $desc)$remoteLogInfo" | Out-File -FilePath $createLogPath -Append
                    continue
                }

                Write-Host "跳過: GitHub 倉庫 $repoFull 已存在 (公開)。" -ForegroundColor Yellow
                "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [EXIST] $repoFull already exists$remoteLogInfo" | Out-File -FilePath $createLogPath -Append
            } else {
                # 2. 建立 GitHub 倉庫
                Write-Host "正在建立倉庫..." -ForegroundColor Green
                
                try {
                    $hasLocalDir = Test-Path $targetDir
                    $shouldUseSource = $false
                    
                    if ($hasLocalDir) {
                        Push-Location $targetDir
                        # 檢查是否已有 origin
                        $hasOrigin = git remote | Where-Object { $_ -eq "origin" }
                        if (-not $hasOrigin) {
                            $shouldUseSource = $true
                            if (-not (Test-Path ".git")) {
                                git init -b main
                                git add .
                                git commit -m "chore: initial commit"
                            }
                        } else {
                            Write-Host "提示: 本地已有關聯遠端 (origin)，將執行純遠端建立以避免衝突。" -ForegroundColor Gray
                        }
                        Pop-Location
                    }

                    if ($shouldUseSource) {
                        Write-Host "偵測到本地資料夾且無遠端關聯，將執行關聯建立與推送..." -ForegroundColor Gray
                        $createCmd = "gh repo create $repoFull $extraParams --source=$targetDir --remote=origin --push"
                    } else {
                        $createCmd = "gh repo create $repoFull $extraParams"
                    }

                    # 執行指令並捕捉所有輸出
                    $output = Invoke-Expression "$createCmd 2>&1"
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "成功建立: $repoFull" -ForegroundColor Green
                        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [SUCCESS] Created $repoFull" | Out-File -FilePath $createLogPath -Append
                    } else {
                        $errorMessage = $output | Out-String
                        Write-Host "建立失敗: $repoFull" -ForegroundColor Red
                        Write-Host "錯誤原因:`n$errorMessage" -ForegroundColor Yellow
                        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [ERROR] Failed to create $repoFull. Reason: $($errorMessage.Trim())" | Out-File -FilePath $createLogPath -Append
                    }
                } catch {
                    Write-Host "執行過程發生意外錯誤: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
    }
}

# --- 更新主帳號 Repository Description ---
if ($mainAccount) {
    Write-Host "`n==========================================" -ForegroundColor Magenta
    Write-Host "更新主帳號 ($mainAccount) Repository Description..." -ForegroundColor Cyan
    
    # 切換回主帳號
    gh auth switch --user $mainAccount 2>$null
    Start-Sleep -Seconds 2
    
    foreach ($line in $projects) {
        $trimmedLine = $line.Trim()
        if ($trimmedLine -match '^(?<name>[^\s]+)(\s+(?<params>.+))?$') {
            $repoName = $Matches['name']
            $mainRepoFull = "$mainAccount/$repoName"
            
            # 取得主帳號 Repository 現有 Description
            $repoInfoJson = gh repo view $mainRepoFull --json description 2>$null | ConvertFrom-Json
            
            if ($null -ne $repoInfoJson) {
                $currentDesc = if ($repoInfoJson.description) { $repoInfoJson.description } else { "" }
                
                # 若開頭不是 ✅ 也不是 ⁉️，加上 ⁉️ 提醒
                if (-not $currentDesc.StartsWith("✅") -and -not $currentDesc.StartsWith("⁉️")) {
                    $newDesc = "⁉️ $currentDesc"
                    Write-Host "`n------------------------------------------" -ForegroundColor Gray
                    Write-Host "更新: $mainRepoFull" -ForegroundColor Cyan
                    Write-Host "  原始: $currentDesc" -ForegroundColor Gray
                    Write-Host "  新增: $newDesc" -ForegroundColor Yellow
                    
                    gh repo edit $mainRepoFull --description "$newDesc" 2>$null
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "  ✅ 更新成功" -ForegroundColor Green
                        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [UPDATE] $mainRepoFull description updated with ⁉️" | Out-File -FilePath $createLogPath -Append
                        
                        # 執行專案目錄的 setup_git_sync.ps1
                        $projectDir = Join-Path $rootPath $repoName
                        $setupScript = Join-Path $projectDir "setup_git_sync.ps1"
                        
                        if (Test-Path $setupScript) {
                            Write-Host "  執行 setup_git_sync.ps1..." -ForegroundColor Cyan
                            Push-Location $projectDir
                            try {
                                & .\setup_git_sync.ps1
                                Write-Host "  ✅ setup_git_sync.ps1 執行完成" -ForegroundColor Green
                                "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [SYNC] $repoName setup_git_sync.ps1 executed" | Out-File -FilePath $createLogPath -Append
                                
                                # 檢查 git status 是否有差異
                                $gitStatus = git status --porcelain 2>$null
                                if ($gitStatus) {
                                    Write-Host "  偵測到 Git 變更，執行自動 commit..." -ForegroundColor Cyan
                                    git add -A
                                    git commit -m "chore: 更新 git sync 設定"
                                    
                                    if ($LASTEXITCODE -eq 0) {
                                        Write-Host "  ✅ 自動 commit 完成" -ForegroundColor Green
                                        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [COMMIT] $repoName auto committed" | Out-File -FilePath $createLogPath -Append
                                        
                                        # 執行 git pull
                                        Write-Host "  執行 git pull..." -ForegroundColor Cyan
                                        git pull --rebase 2>&1 | Out-Null
                                        
                                        if ($LASTEXITCODE -eq 0) {
                                            Write-Host "  ✅ git pull 完成" -ForegroundColor Green
                                        } else {
                                            Write-Host "  ⚠️ git pull 有警告或衝突，請手動檢查" -ForegroundColor Yellow
                                        }
                                    } else {
                                        Write-Host "  ⚠️ 自動 commit 失敗" -ForegroundColor Yellow
                                    }
                                } else {
                                    Write-Host "  無 Git 變更，跳過 commit" -ForegroundColor Gray
                                }
                            } catch {
                                Write-Host "  ❌ setup_git_sync.ps1 執行失敗: $($_.Exception.Message)" -ForegroundColor Red
                            }
                            Pop-Location
                        } else {
                            Write-Host "  ⚠️ 找不到 setup_git_sync.ps1，跳過" -ForegroundColor Yellow
                        }
                    } else {
                        Write-Host "  ❌ 更新失敗" -ForegroundColor Red
                    }
                } else {
                    Write-Host "跳過: $mainRepoFull (description 已有 ✅ 或 ⁉️ 標記)" -ForegroundColor Gray
                }
            }
        }
    }
}

Write-Host "`n批次處理完成！" -ForegroundColor Cyan
