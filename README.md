# OpenCode Windows Autostart

This preview uses Windows Task Scheduler to start OpenCode V2 and 9router before anyone signs in. The tasks run as your Windows user, without elevated privileges. The installer does not install either app, edit its configuration or credentials, or enable remote access.

**This is a beta.** A fresh Windows VM is the easiest place to test, but `Install -AllowPhysicalPC` is available for volunteers who normally start both apps manually. Do not use this alongside an existing startup entry for either app. The 9router CLI can stop a previous instance, so each boot task skips startup if it sees a listener on that app's default port or recognizes an existing app process. The process check is best effort; don't race the task by starting another copy manually. `Check` and `Status` are read-only.

## Requirements

- Windows with Windows PowerShell 5.1 and Task Scheduler. VM install detection covers common Hyper-V, VMware, VirtualBox, and QEMU configurations. Physical PCs require a separate opt-in.
- Node.js, OpenCode V2, and an npm global installation of 9router. Open a fresh PowerShell window and confirm the commands are on `PATH`.
- Access to run the installer as administrator **under the same Windows account that owns the app configuration**. Use your account password at the setup prompt, not your Windows Hello PIN. Passwordless accounts and setups that elevate under a different account are outside the scope of this version.

## Install and test

```powershell
.\Autostart.ps1 Check                     # Show the commands without installing anything
.\Autostart.ps1 Install -WhatIf           # Preview task registration
.\Autostart.ps1 Install                   # Run as administrator
```

On a VM, you can also right-click `Setup-Autostart.cmd` and choose **Run as administrator**.

For a physical PC, first make sure neither app already starts automatically. Back up any important work, then exit 9router from its terminal or tray. Exit OpenCode and run `opencode service stop` if its background service is still running. The installer itself does not stop either app. In an Administrator Windows PowerShell window, run:

```powershell
.\Autostart.ps1 Install -AllowPhysicalPC
```

Type `TEST` at the beta confirmation. Keep the installer folder in the same location while the tasks are installed: Task Scheduler uses `Start-Guarded.ps1` from that folder.

1. Save your work and restart Windows. Leave it at the sign-in screen. Do not start either app manually.
2. If you already paired your phone to the test PC, choose that connection and send a prompt using a model routed through 9router. The PC needs internet and must be awake. To pair for the first time, see [OpenCode's remote access documentation](https://opencode.ai/docs/cli/web/#remote-access).
3. After signing in, run `.\Autostart.ps1 Status`. Look for `Running` and a `LastRun` time from the current boot. `0x00041301` means the task is running; it does not prove that your model provider or the tunnel works.

The tasks use the default local endpoints: `127.0.0.1:20128` (9router) and `127.0.0.1:28894` (OpenCode). If you run either app on a custom port, skip this beta. The installer does not add firewall rules or turn on pairing. It preserves the apps' own settings, including any remote access you already turned on. Task Scheduler uses the account password to run before sign-in. If your Windows password changes, remove and reinstall these tasks with the new password.

If either task name is already in use by an older installer or another user, installation stops rather than replacing it. Review those tasks manually before attempting a migration. Only one instance per app and PC is supported in this version.

## Remove

```powershell
.\Autostart.ps1 Uninstall -WhatIf
.\Autostart.ps1 Uninstall                  # Run as administrator
```

This removes only this installer's tasks for the current account. It does not delete either app, configuration, or sessions.

## Development check

Run `.\tests\Smoke.ps1` with the apps on `PATH`. It checks the task definitions, install safeguards, and what happens when a startup port is already listening. It does not register tasks or reboot Windows. A clean install and reboot of this beta are still to be tested.
