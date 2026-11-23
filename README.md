# OpenCode Windows Autostart

Start OpenCode V2 and 9router when Windows boots, without opening CMD or signing in. This beta is for people who already run both apps manually on their default ports. It doesn't change your app settings, accounts, or sessions.

**Before you start:** You'll need [Git for Windows](https://gitforwindows.org/), Node.js, OpenCode V2, and 9router installed globally via npm. Use the Windows account you normally run these apps from. If either app already starts automatically, skip this installer.

## Set up autostart

1. Click **Start**, search for **Windows PowerShell**, right-click it, choose **Run as administrator**, then click **Yes**.
2. Paste these lines to download the installer and enter its folder:

   ```powershell
   cd $HOME
   git clone https://github.com/Torrayz/opencode-windows-autostart.git
   cd .\opencode-windows-autostart
   ```

3. Save your work. In the CMD window running 9router, press **Ctrl+C**. If it's in the system tray instead, right-click the 9router icon and choose **Quit**. Close OpenCode, then run `opencode service stop` in PowerShell.
4. In the same PowerShell window, run:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\Autostart.ps1 Install -AllowPhysicalPC
   ```

5. Type `TEST`, then enter your **Windows account password**, not your PIN. Wait for `Installed:` to list both tasks. Leave the `opencode-windows-autostart` folder where it is.
6. Click **Start → Power → Restart**. Don't open 9router or OpenCode manually. If your phone is already paired to this PC, try a 9router model from your phone while Windows is still at the sign-in screen. Otherwise, sign in and check that both tasks say `Running`:

   ```powershell
   cd "$HOME\opencode-windows-autostart"
   powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\Autostart.ps1 Status
   ```

## Turn off autostart

Open **Windows PowerShell as administrator** again and run:

```powershell
cd "$HOME\opencode-windows-autostart"
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\Autostart.ps1 Uninstall
```

This removes the startup tasks, not the apps or their data.
