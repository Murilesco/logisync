# LogiSync - Windows installer
# Installs the Python dependencies, copies the agent to %LOCALAPPDATA%\LogiSync and
# registers a logon task that runs it hidden (pythonw).
#
#   powershell -ExecutionPolicy Bypass -File install-windows.ps1 [-Keyboard K950] [-Mouse "MX Anywhere"] [-Channel 2]
#   powershell -ExecutionPolicy Bypass -File install-windows.ps1 -Uninstall
param(
    [string]$Keyboard,
    [string]$Mouse,
    [int]$Channel,
    [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'
$dir = "$env:LOCALAPPDATA\LogiSync"

Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe'" |
    Where-Object { $_.CommandLine -match 'logisync|logi_sync' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Unregister-ScheduledTask -TaskName 'LogiSync' -Confirm:$false -ErrorAction SilentlyContinue
if ($Uninstall) { Write-Host 'LogiSync removed.'; return }

$py = (Get-Command python -ErrorAction Stop).Source
$pyw = Join-Path (Split-Path $py) 'pythonw.exe'
& $py -m pip install --quiet --upgrade hidapi winrt-runtime winrt-Windows.Devices.Bluetooth winrt-Windows.Foundation

New-Item -ItemType Directory -Force $dir | Out-Null
Copy-Item -Recurse -Force "$PSScriptRoot\logisync" $dir

$cfgPath = "$dir\config.json"
$cfg = if (Test-Path $cfgPath) { Get-Content $cfgPath -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
foreach ($kv in @{ keyboard = $Keyboard; mouse = $Mouse; target_channel = $Channel }.GetEnumerator()) {
    if ($kv.Value) { $cfg | Add-Member -Force -NotePropertyName $kv.Key -NotePropertyValue $kv.Value }
}
$cfg | ConvertTo-Json | Set-Content $cfgPath -Encoding utf8

$act = New-ScheduledTaskAction -Execute $pyw -Argument '-m logisync' -WorkingDirectory $dir
$trg = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName 'LogiSync' -Action $act -Trigger $trg -Settings $set `
    -Description 'LogiSync: the mouse follows the keyboard Easy-Switch' -Force | Out-Null
Start-ScheduledTask -TaskName 'LogiSync'
Start-Sleep 4
Get-Content "$dir\logisync.log" -Tail 3 -ErrorAction SilentlyContinue
Write-Host "Installed. Config: $cfgPath"
