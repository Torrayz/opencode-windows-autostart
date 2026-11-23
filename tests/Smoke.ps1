#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$installer = Join-Path (Split-Path $PSScriptRoot -Parent) 'Autostart.ps1'
$definitions = @(& $installer Check)
if ($definitions.Count -ne 2 -or @($definitions | Where-Object {
    $_.Trigger -ne 'AtStartup' -or $_.Arguments -notmatch 'Start-Guarded\.ps1'
}).Count -ne 0) {
    throw 'Expected two guarded boot tasks.'
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
                -App $app -Executable $missing -RouterCli $missing | Out-String
            if ($LASTEXITCODE -ne 0 -or $output -notmatch 'already listening') {
                throw "$app boot guard did not skip a busy port."
            }
        } finally {
            if ($socket) { $socket.Stop() }
        }
    }
}

& {
    function Get-ScheduledTask { param($TaskPath) }
    function Register-ScheduledTask { throw 'Install -WhatIf tried to register a task.' }
    $status = @(& $installer Status)
    if ($status.Count -ne 2 -or @($status | Where-Object State -ne 'Not installed').Count -ne 0) {
        throw 'Expected both missing tasks to be reported.'
    }
    & $installer Install -WhatIf
}

& {
    function Get-ScheduledTask {
        param($TaskPath)
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

& {
    $source = Get-Content -LiteralPath $installer -Raw
    $ast = [scriptblock]::Create($source).Ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Assert-PreviewTestMachine'
    }, $false)
    . ([scriptblock]::Create($ast.Extent.Text))
    function Get-CimInstance {
        param($ClassName)
        [pscustomobject]@{ Manufacturer = 'Dell Inc.'; Model = 'Latitude'; HypervisorPresent = $true }
    }
    try {
        Assert-PreviewTestMachine
        throw 'Preview machine check accepted a physical PC.'
    } catch {
        if ($_.Exception.Message -notlike '*opt into the physical PC beta*') { throw }
    }

    function Get-CimInstance {
        param($ClassName)
        [pscustomobject]@{ Manufacturer = 'Microsoft Corporation'; Model = 'Virtual Machine' }
    }
    $network = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
    $listener = $null
    try {
        if (-not ($network.GetActiveTcpListeners() | Where-Object { $_.Port -in 20128, 28894 })) {
            Assert-PreviewTestMachine
            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 20128)
            $listener.Start()
        }
        try {
            Assert-PreviewTestMachine
            throw 'Preview machine check accepted an occupied port.'
        } catch {
            if ($_.Exception.Message -notlike '*port*in use*') { throw }
        }
    } finally {
        if ($listener) { $listener.Stop() }
    }
}

Write-Host 'Smoke test passed. No tasks were changed.'
