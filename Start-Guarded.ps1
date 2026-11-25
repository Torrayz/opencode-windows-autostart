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

function Test-TcpPortListening([int]$TargetPort) {
    $listeners = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
    return [bool]($listeners | Where-Object { $_.Port -eq $TargetPort })
}

function Write-AutostartLog([string]$Message) {
    try {
        $baseDir = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [IO.Path]::GetTempPath() }
        $logDir = Join-Path $baseDir 'opencode-windows-autostart\logs'
        if (-not (Test-Path -LiteralPath $logDir -PathType Container)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        $logFile = Join-Path $logDir "$App.log"
        if ((Test-Path -LiteralPath $logFile -PathType Leaf) -and (Get-Item -LiteralPath $logFile).Length -gt 2MB) {
            Move-Item -LiteralPath $logFile -Destination "$logFile.1" -Force
        }
        $line = '[{0}] [pid={1}] {2}' -f ([DateTimeOffset]::Now.ToString('yyyy-MM-dd HH:mm:ss.fff zzz')), $PID, $Message
        Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    } catch {}
}

if (Test-TcpPortListening -TargetPort $port) {
    Write-AutostartLog "Port $port is already listening. Skipping $App."
    Write-Warning "Port $port is already listening. Skipping $App."
    exit 0
}

