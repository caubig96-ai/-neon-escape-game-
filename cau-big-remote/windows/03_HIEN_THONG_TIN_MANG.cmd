@echo off
setlocal
chcp 65001 >nul
echo ==============================================
echo THONG TIN MANG - CAU-BIG REMOTE
echo ==============================================
echo.
echo [1] IP LAN va Gateway:
ipconfig | findstr /I /C:"IPv4 Address" /C:"Default Gateway"
echo.
echo [2] Public IP hien tai:
powershell -NoProfile -Command "try { (Invoke-RestMethod -UseBasicParsing 'https://api.ipify.org').ToString() } catch { 'Khong lay duoc Public IP' }"
echo.
echo [3] Tailscale IP neu da cai:
if exist "C:\Program Files\Tailscale\tailscale.exe" (
  "C:\Program Files\Tailscale\tailscale.exe" ip -4
) else (
  echo Chua tim thay Tailscale.
)
echo.
echo MAC CAU-BIG: 34:5A:60:2F:6F:2B
echo LAN PC: 192.168.2.139
echo Broadcast: 192.168.2.255
echo Companion: TCP 8765
echo Wake LAN: UDP 9
echo Wake Internet de xuat: UDP 40009
pause
