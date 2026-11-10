# One-time setup for a Windows build machine: flutter build windows needs the MSVC C++ toolchain.
# Run elevated:  powershell -ExecutionPolicy Bypass -File tool\install_windows_toolchain.ps1
$ErrorActionPreference = 'Stop'

$override = @(
    '--wait --quiet --norestart'
    '--add Microsoft.VisualStudio.Workload.VCTools'
    '--add Microsoft.VisualStudio.Component.VC.CMake.Project'
    '--add Microsoft.VisualStudio.Component.Windows11SDK.22621'
    '--includeRecommended'
) -join ' '

winget install --id Microsoft.VisualStudio.2022.BuildTools --exact `
    --accept-package-agreements --accept-source-agreements --override $override

winget install --id JRSoftware.InnoSetup --exact `
    --accept-package-agreements --accept-source-agreements

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ($vs) { Write-Host "MSVC: $vs" } else { Write-Error 'MSVC still missing' }
$iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if ($iscc) { Write-Host "ISCC: $iscc" } else { Write-Warning 'Inno Setup missing' }
