# OpenCode Windows Autostart

Start **9router** (`127.0.0.1:20128`) and **OpenCode V2** (`127.0.0.1:28894`) automatically at Windows boot, user sign-in, and whenever a network/hotspot connection comes online — without opening CMD, entering a Windows password, or interrupting running instances.

**Prerequisites:** Node.js, OpenCode V2, and 9router installed globally via npm under your Windows user account.

## Set up or update autostart

1. Open **Windows PowerShell** as **Administrator** (or double-click `Setup-Autostart.cmd`).
2. Run:

   ```powershell
   cd $HOME
   git clone https://github.com/Torrayz/opencode-windows-autostart.git
   cd .\opencode-windows-autostart
   powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\Autostart.ps1 Install
   ```

   Running `Install` is safe while 9router and OpenCode are already open: task definitions are updated in place without restarting active servers, and any stopped server is started immediately.

3. Check task status anytime:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\Autostart.ps1 Status
   ```

   Startup logs are written to `%LOCALAPPDATA%\opencode-windows-autostart\logs\`.

Open the [local 9router dashboard](http://127.0.0.1:20128/dashboard) in a browser. Running `9router` again in CMD can replace the background server. Task Scheduler retries every two minutes if the router task has ended, including after a clean exit. While the task is running, Windows ignores the extra trigger without starting another PowerShell process. This recovers a stopped server; it does not restart an unresponsive one that is still running.

## Turn off autostart

Open **Windows PowerShell as Administrator** and run:

```powershell
cd "$HOME\opencode-windows-autostart"
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\Autostart.ps1 Uninstall
```

This removes the scheduled tasks without touching your apps, accounts, or sessions.
