@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

set "BOOKMARK=%~1"
if not defined BOOKMARK set /p "BOOKMARK=请把书签 HTML 文件拖到这里，或输入完整路径: "
if not defined BOOKMARK (
  echo 没有提供书签文件。
  pause
  exit /b 1
)

if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" (
  "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" "%~dp0batch_bookmarks.py" "%BOOKMARK%" -o "%~dp0downloads" --direct
  goto finished
)

where py >nul 2>nul
if not errorlevel 1 (
  py -3 "%~dp0batch_bookmarks.py" "%BOOKMARK%" -o "%~dp0downloads" --direct
  goto finished
)

where python >nul 2>nul
if not errorlevel 1 (
  python "%~dp0batch_bookmarks.py" "%BOOKMARK%" -o "%~dp0downloads" --direct
  goto finished
)

echo 未找到 Python 3。
echo 请安装 Python 3，安装时勾选 Add python.exe to PATH。
pause
exit /b 1

:finished
echo.
echo 完成，报告在 downloads\batch_report.txt
pause
