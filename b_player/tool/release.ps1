# eNode 一键发布：改版本 → 提交 main → 同步公开仓 → 推 tag → GitHub Actions 构建并发布 Release
#
# 双击仓库根目录的 release.bat，按提示操作即可。构建在 GitHub 上进行，本机不需要编译。
# 可选参数：
#   -DryRun           只打印计划，不改文件、不提交、不推送
#   -Version 1.4.1+4  直接指定版本号（省略构建号时自动取当前构建号 +1）
#
# 首次使用前需在公开仓添加 ANDROID_KEYSTORE_B64 Secret，见 README「一键发布」。
param(
    [string]$Version,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

try {
    if ([Console]::OutputEncoding.WebName -ne 'utf-8') {
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    }
} catch {}

$bpDir = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $bpDir
$publicRepo = 'codeforenode/enode'
$publicUrl = "https://github.com/$publicRepo"
$actionsUrl = "$publicUrl/actions/workflows/release.yml"
$publicName = 'gytangyao'
$publicMail = 'gytangyao@users.noreply.github.com'

function Show-Step([string]$Text) {
    Write-Host "`n=== $Text ===" -ForegroundColor Cyan
}

function Show-Info([string]$Text) { Write-Host $Text }
function Show-Warn([string]$Text) { Write-Host $Text -ForegroundColor Yellow }

function Read-Confirm {
    param([string]$Question, [bool]$DefaultYes = $true)
    $hint = if ($DefaultYes) { '[Y/n]' } else { '[y/N]' }
    $answer = Read-Host "$Question $hint"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $DefaultYes }
    return $answer.Trim() -match '^(y|yes|是|好|确认)$'
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)][string[]]$GitArgs,
        [switch]$AllowFail
    )
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $output = & git @GitArgs 2> $errFile
        $code = $LASTEXITCODE
        $errors = @()
        if (Test-Path -LiteralPath $errFile) {
            $errors = @(Get-Content -LiteralPath $errFile | Where-Object { $_ })
        }
    } finally {
        $ErrorActionPreference = $previous
        Remove-Item -LiteralPath $errFile -ErrorAction SilentlyContinue
    }
    $lines = @($output | ForEach-Object { "$_" })
    if ($code -ne 0 -and -not $AllowFail) {
        $detail = @($lines + $errors) -join "`n"
        throw ("git " + ($GitArgs -join ' ') + " 执行失败（退出码 $code）：`n" + $detail)
    }
    return $lines
}

function ConvertTo-VersionParts {
    param([string]$Raw)
    $match = [regex]::Match($Raw, '^(\d+)\.(\d+)\.(\d+)\+(\d+)$')
    if (-not $match.Success) { return $null }
    return @(
        [int]$match.Groups[1].Value,
        [int]$match.Groups[2].Value,
        [int]$match.Groups[3].Value,
        [int]$match.Groups[4].Value
    )
}

function Compare-VersionName {
    param([int[]]$Left, [int[]]$Right)
    for ($i = 0; $i -lt 3; $i++) {
        if ($Left[$i] -ne $Right[$i]) {
            if ($Left[$i] -gt $Right[$i]) { return 1 }
            return -1
        }
    }
    return 0
}

function Get-NextVersion([int[]]$Parts) {
    return ('{0}.{1}.{2}+{3}' -f $Parts[0], $Parts[1], ($Parts[2] + 1), ($Parts[3] + 1))
}

$versionBumped = $false
$committed = $false

