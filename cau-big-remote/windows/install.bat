@echo off
setlocal
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Hay chuot phai file install.bat va chon Run as administrator.
  pause
  exit /b 1
)
set "APPDIR=%ProgramData%\CAU-BIG-Remote"
mkdir "%APPDIR%" 2>nul
copy /Y "%~dp0CAU-BIG-Companion.exe" "%APPDIR%\CAU-BIG-Companion.exe" >nul
netsh advfirewall firewall delete rule name="CAU-BIG Remote Companion" >nul 2>&1
netsh advfirewall firewall add rule name="CAU-BIG Remote Companion" dir=in action=allow protocol=TCP localport=8765 remoteip=localsubnet,100.64.0.0/10 profile=any >nul
schtasks /Delete /TN "CAU-BIG Remote Companion" /F >nul 2>&1
schtasks /Create /TN "CAU-BIG Remote Companion" /SC ONLOGON /RL HIGHEST /TR "\"%APPDIR%\CAU-BIG-Companion.exe\"" /F >nul
start "" "%APPDIR%\CAU-BIG-Companion.exe"
timeout /t 2 >nul
echo.
echo ==============================================
echo CAU-BIG Remote Companion da cai xong.
echo Port: 8765
echo Chi cho phep LAN va Tailscale 100.64.0.0/10.
echo KHONG forward cong 8765 truc tiep ra Internet.
echo ==============================================
echo.
echo File TOKEN se mo bang Notepad. Hay nhap TOKEN nay vao app iPhone.
if exist "%APPDIR%\TOKEN.txt" start "" notepad "%APPDIR%\TOKEN.txt"
pause
