#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Check', 'Install', 'Status', 'Uninstall')]
    [string]$Action = 'Status'
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
    if (-not $supported) {
        throw 'Preview installation is limited to a recognized Windows test VM. Use Check or Status on your main PC.'
    }

    $listeners = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
    if ($listeners | Where-Object { $_.Port -in 20128, 28894 }) {
        throw 'Port 20128 or 28894 is in use. No tasks were installed. Use a clean test VM, without another app instance running.'
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

    $actions = @{}
    $actions[$taskNames[0]] = New-ScheduledTaskAction -Execute $node -WorkingDirectory $env:USERPROFILE `
        -Argument ('"{0}" --no-browser --host 127.0.0.1 --port 20128 --skip-update' -f $routerCli)
    $openCodeArgs = 'serve --service --hostname 127.0.0.1 --port 28894'
    if ($openCode.Source.EndsWith('.cmd', [StringComparison]::OrdinalIgnoreCase)) {
        if ($openCode.Source.Contains('%')) { throw 'OpenCode paths containing % are not supported by the CMD launcher.' }
        $openCodeArgs = '/d /v:off /s /c ""{0}" {1}"' -f $openCode.Source, $openCodeArgs
        $openCodeExe = Join-Path $env:SystemRoot 'System32\cmd.exe'
    } else {
        $openCodeExe = $openCode.Source
    }
    $actions[$taskNames[1]] = New-ScheduledTaskAction -Execute $openCodeExe -WorkingDirectory $env:USERPROFILE `
        -Argument $openCodeArgs

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
Write-Warning 'Use a disposable VM without production app data. Do not run a second copy of either app alongside these tasks.'
if ((Read-Host 'Type TEST to confirm this is a disposable test VM') -cne 'TEST') {
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
