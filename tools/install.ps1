param([string]$Apk = '', [string]$Device = '')
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
if (-not $Apk) {
    $taskVersion = [regex]::Match((Get-Content (Join-Path $taskRoot 'pubspec.yaml') -Raw), '(?m)^version:\s*([^+\s]+)').Groups[1].Value
    $Apk = "dist\liuguang-v$taskVersion-arm64.apk"
}
$taskAdb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
if (-not $Device) {
    $taskDevices = @(& $taskAdb devices | Select-String '^\S+\s+device$')
    if ($taskDevices.Count -ne 1) { throw 'Specify -Device when zero or multiple USB devices are connected' }
    $Device = ($taskDevices[0].Line -split '\s+')[0]
}
$taskApk = if ([IO.Path]::IsPathRooted($Apk)) { $Apk } else { Join-Path $taskRoot $Apk }
$taskCache = Join-Path $taskRoot 'tools\.cache'
New-Item -ItemType Directory -Force $taskCache | Out-Null
$taskOutput = Join-Path $taskCache 'install-output.txt'
$taskError = Join-Path $taskCache 'install-error.txt'
$taskProcess = Start-Process -FilePath $taskAdb -ArgumentList @('-s',$Device,'install','-r',$taskApk) -WindowStyle Hidden -RedirectStandardOutput $taskOutput -RedirectStandardError $taskError -PassThru
for ($taskAttempt=0; $taskAttempt -lt 4; $taskAttempt++) {
    Start-Sleep -Milliseconds 600
    if ($taskProcess.HasExited) { break }
    & $taskAdb -s $Device shell uiautomator dump /sdcard/liuguang-install.xml | Out-Null
    $taskXmlPath = Join-Path $taskCache 'install-screen.xml'
    & $taskAdb -s $Device pull /sdcard/liuguang-install.xml $taskXmlPath 2>$null | Out-Null
    [xml]$taskUi = Get-Content -LiteralPath $taskXmlPath -Raw
    if ($taskUi.OuterXml.Contains('琉光') -and $taskUi.OuterXml.Contains('USB安装提示')) {
        $taskButton = $taskUi.SelectSingleNode("//*[@text='继续安装' and @enabled='true']")
        if ($taskButton -and $taskButton.bounds -match '\[(\d+),(\d+)\]\[(\d+),(\d+)\]') {
            $taskX = [int](([int]$Matches[1]+[int]$Matches[3])/2)
            $taskY = [int](([int]$Matches[2]+[int]$Matches[4])/2)
            & $taskAdb -s $Device shell input tap $taskX $taskY
            break
        }
    }
}
if (-not $taskProcess.WaitForExit(30000)) { throw 'Installation timed out' }
Get-Content -LiteralPath $taskOutput
$taskErrors = Get-Content -LiteralPath $taskError -Raw
if ($taskErrors) { Write-Output $taskErrors }
if ($taskProcess.ExitCode -ne 0) { throw 'Installation failed' }
