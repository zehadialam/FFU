#Requires AutoHotkey v2.0

WinWait "Microsoft account"
    WinActivate
    Send "+{F10}"

WinWait "Administrator: C:\Windows\system32\cmd.exe"
    WinActivate

Send "powershell -ExecutionPolicy Bypass -File C:\Autopilot\Register-Autopilot.ps1{Enter}"

ExitApp