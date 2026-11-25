#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Check', 'Install', 'Status', 'Uninstall')]
    [string]$Action = 'Status',
    [switch]$AllowPhysicalPC,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$userShort = $identity.Name.Split('\')[-1]
$ownerTag = "opencode-windows-autostart (owner: $($identity.User.Value))"
$managedTags = @(
    $ownerTag,
    "Windows-Autostart for ${userShort}: start local apps at Windows boot."
)
$taskNames = '9router AutoStart', 'OpenCode AutoStart'
$taskPath = '\'

function New-AutostartTriggers {
    param(
        [Parameter(Mandatory)][string]$UserId,
        [Parameter(Mandatory)][int]$BootDelaySeconds,
        [Parameter(Mandatory)][int]$LogonDelaySeconds,
        [Parameter(Mandatory)][int]$NetworkDelaySeconds
    )

    $bootTrigger = New-ScheduledTaskTrigger -AtStartup
    $bootTrigger.Delay = "PT${BootDelaySeconds}S"

    $logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $UserId
    $logonTrigger.Delay = "PT${LogonDelaySeconds}S"

    $list = @($bootTrigger, $logonTrigger)

    $evtClass = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler -ErrorAction SilentlyContinue
    if ($evtClass) {
        $evtTrigger = New-CimInstance -CimClass $evtClass -ClientOnly
        $evtTrigger.Enabled = $true
        $evtTrigger.Delay = "PT${NetworkDelaySeconds}S"
        $evtTrigger.Subscription = '<QueryList><Query Id="0" Path="Microsoft-Windows-NetworkProfile/Operational"><Select Path="Microsoft-Windows-NetworkProfile/Operational">*[System[Provider[@Name=''Microsoft-Windows-NetworkProfile''] and EventID=10000]]</Select></Query></QueryList>'
        $list += $evtTrigger
    }

    return $list
}

if ($Action -in 'Check', 'Install') {
    $node = (Get-Command node.exe -CommandType Application).Source
    $routerShim = (Get-Command 9router.cmd -CommandType Application).Source
    $routerCli = Join-Path (Split-Path $routerShim -Parent) 'node_modules\9router\cli.js'
    if (-not (Test-Path -LiteralPath $routerCli -PathType Leaf)) {
        throw 'Cannot find the 9router npm package next to 9router.cmd. Check your global npm installation.'
    }

    $openCode = Get-Command opencode.exe, opencode.cmd -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $openCode) { throw 'OpenCode was not found on PATH. Install OpenCode V2, then open a new PowerShell window.' }

    $openCodeExe = $openCode.Source
    if ($openCodeExe.EndsWith('.cmd', [StringComparison]::OrdinalIgnoreCase)) {
        $directExe = Join-Path (Split-Path $openCodeExe -Parent) 'node_modules\@opencode\cli\bin\opencode.exe'
        if (Test-Path -LiteralPath $directExe -PathType Leaf) {
            $openCodeExe = $directExe
        } elseif ($openCodeExe.Contains('%')) {
            throw 'OpenCode paths containing % are not supported by the CMD launcher.'
        }
    }

    $launcher = Join-Path $PSScriptRoot 'Start-Guarded.ps1'
    if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) { throw 'Missing Start-Guarded.ps1.' }
    $powershell = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -LiteralPath $powershell -PathType Leaf)) { throw 'Use Windows PowerShell 5.1 for this installer.' }
    $prefix = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File "{0}"' -f $launcher

    $actions = @{}
    $actions[$taskNames[0]] = New-ScheduledTaskAction -Execute $powershell -WorkingDirectory $env:USERPROFILE `
        -Argument ('{0} -App Router -Executable "{1}" -RouterCli "{2}"' -f $prefix, $node, $routerCli)
    $actions[$taskNames[1]] = New-ScheduledTaskAction -Execute $powershell -WorkingDirectory $env:USERPROFILE `
        -Argument ('{0} -App OpenCode -Executable "{1}"' -f $prefix, $openCodeExe)

    $triggers = @{}
    $triggers[$taskNames[0]] = New-AutostartTriggers -UserId $identity.Name -BootDelaySeconds 5 -LogonDelaySeconds 3 -NetworkDelaySeconds 2
    # IgnoreNew makes this a scheduler-only tick while the managed server runs.
    $triggers[$taskNames[0]] += New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Minutes 2)
    $triggers[$taskNames[1]] = New-AutostartTriggers -UserId $identity.Name -BootDelaySeconds 10 -LogonDelaySeconds 6 -NetworkDelaySeconds 5

    $settings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -DontStopOnIdleEnd `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -RestartCount 5 `
        -RestartInterval (New-TimeSpan -Minutes 1)

    $taskPrincipal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType S4U -RunLevel Limited

    if ($Action -eq 'Check') {
        foreach ($name in $taskNames) {
            [pscustomobject]@{
                Task = $name
                Account = $identity.Name
                LogonType = 'S4U'
                Trigger = 'AtStartup, AtLogOn, OnNetworkConnect'
                RecoveryInterval = ($triggers[$name] | ForEach-Object { $_.Repetition.Interval } | Where-Object { $_ })
                Executable = $actions[$name].Execute
                Arguments = $actions[$name].Arguments
            }
        }
        return
    }
}

