# Build the Windows release, then emit a portable zip and, with -Installer, a setup.exe.
#   powershell -ExecutionPolicy Bypass -File tool\package_windows.ps1 -Installer
param([switch]$Installer)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere) -or
    -not (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)) {
    throw 'MSVC C++ toolchain missing - run tool\install_windows_toolchain.ps1 elevated first.'
}

flutter build windows --release
if ($LASTEXITCODE) { throw 'flutter build windows failed' }

$rel = (Resolve-Path 'build\windows\x64\runner\Release').Path
$ver = ((Select-String -Path 'pubspec.yaml' -Pattern '^version: ').Line -split '\+')[0].Substring(9)
$repoRoot = (Resolve-Path (Join-Path (Get-Location) '..')).Path
$dist = Join-Path (Get-Location) 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null

# 许可与第三方声明随包分发
Copy-Item (Join-Path $repoRoot 'LICENSE') (Join-Path $rel 'LICENSE') -Force
Copy-Item (Join-Path $repoRoot 'THIRD_PARTY_NOTICES.md') (Join-Path $rel 'THIRD_PARTY_NOTICES.md') -Force

$zip = Join-Path $dist "eNode-$ver-win-x64.zip"
Remove-Item $zip -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $rel '*') -DestinationPath $zip
Write-Host "portable  -> $zip  ($([math]::Round((Get-Item $zip).Length / 1MB, 1)) MB)"

if ($Installer) {
    $iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe") |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $iscc) { throw 'Inno Setup missing - winget install JRSoftware.InnoSetup' }
    & $iscc "/DAppVersion=$ver" "/DBuildDir=$rel" "/DOutDir=$dist" `
        "/DIcoFile=$(Join-Path (Get-Location) 'windows\runner\resources\app_icon.ico')" `
        (Join-Path $PSScriptRoot 'enode.iss')
    if ($LASTEXITCODE) { throw 'ISCC failed' }
    Write-Host "installer -> $(Join-Path $dist "eNode-$ver-win-x64-setup.exe")"
}
