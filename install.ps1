# Pemasang Tenun untuk Windows.
# Pakai: irm https://raw.githubusercontent.com/TenunLang/Tenun/main/install.ps1 | iex
$ErrorActionPreference = "Stop"

$repo = "TenunLang/Tenun"
$dest = "$HOME\.tenun\bin"
$url = "https://github.com/$repo/releases/latest/download/tenun-windows-x86_64.exe"

Write-Host "Mengunduh tenun-windows-x86_64.exe ..."
New-Item -ItemType Directory -Force $dest | Out-Null
Invoke-WebRequest -Uri $url -OutFile "$dest\tenun.exe"

# Tambahkan ke PATH pengguna
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$dest*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$dest", "User")
}

Write-Host ""
Write-Host "Tenun terpasang di $dest\tenun.exe"
Write-Host "Buka terminal baru, lalu: tenun version"
