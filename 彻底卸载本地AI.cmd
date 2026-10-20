@echo off
chcp 65001 >nul 2>&1
setlocal
set "SCRIPT=%~dp0彻底卸载本地AI.ps1"

if not exist "%SCRIPT%" (
    echo.
    echo [错误] 找不到“彻底卸载本地AI.ps1”，请确保它与本文件放在同一目录下。
    echo.
    pause
    exit /b 1
)

echo 正在启动 local-ai-kit 彻底卸载工具...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*

if errorlevel 1 (
    echo.
    echo [提示] 工具已结束（可能中途取消或出错）。
)
endlocal