try {
    Show-Step '读取当前版本'
    $pubspecPath = Join-Path $bpDir 'pubspec.yaml'
    $pubspecText = [System.IO.File]::ReadAllText($pubspecPath)
    $versionMatch = [regex]::Match($pubspecText, '(?m)^version:\s*([^\r\n#]+)')
    if (-not $versionMatch.Success) { throw 'pubspec.yaml 里找不到 version 行。' }
    $current = $versionMatch.Groups[1].Value.Trim()
    $currentParts = ConvertTo-VersionParts $current
    if (-not $currentParts) { throw "pubspec.yaml 的版本号 '$current' 不是 A.B.C+N 格式。" }
    Show-Info "  当前版本：$current"

    if ([string]::IsNullOrWhiteSpace($Version)) {
        $suggest = Get-NextVersion $currentParts
        $typed = Read-Host "要发布的版本号（直接回车 = $suggest）"
        if ([string]::IsNullOrWhiteSpace($typed)) { $Version = $suggest } else { $Version = $typed.Trim() }
    }
    $Version = $Version.Trim().TrimStart([char[]]'vV')
    if ($Version -match '^\d+\.\d+\.\d+$') {
        $Version = "$Version+$($currentParts[3] + 1)"
    }
    $targetParts = ConvertTo-VersionParts $Version
    if (-not $targetParts) {
        throw "版本号 '$Version' 格式不对，应为 1.4.1+4（版本名 + 构建号）。"
    }
    $targetName = '{0}.{1}.{2}' -f $targetParts[0], $targetParts[1], $targetParts[2]
    $tagName = "v$targetName"
    $sameVersion = ($Version -eq $current)

    $nameCmp = Compare-VersionName $targetParts $currentParts
    if ($nameCmp -lt 0) {
        throw "新版本 $Version 不能低于当前版本 $current。"
    }
    if ($nameCmp -eq 0 -and $targetParts[3] -ne $currentParts[3]) {
        throw "版本名没变但构建号变了。应用内检查更新只比较版本名，请同时提升版本名，例如 $(Get-NextVersion $currentParts)。"
    }
    if ($nameCmp -gt 0 -and $targetParts[3] -le $currentParts[3]) {
        throw "构建号必须大于当前的 $($currentParts[3])，否则 Android 不会把它当成升级包。"
    }
    if ($sameVersion) {
        Show-Warn "  版本号与当前一致（$current），将按当前代码发布；若代码有改动，建议提升版本号。"
    }

    Show-Step '检查仓库状态'
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw '找不到 git 命令。' }

    $branch = @(Invoke-Git @('-C', $repoRoot, 'rev-parse', '--abbrev-ref', 'HEAD') | Where-Object { $_ })[0].Trim()
    if ($branch -ne 'main') {
        throw "当前分支是 $branch，发布脚本只在 main 上运行。请先切回 main。"
    }
    $remotes = @(Invoke-Git @('-C', $repoRoot, 'remote') | Where-Object { $_ })
    if ($remotes -notcontains 'public') {
        throw "缺少 public 远端。先执行：git remote add public https://github.com/$publicRepo.git"
    }
    $unmerged = @(Invoke-Git @('-C', $repoRoot, 'diff', '--name-only', '--diff-filter=U') | Where-Object { $_ })
    if ($unmerged.Count -gt 0) {
        throw '存在未解决的合并冲突，先处理完再发布。'
    }

    $changes = @(Invoke-Git @('-C', $repoRoot, 'status', '--porcelain') | Where-Object { $_ -and $_.Trim() })
    if ($changes.Count -gt 0) {
        Show-Warn "  工作区有 $($changes.Count) 项未提交的改动，会一起提交并公开到公开仓："
        $changes | Select-Object -First 30 | ForEach-Object { Show-Info "    $_" }
        if ($changes.Count -gt 30) {
            Show-Info "    ...（其余 $($changes.Count - 30) 项）"
        }
    } else {
        Show-Info '  工作区干净。'
    }

    if (-not $DryRun) {
        Show-Step '同步公开仓'
        try {
            Invoke-Git @('-C', $repoRoot, 'fetch', 'public', 'main') | Out-Null
        } catch {
            throw "无法连接公开仓 GitHub（$publicRepo），请检查网络或代理后重试。`n$($_.Exception.Message)"
        }
        $remoteTags = @(Invoke-Git @('-C', $repoRoot, 'ls-remote', '--tags', 'public', "refs/tags/$tagName") | Where-Object { $_ })
        if ($remoteTags.Count -gt 0) {
            throw "公开仓已有标签 $tagName。若只是构建失败，请到 Actions 页点 Re-run；要改代码请提升版本号再发布。"
        }
        $localTags = @(Invoke-Git @('-C', $repoRoot, 'tag', '--list', $tagName) | Where-Object { $_ })
        if ($localTags.Count -gt 0) {
            Invoke-Git @('-C', $repoRoot, 'tag', '-d', $tagName) | Out-Null
            Show-Warn "  删除了上次未推送完成的本地标签 $tagName"
        }
        Show-Info '  公开仓没有同名标签，可以发布。'
    }

    Show-Step '发布计划'
    Show-Info "  版本：$current → $Version"
    Show-Info '  构建：GitHub Actions（Windows 安装版/便携版 + Android APK）'
    Show-Info "  公开仓：$publicRepo"
    Show-Info "  公开标签：$tagName"

    if ($DryRun) {
        Show-Step 'DryRun 结束'
        Show-Info '  未修改版本号、未提交、未推送、未打开浏览器。'
        Show-Info '  去掉 -DryRun 即可真正发布。'
        exit 0
    }

    if (-not (Read-Confirm '开始发布？')) {
        Show-Info '已取消，没有做任何改动。'
        exit 0
    }

    Show-Step "写入版本号 $Version"
    if (-not $sameVersion) {
        $newText = [regex]::Replace($pubspecText, '(?m)^version:[^\r\n]*', "version: $Version")
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($pubspecPath, $newText, $utf8NoBom)
        $versionBumped = $true
        Show-Info '  已更新 pubspec.yaml'
    } else {
        Show-Info '  版本号未变，跳过。'
    }

    Show-Step '提交到 main'
    Invoke-Git @('-C', $repoRoot, 'add', '-A') | Out-Null
    $staged = @(Invoke-Git @('-C', $repoRoot, 'diff', '--cached', '--name-only') | Where-Object { $_ })
    if ($staged.Count -gt 0) {
        $identity = @()
        $lastAuthor = @(Invoke-Git @('-C', $repoRoot, 'log', '-1', '--format=%an%n%ae', 'main') | Where-Object { $_ })
        if ($lastAuthor.Count -ge 2) {
            $identity = @('-c', "user.name=$($lastAuthor[0])", '-c', "user.email=$($lastAuthor[1])")
        }
        $commitArgs = @('-C', $repoRoot) + $identity + @('commit', '-m', "release: $tagName")
        Invoke-Git -GitArgs $commitArgs | Out-Null
        $committed = $true
        Show-Info "  已提交 $($staged.Count) 个文件。"
    } else {
        Show-Info '  没有新的改动，跳过提交。'
    }

    Show-Step '推送到私有仓 origin'
    Invoke-Git @('-C', $repoRoot, 'push', 'origin', 'main') | Out-Null
    Show-Info '  origin main 已同步。'

    Show-Step "同步公开仓 $publicRepo"
    $tmp = Join-Path $env:TEMP ('enode-release-' + [guid]::NewGuid().ToString('N'))
    $worktreeAdded = $false
    try {
        Invoke-Git @('-C', $repoRoot, 'worktree', 'add', '--detach', $tmp, 'public/main') | Out-Null
        $worktreeAdded = $true
        Invoke-Git @('-C', $tmp, 'read-tree', '-u', '--reset', 'main') | Out-Null
        Invoke-Git @('-C', $tmp, 'add', '-A') | Out-Null

        $mismatch = @(Invoke-Git @('-C', $tmp, 'diff', '--cached', '--name-only', 'main') | Where-Object { $_ })
        if ($mismatch.Count -gt 0) {
            throw '公开仓导出校验失败：临时工作区的索引与 main 不一致。'
        }

        $pending = @(Invoke-Git @('-C', $tmp, 'diff', '--cached', '--name-only', 'public/main') | Where-Object { $_ })
        if ($pending.Count -gt 0) {
            Invoke-Git @('-C', $tmp, '-c', "user.name=$publicName", '-c', "user.email=$publicMail", 'commit', '-m', "release: $tagName") | Out-Null
            Invoke-Git @('-C', $tmp, 'push', 'public', 'HEAD:main') | Out-Null
            Show-Info "  公开仓 main 已更新（$($pending.Count) 个文件）。"
        } else {
            Show-Info '  公开仓内容已一致，跳过提交。'
        }

        $exportTags = @(Invoke-Git @('-C', $tmp, 'tag', '--list', $tagName) | Where-Object { $_ })
        if ($exportTags.Count -eq 0) {
            Invoke-Git @('-C', $tmp, '-c', "user.name=$publicName", '-c', "user.email=$publicMail", 'tag', '-a', $tagName, '-m', "eNode $targetName") | Out-Null
        }
        Invoke-Git @('-C', $tmp, 'push', 'public', "refs/tags/$tagName") | Out-Null
        Show-Info "  标签 $tagName 已推送。"
    } finally {
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            if ($worktreeAdded) {
                & git -C $repoRoot worktree remove --force $tmp *> $null
            }
            if (Test-Path $tmp) {
                Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            }
            & git -C $repoRoot worktree prune *> $null
        } finally {
            $ErrorActionPreference = $previous
        }
    }

    Show-Step '已触发 GitHub 构建'
    Show-Info "  Actions：$actionsUrl"
    Show-Info "  Release：$publicUrl/releases/tag/$tagName"
    Show-Info '  通常 20-30 分钟；成功后三个安装包会自动出现在 Release 里。'
    Show-Warn '  若构建失败：看 Actions 日志修代码，然后提升版本号重新发布；同一个标签不要复用。'
    Show-Warn '  Android 首次构建需要公开仓已添加 ANDROID_KEYSTORE_B64 Secret（见 README）。'
    Start-Process $actionsUrl
    exit 0
} catch {
    Show-Warn ''
    Show-Warn "发布中止：$($_.Exception.Message)"
    if ($versionBumped -and -not $committed) {
        [System.IO.File]::WriteAllText($pubspecPath, $pubspecText, (New-Object System.Text.UTF8Encoding($false)))
        Show-Warn '已还原 pubspec.yaml 的版本号。'
    }
    Show-Warn '修复上面的问题后重新运行 release.bat。'
    exit 1
}
