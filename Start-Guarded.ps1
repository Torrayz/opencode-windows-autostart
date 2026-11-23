#Requires -Version 5.1
param(
    [Parameter(Mandatory)]
    [ValidateSet('Router', 'OpenCode')]
    [string]$App,
    [Parameter(Mandatory)]
    [string]$Executable,
    [string]$RouterCli
)

$ErrorActionPreference = 'Stop'
$port = if ($App -eq 'Router') { 20128 } else { 28894 }
$listeners = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
if ($listeners | Where-Object Port -eq $port) {
    Write-Warning "Port $port is already listening. Skipping $App."
    exit 0
}

# A copy using a nondefault port can still share the same application data.
$processes = if ($App -eq 'Router') {
    Get-CimInstance Win32_Process -Filter "Name = 'node.exe' OR Name = 'bun.exe'" |
        Where-Object { $_.CommandLine -match '(?i)(?:^|[\\/"\s])9router(?:[\\/."\s]|$)' }
} else {
    Get-CimInstance Win32_Process -Filter "Name LIKE 'opencode%.exe'"
}
if ($processes) {
    Write-Warning "An existing $App process was detected. Skipping startup."
    exit 0
}

if ($App -eq 'Router') {
    if (-not $RouterCli) { throw 'Missing 9router CLI path.' }
    & $Executable $RouterCli --no-browser --host 127.0.0.1 --port $port --skip-update
} else {
    & $Executable serve --service --hostname 127.0.0.1 --port $port
}
exit $LASTEXITCODE
