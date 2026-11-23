#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Check', 'Install', 'Status', 'Uninstall')]
    [string]$Action = 'Status',
    [switch]$AllowPhysicalPC
)

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$ownerTag = "opencode-windows-autostart (owner: $($identity.User.Value))"
$taskNames = '9router AutoStart', 'OpenCode AutoStart'
$taskPath = '\'

function Assert-PreviewTestMachine {
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem
    # HypervisorPresent alone also matches some physical PCs running Hyper-V or VBS.
    $supported = ($computer.Manufacturer -eq 'Microsoft Corporation' -and $computer.Model -eq 'Virtual Machine') -or
        ($computer.Manufacturer -eq 'VMware, Inc.' -and $computer.Model -like 'VMware*') -or
        ($computer.Manufacturer -in 'innotek GmbH', 'Oracle Corporation' -and $computer.Model -eq 'VirtualBox') -or
        ($computer.Manufacturer -eq 'QEMU' -and $computer.Model -in 'Standard PC (Q35 + ICH9, 2009)', 'Standard PC (i440FX + PIIX, 1996)')
    if (-not $supported -and -not $AllowPhysicalPC) {
        throw 'Use a test VM or explicitly opt into the physical PC beta with Install -AllowPhysicalPC.'
    }

    $listeners = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
    if ($listeners | Where-Object { $_.Port -in 20128, 28894 }) {
        throw 'Port 20128 or 28894 is in use. Exit both apps normally, then rerun Install. No tasks were installed.'
    }
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

    if ($openCode.Source.EndsWith('.cmd', [StringComparison]::OrdinalIgnoreCase) -and $openCode.Source.Contains('%')) {
        throw 'OpenCode paths containing % are not supported by the CMD launcher.'
    }
    $launcher = Join-Path $PSScriptRoot 'Start-Guarded.ps1'
    if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) { throw 'Missing Start-Guarded.ps1.' }
    $powershell = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -LiteralPath $powershell -PathType Leaf)) { throw 'Use Windows PowerShell 5.1 for this installer.' }
    $prefix = '-NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File "{0}"' -f $launcher
    $actions = @{}
    $actions[$taskNames[0]] = New-ScheduledTaskAction -Execute $powershell -WorkingDirectory $env:USERPROFILE `
        -Argument ('{0} -App Router -Executable "{1}" -RouterCli "{2}"' -f $prefix, $node, $routerCli)
    $actions[$taskNames[1]] = New-ScheduledTaskAction -Execute $powershell -WorkingDirectory $env:USERPROFILE `
        -Argument ('{0} -App OpenCode -Executable "{1}"' -f $prefix, $openCode.Source)

    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    $trigger = New-ScheduledTaskTrigger -AtStartup

    if ($Action -eq 'Check') {
        foreach ($name in $taskNames) {
            [pscustomobject]@{
                Task = $name
                Account = $identity.Name
                Trigger = 'AtStartup'
                Executable = $actions[$name].Execute
                Arguments = $actions[$name].Arguments
            }
        }
        return
    }
}

$existing = @{}
Get-ScheduledTask -TaskPath $taskPath | Where-Object { $_.TaskName -in $taskNames } | ForEach-Object {
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
        if ($existing[$name] -and $existing[$name].Description -ne $ownerTag) {
            throw "Task '$name' already exists and is not managed by this installer. It was not changed."
        }
    }
    $targets = @($taskNames | Where-Object { -not $existing[$_] })
} else {
    $targets = @($taskNames | Where-Object { $existing[$_].Description -eq $ownerTag })
}

if ($targets.Count -eq 0) {
    if ($Action -eq 'Install') { Write-Host 'Both autostart tasks are already installed.' }
    else { Write-Host 'No tasks managed by this installer were found.' }
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

Assert-PreviewTestMachine
Write-Warning 'Save your work. Do not use these tasks alongside another autostart for either app or launch another 9router manually while the task is running.'
if ((Read-Host 'Type TEST to confirm you understand the beta limitations') -cne 'TEST') {
    throw 'Cancelled. No tasks were installed.'
}

$secret = Read-Host "Windows password for $($identity.Name) (not your PIN)" -AsSecureString
$created = @()
try {
    if ($secret.Length -eq 0) { throw 'No password entered. No tasks were installed.' }
    $credential = New-Object System.Management.Automation.PSCredential($identity.Name, $secret)
    foreach ($name in $targets) {
        Register-ScheduledTask -TaskName $name -TaskPath $taskPath -Trigger $trigger -Settings $settings `
            -Action $actions[$name] -User $identity.Name -Password ($credential.GetNetworkCredential().Password) `
            -RunLevel Limited -Description $ownerTag | Out-Null
        $created += $name
    }
} catch {
    foreach ($name in $created) {
        $task = Get-ScheduledTask -TaskName $name -TaskPath $taskPath -ErrorAction SilentlyContinue
        if ($task -and $task.Description -eq $ownerTag) {
            try { Unregister-ScheduledTask -TaskName $name -TaskPath $taskPath -Confirm:$false }
            catch { Write-Warning "Could not roll back '$name'. Check Status before retrying." }
        }
    }
    throw
} finally {
    $secret.Dispose()
    Remove-Variable credential -ErrorAction SilentlyContinue
}

Write-Host "Installed: $($created -join ', '). Test on the next Windows restart."
