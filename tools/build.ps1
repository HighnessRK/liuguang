param([ValidateSet('debug','release')][string]$Mode = 'release', [switch]$Install)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$env:PUB_HOSTED_URL = 'https://pub.dev'
$taskProxy = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
if ($taskProxy.ProxyEnable -eq 1 -and $taskProxy.ProxyServer -match '^([^:;=]+):(\d+)$') {
    $env:GRADLE_OPTS = "-Dhttps.proxyHost=$($Matches[1]) -Dhttps.proxyPort=$($Matches[2]) -Dhttp.proxyHost=$($Matches[1]) -Dhttp.proxyPort=$($Matches[2])"
}
$taskMappedDrive = $null
try {
    Set-Location -LiteralPath $taskRoot
    # gen_snapshot/aapt in the current Windows Flutter SDK require an ASCII path.
    if ($taskRoot -match '[^\x00-\x7F]') {
        foreach ($taskLetter in 76..90) {
            $taskCandidate = "$([char]$taskLetter):"
            if (-not (Test-Path -LiteralPath "$taskCandidate\")) {
                subst.exe $taskCandidate $taskRoot
                if ($LASTEXITCODE -eq 0) { $taskMappedDrive = $taskCandidate; break }
            }
        }
        if (-not $taskMappedDrive) { throw 'No free drive letter for the temporary ASCII build path' }
        Set-Location -LiteralPath "$taskMappedDrive\"
    }
    if ($Mode -eq 'release' -and -not (Test-Path android\key.properties)) {
        python tools\setup_signing.py
        if ($LASTEXITCODE -ne 0) { throw 'Signing setup failed' }
    }
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Package resolution failed' }
    dart analyze lib test integration_test
    if ($LASTEXITCODE -ne 0) { throw 'Analysis failed' }
    flutter test --no-pub --timeout 90s
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed' }
    flutter build apk "--$Mode" --no-pub --target-platform android-arm64
    if ($LASTEXITCODE -ne 0) { throw 'Build failed' }
    if ($Mode -eq 'release') {
        $taskVersion = [regex]::Match((Get-Content pubspec.yaml -Raw), '(?m)^version:\s*([^+\s]+)').Groups[1].Value
        $taskArtifact = "liuguang-v$taskVersion-arm64.apk"
        New-Item -ItemType Directory -Force dist | Out-Null
        Copy-Item -LiteralPath build\app\outputs\flutter-apk\app-release.apk -Destination "dist\$taskArtifact" -Force
        $taskHash = Get-FileHash -LiteralPath "dist\$taskArtifact" -Algorithm SHA256
        "$($taskHash.Hash)  $taskArtifact" | Set-Content -LiteralPath dist\SHA256.txt -Encoding utf8
    }
    if ($Install) {
        $taskInstallApk = (Resolve-Path "build\app\outputs\flutter-apk\app-$Mode.apk").Path
        & (Join-Path $taskRoot 'tools\install.ps1') -Apk $taskInstallApk
    }
} finally {
    Set-Location -LiteralPath $taskRoot
    if ($taskMappedDrive) { subst.exe $taskMappedDrive /d }
}
