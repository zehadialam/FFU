$cleanupPaths = @(
    "C:\Autopilot",
    "C:\Windows\Setup\Scripts"
)
foreach ($path in $cleanupPaths) {
    if (Test-Path -Path $path -PathType Container) {
        Remove-Item -Path $path -Recurse -Force
    }
}
Unregister-ScheduledTask -TaskName "CleanupAndSysprep" -Confirm:$false
Start-Process -FilePath "C:\Windows\System32\Sysprep\sysprep.exe" -ArgumentList "/oobe /reboot /quiet" -NoNewWindow