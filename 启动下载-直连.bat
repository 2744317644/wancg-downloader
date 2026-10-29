@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

set "PYEXE="
where py >nul 2>nul && set "PYEXE=py -3"
if not defined PYEXE if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set "PYEXE=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
if not defined PYEXE where python >nul 2>nul && set "PYEXE=python"
if not defined PYEXE (
  echo Python 3 was not found.
  echo Install it from https://www.python.org/downloads/
  echo and enable "Add python.exe to PATH" during setup.
  pause
  exit /b 1
)

echo Starting wnacg Web UI in DIRECT mode (DoH, no proxy)...
echo If doh.pub is unreachable, use the normal launcher instead.
echo.
%PYEXE% "%~dp0wnacg_web.py" --direct
echo.
echo Web UI stopped.
pause
