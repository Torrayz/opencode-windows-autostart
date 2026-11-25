#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$installer = Join-Path (Split-Path $PSScriptRoot -Parent) 'Autostart.ps1'
$definitions = @(& $installer Check)
if ($definitions.Count -ne 2 -or @($definitions | Where-Object {
    $_.LogonType -ne 'S4U' -or
    $_.Trigger -ne 'AtStartup, AtLogOn, OnNetworkConnect' -or
    $_.Arguments -notmatch 'Start-Guarded\.ps1'
}).Count -ne 0) {
    throw 'Expected two guarded S4U tasks with startup, logon, and network triggers.'
}
if ($definitions[0].RecoveryInterval -ne 'PT2M' -or $definitions[1].RecoveryInterval) {
    throw 'Expected a two-minute recovery trigger for 9router only.'
}
if ($definitions[0].Arguments -notmatch ' -App Router ' -or
    $definitions[1].Arguments -notmatch ' -App OpenCode ') {
    throw 'Wrong app arguments for guarded boot tasks.'
}

& {
    $launcher = Join-Path (Split-Path $installer -Parent) 'Start-Guarded.ps1'
    $missing = Join-Path $PSScriptRoot 'does-not-exist.exe'
    $ports = @{ Router = 20128; OpenCode = 28894 }
    $network = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
    foreach ($app in 'Router', 'OpenCode') {
        $port = $ports[$app]
        $socket = $null
        try {
            if (-not ($network.GetActiveTcpListeners() | Where-Object Port -eq $port)) {
                $socket = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
                $socket.Start()
            }
            $output = & (Join-Path $PSHOME 'powershell.exe') -NoProfile -NonInteractive -File $launcher `
                -App $app -Executable $missing -RouterCli $missing 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0 -or $output -notmatch 'already listening') {
                throw "$app boot guard did not skip a busy port."
            }
        } finally {
            if ($socket) { $socket.Stop() }
        }
    }
}

& {
    function Get-ScheduledTask { param($TaskPath, $ErrorAction) }
    function Register-ScheduledTask { throw 'Install -WhatIf tried to register a task.' }
    $status = @(& $installer Status)
    if ($status.Count -ne 2 -or @($status | Where-Object State -ne 'Not installed').Count -ne 0) {
        throw 'Expected both missing tasks to be reported.'
    }
    & $installer Install -WhatIf
}

& {
    $userShort = [Security.Principal.WindowsIdentity]::GetCurrent().Name.Split('\')[-1]
    function Get-ScheduledTask {
        param($TaskPath, $ErrorAction)
        [pscustomobject]@{
            TaskName = '9router AutoStart'
            Description = "Windows-Autostart for ${userShort}: start local apps at Windows boot."
        }
    }
    function Register-ScheduledTask { throw 'Legacy upgrade -WhatIf tried to register a task.' }
    & $installer Install -WhatIf
}

& {
    function Get-ScheduledTask {
        param($TaskPath, $ErrorAction)
        [pscustomobject]@{ TaskName = '9router AutoStart'; Description = 'Existing installer' }
    }
    function Register-ScheduledTask { throw 'Install attempted to overwrite a task.' }
    function Unregister-ScheduledTask { throw 'Uninstall attempted to remove an unmanaged task.' }
    try {
        & $installer Install -WhatIf
        throw 'Install did not detect an unmanaged task.'
    } catch {
        if ($_.Exception.Message -notlike '*already exists and is not managed*') { throw }
    }
    & $installer Uninstall
}

Write-Host 'Smoke test passed. No tasks were changed.'
