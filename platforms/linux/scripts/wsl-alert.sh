#!/bin/bash
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -Command "
Add-Type -AssemblyName System.Windows.Forms | Out-Null;
[System.Windows.Forms.MessageBox]::Show('Hello from Fleet (running inside WSL).','Fleet','OK','Information') | Out-Null
" >/dev/null 2>&1
echo "Displayed Windows MessageBox"
