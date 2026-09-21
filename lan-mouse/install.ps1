# 1. Variables and Paths
$installPath = "$env:LOCALAPPDATA\LanMouse"
$zipPath = "$env:TEMP\lan-mouse-windows.zip"
$repoUrl = "https://api.github.com/repos/feschber/lan-mouse/releases/latest"

# 2. Fetch and Download the Latest Release
Write-Host "Checking GitHub for the latest Lan Mouse release..." -ForegroundColor Cyan
$release = Invoke-RestMethod -Uri $repoUrl
$asset = $release.assets | Where-Object { $_.name -match "windows.*\.zip" }

if ($null -eq $asset) {
    Write-Error "Could not find a matching .zip release for Windows."
    Break
}

Write-Host "Downloading $($asset.name)..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath

# 3. Extract Files (Preserves directory structure and GTK DLLs)
Write-Host "Extracting to $installPath..." -ForegroundColor Cyan
if (Test-Path $installPath) { Remove-Item -Recurse -Force $installPath }
New-Item -ItemType Directory -Force -Path $installPath | Out-Null
Expand-Archive -Path $zipPath -DestinationPath $installPath -Force

# Identify the extracted executable
$exePath = Get-ChildItem -Path $installPath -Filter "lan-mouse.exe" -Recurse | Select-Object -First 1 -ExpandProperty FullName

# 4. Configure Windows Defender Firewall (Ports and Executable)
Write-Host "Configuring Windows Firewall rules (Port 4242 TCP/UDP)..." -ForegroundColor Cyan
Remove-NetFirewallRule -DisplayName "Lan Mouse" -ErrorAction SilentlyContinue

New-NetFirewallRule -DisplayName "Lan Mouse" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 4242 -Program $exePath | Out-Null
New-NetFirewallRule -DisplayName "Lan Mouse" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 4242 -Program $exePath | Out-Null

# 5. Create Desktop Shortcut
Write-Host "Creating Desktop shortcut..." -ForegroundColor Cyan
$WshShell = New-Object -comObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\Lan Mouse.lnk")
$Shortcut.TargetPath = $exePath
$Shortcut.WorkingDirectory = Split-Path $exePath
$Shortcut.Save()

# Cleanup
Remove-Item $zipPath
Write-Host "Setup complete! Launch Lan Mouse from your Desktop." -ForegroundColor Green
