param(
    [switch]$Zip
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$posApp = Join-Path $repoRoot 'apps\pos_app'
$releaseDir = Join-Path $posApp 'build\windows\x64\runner\Release'
$exePath = Join-Path $releaseDir 'FoodCityPOS.exe'
$zipPath = Join-Path $repoRoot 'dist\FoodCityPOS-windows-x64.zip'
$windowsBuildDir = Join-Path $posApp 'build\windows\x64'

Push-Location $posApp
try {
    $cmakeCache = Join-Path $windowsBuildDir 'CMakeCache.txt'
    $cmakeFiles = Join-Path $windowsBuildDir 'CMakeFiles'

    if (Test-Path $cmakeCache) {
        Remove-Item $cmakeCache -Force
    }

    if (Test-Path $cmakeFiles) {
        Remove-Item $cmakeFiles -Recurse -Force
    }

    flutter pub get
    flutter build windows --release
}
finally {
    Pop-Location
}

if (-not (Test-Path $exePath)) {
    throw "Expected executable was not created: $exePath"
}

Write-Host "Windows app built successfully: $exePath"
Write-Host "Copy the whole Release folder to the POS computer, not only the .exe file."

if ($Zip) {
    New-Item -ItemType Directory -Force (Split-Path -Parent $zipPath) | Out-Null
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }
    Compress-Archive -Path (Join-Path $releaseDir '*') -DestinationPath $zipPath
    Write-Host "Zip package created: $zipPath"
}

