# OpenCode Windows Autostart

This preview uses Windows Task Scheduler to start OpenCode V2 and 9router before anyone signs in. The tasks run as your Windows user, without elevated privileges. The installer does not install either app, edit its configuration or credentials, or enable remote access.

**Test installs on a fresh, disposable Windows VM only.** The 9router CLI can stop an existing instance during startup. The installer refuses to install on machines it does not recognize as VMs, and also refuses installation while either default port is listening. The port check only covers the time of installation. Do not run a second copy of either app on the test VM. `Check` and `Status` are read-only and can be run on your main PC.

## Requirements

- Windows with Windows PowerShell 5.1 and Task Scheduler. VM install detection covers common Hyper-V, VMware, VirtualBox, and QEMU configurations.
- Node.js, OpenCode V2, and an npm global installation of 9router. Open a fresh PowerShell window and confirm the commands are on `PATH`.
- Access to run the installer as administrator **under the same Windows account that owns the app configuration**. Use your account password at the setup prompt, not your Windows Hello PIN. Passwordless accounts and setups that elevate under a different account are outside the scope of this version.

## Install and test

```powershell
.\Autostart.ps1 Check                     # Show the commands without installing anything
.\Autostart.ps1 Install -WhatIf           # Preview task registration
.\Autostart.ps1 Install                   # Run as administrator
```

Alternatively, right-click `Setup-Autostart.cmd` and choose **Run as administrator** on the test VM. Review the scripts before running them. Type `TEST` at the disposable VM confirmation. Do not import existing production sessions or credentials into the VM just to run the startup test.

1. Save your work and restart Windows. Leave it at the sign-in screen. Do not start either app manually.
2. If you have paired your phone to this VM and configured a test provider, choose that connection and send a prompt using a model routed through 9router. The VM needs internet and must be awake for remote use. To pair for the first time, see [OpenCode's remote access documentation](https://opencode.ai/docs/cli/web/#remote-access).
3. After signing in, run `.\Autostart.ps1 Status`. Look for `Running` and a `LastRun` time from the current boot. `0x00041301` means the task is running; it does not prove that your model provider or the tunnel works.

The listeners use `127.0.0.1` (9router `20128`, OpenCode `28894`). The installer does not add firewall rules. Task Scheduler uses the account password to run before sign-in. If your Windows password changes, remove and reinstall these tasks with the new password.

If either task name is already in use by an older installer or another user, installation stops rather than replacing it. Review those tasks manually before attempting a migration. Only one instance per app and PC is supported in this version.

## Remove

```powershell
.\Autostart.ps1 Uninstall -WhatIf
.\Autostart.ps1 Uninstall                  # Run as administrator
```

This removes only this installer's tasks for the current account. It does not delete either app, configuration, or sessions.

## Development check

Run `.\tests\Smoke.ps1` with the apps on `PATH`. It checks the task definitions and uses simulated machines and task entries to test install safeguards. It does not register tasks or reboot Windows. A clean install and reboot of this preview are still to be tested.