$existing = @{}
Get-ScheduledTask -TaskPath $taskPath -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -in $taskNames } | ForEach-Object {
    $existing[$_.TaskName] = $_
}

if ($Action -eq 'Status') {
    foreach ($name in $taskNames) {
        $task = $existing[$name]
        $info = if ($task) { Get-ScheduledTaskInfo -InputObject $task }
        [pscustomobject]@{
            Task = $name
            State = $(if ($task) { $task.State } else { 'Not installed' })
            Managed = [bool]($task -and $task.Description -eq $ownerTag)
            LastRun = $(if ($info -and $info.LastTaskResult -ne 0x00041303) { $info.LastRunTime })
            LastResult = $(if ($info) { '0x{0:X8}' -f $info.LastTaskResult })
        }
    }
    return
}

if ($Action -eq 'Install') {
    foreach ($name in $taskNames) {
        if ($existing[$name] -and ($existing[$name].Description -notin $managedTags) -and -not $Force) {
            throw "Task '$name' already exists and is not managed by this installer. It was not changed."
        }
    }
    $targets = @($taskNames)
} else {
    $targets = @($taskNames | Where-Object { $existing[$_] -and ($existing[$_].Description -in $managedTags) })
}

if ($targets.Count -eq 0) {
    Write-Host 'No tasks managed by this installer were found.'
    return
}
if (-not $PSCmdlet.ShouldProcess(($targets -join ', '), $Action)) { return }

$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Open PowerShell as Administrator under your own Windows account, then try again.'
}

if ($Action -eq 'Uninstall') {
    foreach ($name in $targets) {
        Unregister-ScheduledTask -TaskName $name -TaskPath $taskPath -Confirm:$false
        Write-Host "Removed: $name"
    }
    return
}

$updated = @()
foreach ($name in $targets) {
    Register-ScheduledTask -TaskName $name -TaskPath $taskPath `
        -Action $actions[$name] `
        -Trigger $triggers[$name] `
        -Settings $settings `
        -Principal $taskPrincipal `
        -Description $ownerTag `
        -Force | Out-Null
    $updated += $name
}

# Start any task whose target port is not yet listening so it comes online immediately.
$activePorts = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners().Port
$taskPorts = @{
    '9router AutoStart'  = 20128
    'OpenCode AutoStart' = 28894
}
foreach ($name in $updated) {
    $port = $taskPorts[$name]
    if ($activePorts -notcontains $port) {
        Start-ScheduledTask -TaskName $name -TaskPath $taskPath
    }
}

Write-Host "Installed: $($updated -join ', '). Active at boot, sign-in, and network connect."
