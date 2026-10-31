@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

set "PYEXE="
where py >nul 2>nul && set "PYEXE=py -3"
if not defined PYEXE if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set "PYEXE=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
if not defined PYEXE where python >nul 2>nul && set "PYEXE=python"
if not defined PYEXE (
  echo 未找到 Python 3，请先安装 Python。
  pause
  exit /b 1
)

set "BOOKMARK=%~1"
if not defined BOOKMARK set /p "BOOKMARK=请把书签 HTML 文件拖到这里，或输入完整路径: "
if not defined BOOKMARK (
  echo 没有提供书签文件。
  pause
  exit /b 1
)

%PYEXE% "%~dp0batch_bookmarks.py" "%BOOKMARK%" -o "%~dp0downloads"
echo.
echo 完成，按任意键关闭。
pause
