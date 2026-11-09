param([string]$Device = '', [switch]$LiveProvider, [switch]$LiveOnly,
      [ValidateRange(0,65535)][int]$ProxyPort = 0,
      [ValidateRange(1,3)][int]$LiveSubmitLimit = 2)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskAdb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
if (-not $Device) {
    $taskDevices = @(& $taskAdb devices | Select-String '^\S+\s+device$')
    if ($taskDevices.Count -ne 1) { throw 'Specify -Device when zero or multiple USB devices are connected' }
    $Device = ($taskDevices[0].Line -split '\s+')[0]
}
$taskCache = Join-Path $taskRoot 'tools\.cache'
New-Item -ItemType Directory -Force $taskCache | Out-Null
$taskFlutter = (Get-Command flutter.bat).Source
$taskLog = Join-Path $taskCache 'device-test-final.log'
$taskJob = Start-Job -ArgumentList $taskRoot,$taskFlutter,$Device,$taskLog,$LiveProvider.IsPresent,$LiveOnly.IsPresent,$ProxyPort,$LiveSubmitLimit -ScriptBlock {
    param($root,$flutter,$device,$log,$live,$liveOnly,$proxyPort,$submitLimit)
    Set-Location -LiteralPath $root
    # The caller supplies an ASCII drive mapping for Flutter's Android tools.
    $env:PUB_HOSTED_URL = 'https://pub.dev'
    $OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    # Flutter defaults to uninstalling the package when integration tests finish.
    # Retain the installed package and its private data on a user's device.
    $testArguments = @('test','--no-pub','--no-uninstall','integration_test/device_test.dart','-d',$device,
        "--dart-define=LIVE_PROVIDER_TEST=$($live.ToString().ToLower())",
        "--dart-define=LIVE_PROXY_PORT=$proxyPort", "--dart-define=LIVE_SUBMIT_LIMIT=$submitLimit")
    if ($liveOnly) { $testArguments += @('--plain-name','live configured provider') }
    & $flutter @testArguments *> $log
    return $LASTEXITCODE
}
$taskConfirmed = $false
try {
    while ($taskJob.State -in @('Running','NotStarted')) {
        if (-not $taskConfirmed) {
            & $taskAdb -s $Device shell uiautomator dump /sdcard/liuguang-install.xml 2>$null | Out-Null
            $taskXml = & $taskAdb -s $Device shell cat /sdcard/liuguang-install.xml 2>$null
            if ($taskXml -and $taskXml.Contains('琉光') -and $taskXml.Contains('USB安装提示')) {
                [xml]$taskUi = $taskXml
                $taskButton = $taskUi.SelectSingleNode("//*[@text='继续安装' and @enabled='true']")
                if ($taskButton -and $taskButton.bounds -match '\[(\d+),(\d+)\]\[(\d+),(\d+)\]') {
                    $taskX = [int](([int]$Matches[1]+[int]$Matches[3])/2)
                    $taskY = [int](([int]$Matches[2]+[int]$Matches[4])/2)
                    & $taskAdb -s $Device shell input tap $taskX $taskY
                    $taskConfirmed = $true
                    Write-Output 'USB installation confirmation accepted.'
                }
            }
        }
        Start-Sleep -Milliseconds 800
    }
    $taskExit = Receive-Job -Job $taskJob -Wait
    Get-Content -LiteralPath $taskLog -Tail 18
    if ($taskJob.State -eq 'Failed' -or $taskExit -ne 0) { throw 'Device integration test failed' }
} finally {
    Remove-Job -Job $taskJob -Force
}