$createdNew = $false
$mutex = New-Object System.Threading.Mutex($false, "Local\OpenCodeWindowsAutostart-$App", [ref]$createdNew)
$hasHandle = $false
try {
    try {
        $hasHandle = $mutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        $hasHandle = $true
    }
    if (-not $hasHandle) {
        Write-AutostartLog "$App startup is already in progress. Skipping."
        Write-Warning "$App startup is already in progress. Skipping."
        exit 0
    }

    if (Test-TcpPortListening -TargetPort $port) {
        Write-AutostartLog "Port $port is already listening. Skipping $App."
        Write-Warning "Port $port is already listening. Skipping $App."
        exit 0
    }

    # A copy using a nondefault port can still share the same application data.
    $processes = if ($App -eq 'Router') {
        Get-CimInstance Win32_Process -Filter "Name = 'node.exe' OR Name = 'bun.exe'" |
            Where-Object {
                $_.CommandLine -match '(?i)(?:^|[\\/"\s])9router(?:[\\/."\s]|$)' -and
                $_.CommandLine -notmatch '(?i)\bcli\.js"?\s+(?:show|connect|xai)\b'
            }
    } else {
        Get-CimInstance Win32_Process -Filter "Name = 'opencode.exe'" |
            Where-Object { $_.CommandLine -match '(?i)(?:^|\s)serve(?:\s|$)' }
    }
    if ($processes) {
        Write-AutostartLog "An existing $App process was detected. Skipping startup."
        Write-Warning "An existing $App process was detected. Skipping startup."
        exit 0
    }

    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
        throw "Executable not found: $Executable"
    }

    $logBase = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [IO.Path]::GetTempPath() }
    $logDir = Join-Path $logBase 'opencode-windows-autostart\logs'
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $stdoutLog = Join-Path $logDir "$App.stdout.log"
    $stderrLog = Join-Path $logDir "$App.stderr.log"
    foreach ($streamLog in $stdoutLog, $stderrLog) {
        if ((Test-Path -LiteralPath $streamLog -PathType Leaf) -and (Get-Item -LiteralPath $streamLog).Length -gt 2MB) {
            Move-Item -LiteralPath $streamLog -Destination "$streamLog.1" -Force
        }
    }

    if ($App -eq 'Router') {
        if (-not $RouterCli) { throw 'Missing 9router CLI path.' }
        if (-not (Test-Path -LiteralPath $RouterCli -PathType Leaf)) {
            throw "9router CLI not found: $RouterCli"
        }

        # Launch 9router's standalone server directly instead of cli.js:
        # cli.js with --skip-update and no TTY enters WinForms NotifyIcon trayMode in Session 0,
        # skips server crash/close handlers, and runs stopPreviousInstance().
        $routerRoot = Split-Path -Path $RouterCli -Parent
        $standaloneDir = Join-Path $routerRoot 'app'
        $customServer = Join-Path $standaloneDir 'custom-server.js'
        $plainServer = Join-Path $standaloneDir 'server.js'
        $serverScript = if (Test-Path -LiteralPath $customServer -PathType Leaf) {
            $customServer
        } elseif (Test-Path -LiteralPath $plainServer -PathType Leaf) {
            $plainServer
        } else {
            throw "Cannot find 9router standalone server under $standaloneDir"
        }

        $appDataDir = if ($env:APPDATA) { $env:APPDATA } else { Join-Path $HOME 'AppData\Roaming' }
        $runtimeNm = Join-Path $appDataDir '9router\runtime\node_modules'
        $bundledNm = Join-Path $standaloneDir 'node_modules'
        $sqliteHook = Join-Path $routerRoot 'hooks\sqliteRuntime.js'
        if (-not (Test-Path -LiteralPath (Join-Path $runtimeNm 'better-sqlite3') -PathType Container) -and
            (Test-Path -LiteralPath $sqliteHook -PathType Leaf)) {
            $initArgs = '-e "try { require(process.argv[1]).ensureSqliteRuntime({ silent: true }); } catch {}" "{0}"' -f $sqliteHook
            Start-Process -FilePath $Executable -ArgumentList $initArgs -WorkingDirectory $routerRoot -NoNewWindow -Wait | Out-Null
        }

        $env:NODE_PATH = (@($runtimeNm, $bundledNm, $env:NODE_PATH) | Where-Object { $_ }) -join ';'
        $env:PORT = "$port"
        $env:HOSTNAME = '127.0.0.1'

        $argString = '"--max-old-space-size=6144" "{0}"' -f $serverScript
        Write-AutostartLog "Starting 9router standalone server ($serverScript) on 127.0.0.1:$port"
        $proc = Start-Process -FilePath $Executable -ArgumentList $argString -WorkingDirectory $standaloneDir `
            -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -NoNewWindow -Wait -PassThru
        Write-AutostartLog "9router server exited with code $($proc.ExitCode)"
        exit $proc.ExitCode
    } else {
        # Give 9router a brief head start so 127.0.0.1:20128 is ready when OpenCode loads providers.
        $deadline = [DateTime]::UtcNow.AddSeconds(12)
        while (-not (Test-TcpPortListening -TargetPort 20128) -and [DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 250
        }

        $workDir = if ($env:USERPROFILE -and (Test-Path -LiteralPath $env:USERPROFILE -PathType Container)) {
            $env:USERPROFILE
        } else {
            Split-Path -Path $Executable -Parent
        }

        $filePath = $Executable
        $argString = 'serve --service --hostname 127.0.0.1 --port {0}' -f $port
        if ($Executable.EndsWith('.cmd', [StringComparison]::OrdinalIgnoreCase) -or
            $Executable.EndsWith('.bat', [StringComparison]::OrdinalIgnoreCase)) {
            $candidateExe = Join-Path (Split-Path -Path $Executable -Parent) 'node_modules\@opencode\cli\bin\opencode.exe'
            if (Test-Path -LiteralPath $candidateExe -PathType Leaf) {
                $filePath = $candidateExe
            } else {
                $filePath = Join-Path $env:SystemRoot 'System32\cmd.exe'
                $argString = '/d /s /c ""{0}" {1}"' -f $Executable, $argString
            }
        }

        Write-AutostartLog "Starting OpenCode server ($filePath) on 127.0.0.1:$port"
        $proc = Start-Process -FilePath $filePath -ArgumentList $argString -WorkingDirectory $workDir `
            -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -NoNewWindow -Wait -PassThru
        Write-AutostartLog "OpenCode server exited with code $($proc.ExitCode)"
        exit $proc.ExitCode
    }
} catch {
    Write-AutostartLog "ERROR: $($_.Exception.Message)"
    throw
} finally {
    if ($hasHandle) {
        try { $mutex.ReleaseMutex() } catch {}
    }
    $mutex.Dispose()
}
