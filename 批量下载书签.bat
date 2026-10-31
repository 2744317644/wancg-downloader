@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

set "BOOKMARK=%~1"
if not defined BOOKMARK set /p "BOOKMARK=请把书签 HTML 文件拖到这里，或输入完整路径: "
if not defined BOOKMARK goto nofile

set "PY=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
if exist "%PY%" goto run_path

where py >nul 2>nul
if not errorlevel 1 goto run_py

where python >nul 2>nul
if not errorlevel 1 goto run_python

goto nopython

:run_path
"%PY%" "%~dp0batch_bookmarks.py" "%BOOKMARK%" -o "%~dp0downloads"
goto done

:run_py
py -3 "%~dp0batch_bookmarks.py" "%BOOKMARK%" -o "%~dp0downloads"
goto done

:run_python
python "%~dp0batch_bookmarks.py" "%BOOKMARK%" -o "%~dp0downloads"
goto done

:nopython
echo.
echo 未找到 Python 3。
echo 请安装 Python 3，安装时勾选 Add python.exe to PATH。
echo.
pause
exit /b 1

:nofile
echo.
echo 没有提供书签文件。
echo.
pause
exit /b 1

:done
echo.
echo 完成，报告在 downloads\batch_report.txt
pause
