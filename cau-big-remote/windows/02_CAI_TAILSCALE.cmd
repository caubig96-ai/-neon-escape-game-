@echo off
setlocal
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Hay chuot phai file nay va chon Run as administrator.
  pause
  exit /b 1
)
where tailscale >nul 2>&1
if %errorlevel% equ 0 goto :LOGIN
where winget >nul 2>&1
if %errorlevel% neq 0 (
  echo Khong tim thay winget. Hay cai Tailscale tu https://tailscale.com/download/windows
  pause
  exit /b 1
)
winget install --id Tailscale.Tailscale -e --accept-package-agreements --accept-source-agreements
:LOGIN
start "" "C:\Program Files\Tailscale\tailscale-ipn.exe" 2>nul
timeout /t 3 >nul
if exist "C:\Program Files\Tailscale\tailscale.exe" (
  echo IP Tailscale cua PC:
  "C:\Program Files\Tailscale\tailscale.exe" ip -4
)
echo.
echo Tren iPhone: cai Tailscale, dang nhap cung tai khoan, bat VPN Tailscale.
echo Sau do nhap URL trong app CAU-BIG Remote theo dang:
echo http://100.x.x.x:8765
pause
