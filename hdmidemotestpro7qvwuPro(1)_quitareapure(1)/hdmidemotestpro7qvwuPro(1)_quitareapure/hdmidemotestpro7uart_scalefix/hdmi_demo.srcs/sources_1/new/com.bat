@echo off
:: 强制切换到脚本所在目录（解决管理员运行后目录错误）
cd /d "%~dp0" 2>nul || exit /b

set "OUTFILE=combined.txt"
if exist "%OUTFILE%" del "%OUTFILE%"

echo 当前工作目录: %cd%
echo 正在搜索 .v 文件（包含子目录）...

set count=0
for /r %%F in (*.v) do (
    echo 处理: %%~nxF
    >> "%OUTFILE%" echo %%~nxF:
    >> "%OUTFILE%" type "%%F"
    >> "%OUTFILE%" echo.
    set /a count+=1
)

if %count%==0 (
    echo 错误：当前目录及子目录下没有找到任何 .v 文件。
) else (
    echo 成功处理 %count% 个文件，结果保存到 %cd%\%OUTFILE%
)

echo.
echo 请按任意键关闭窗口...
pause >nul