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

# 執行載入
Load-Env

# 設定搜尋的根目錄
$rootPath = if ($env:ROOT_PATH) { $env:ROOT_PATH } else { "D:\github\chiisen\" }
$logPath = Join-Path $PSScriptRoot "git_remote_list.log"
$debugLogPath = Join-Path $PSScriptRoot "git_remote_debug.log"
$projectsExtractPath = Join-Path $PSScriptRoot "extracted_projects.txt"
$excludedLogPath = Join-Path $PSScriptRoot "excluded_projects.log"

$startTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
Write-Host "開始掃描並導出標準專案清單 (Exclude Private/Fork)..." -ForegroundColor Cyan

# 初始 Log 與導出檔 (清空舊資料)
"--- Git Remote Address List: $startTime ---`n" | Out-File -FilePath $logPath -Encoding utf8
"--- Git Remote Multiple Remotes Debug: $startTime ---`n" | Out-File -FilePath $debugLogPath -Encoding utf8
# extracted_projects.txt 與 excluded_projects.log 直接清空
$null | Out-File -FilePath $projectsExtractPath -Encoding utf8
"--- Excluded Projects Reasons: $startTime ---`n" | Out-File -FilePath $excludedLogPath -Encoding utf8

# 取得所有子目錄
$directories = Get-ChildItem -Path $rootPath -Directory

$repoCount = 0

foreach ($dir in $directories) {
    $gitDir = Join-Path $dir.FullName ".git"
    
    if (Test-Path $gitDir) {
        $repoCount++
        
        # 執行 git remote -v
        $remotes = @(git -C $dir.FullName remote -v 2>$null | Where-Object { $_.Trim() -ne "" })
        
        if ($remotes.Count -eq 2) {
            # 標準兩筆 (Fetch/Push)，寫入標準 Log
            "[$($dir.Name)]`n$($remotes -join "`n")`n" | Out-File -FilePath $logPath -Append -Encoding utf8
            # 解析遠端 URL 以取得 owner/repo (優先看 fetch)
            $fetchLine = $remotes | Where-Object { $_ -match "\(fetch\)" }
            # 修正後的正規表達式：支援 repo 名稱中包含點 (.)
            if ($fetchLine -match '[:/](?<owner>[^:/]+)/(?<repo>.+)\.git') {
                $owner = $Matches['owner']
                $repoName = $Matches['repo']
                $repoFull = "$owner/$repoName"

                # 透過 gh 檢查屬性並排除 Private/Fork
                $repoData = gh repo view $repoFull --json description,isPrivate,isFork 2>$null | ConvertFrom-Json
                if ($null -ne $repoData) {
                    $desc = if ($repoData.description) { $repoData.description } else { "" }
                    $isPrivate = $repoData.isPrivate
                    $isFork = $repoData.isFork
                    $isDone = ($null -ne $desc) -and $desc.Trim().StartsWith("✅")

                    if (-not $isPrivate -and -not $isFork -and -not $isDone) {
                        # 格式: 專案名稱 --public --description "..."
                        $exportLine = "$repoName --public --description `"$desc`""
                        $exportLine | Out-File -FilePath $projectsExtractPath -Append -Encoding utf8
                        
                        # 僅在成功時在畫面上顯示處理資訊與導出狀態
                        Write-Host "處理專案: $($dir.Name)" -ForegroundColor Gray
                        Write-Host "    [DEBUG] Private: $isPrivate, Fork: $isFork, Done: $isDone" -ForegroundColor Gray
                        Write-Host "  [✅ 已導出 extracted_projects.txt] $repoName" -ForegroundColor Green
                    } else {
                        # 排除項目僅記錄到專屬 Log
                        $reason = if($isPrivate){"私有專案 (Private)"}elseif($isFork){"分支專案 (Fork)"}elseif($isDone){"GitHub 描述文字開頭為 ✅ (已完成)"}
                        "[$repoName] -- $reason" | Out-File -FilePath $excludedLogPath -Append -Encoding utf8
                    }
                } else {
                    "[$($dir.Name)] -- 非 GitHub 專案或 API 錯誤 (可能未登入 gh)" | Out-File -FilePath $excludedLogPath -Append -Encoding utf8
                }
                # 稍微延遲避免 GitHub API 速率限制
                Start-Sleep -Milliseconds 100
            } else {
                "[$($dir.Name)] -- 無法解析遠端位址格式" | Out-File -FilePath $excludedLogPath -Append -Encoding utf8
            }
        } elseif ($remotes.Count -gt 2) {
            # 超過兩筆，寫入 Debug Log 並記錄原因
            $reason = "偵測到多個遠端位址 ($($remotes.Count) 筆)"
            "[$($dir.Name)] -- $reason" | Out-File -FilePath $excludedLogPath -Append -Encoding utf8
            "[$($dir.Name)] ($($remotes.Count) 筆)`n$($remotes -join "`n")`n" | Out-File -FilePath $debugLogPath -Append -Encoding utf8
        } else {
            # 0 筆或 1 筆等非標準情況
            $reason = if ($remotes.Count -eq 0) { "無遠端位址" } else { "單一遠端位址 ($($remotes.Count) 筆)" }
            "[$($dir.Name)] -- $reason" | Out-File -FilePath $excludedLogPath -Append -Encoding utf8
            "[$($dir.Name)] ($reason)`n$($remotes -join "`n")`n" | Out-File -FilePath $logPath -Append -Encoding utf8
        }
    }
}

$endTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$summary = "`n--- 掃描完成 ($endTime) ---`n掃描總專案數: $repoCount"

$summary | Out-File -FilePath $logPath -Append -Encoding utf8
$summary | Out-File -FilePath $debugLogPath -Append -Encoding utf8
Write-Host $summary -ForegroundColor Cyan
Write-Host "標準結果: $logPath" -ForegroundColor Yellow
Write-Host "排除結果: $excludedLogPath" -ForegroundColor Gray
Write-Host "異常結果: $debugLogPath" -ForegroundColor Magenta
