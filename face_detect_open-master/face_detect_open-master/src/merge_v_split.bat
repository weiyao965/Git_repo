@echo off
chcp 65001 >nul 2>nul
setlocal enabledelayedexpansion

set "MAXSIZE=51200"
set "BASENAME=combined"
set "PART=0"
set "OUTFILE=%BASENAME%.txt"

cd /d "%~dp0"

del "%BASENAME%*.txt" 2>nul
type nul > "%OUTFILE%"
set "CURRSIZE=0"

for /r %%F in (*.v) do (
    echo 正在处理: %%F
    set "FULLPATH=%%F"
    set "FNAME=%%~nxF"
    set "TMPFILE=%TEMP%\_vmerge_tmp_%RANDOM%.txt"

    :: 写入 "文件名:" + 换行
    > "!TMPFILE!" echo !FNAME!:
    :: 追加文件内容（使用延迟扩展变量）
    type "!FULLPATH!" >> "!TMPFILE!"
    :: 追加一个换行
    echo. >> "!TMPFILE!"

    :: 获取临时文件大小
    for %%A in ("!TMPFILE!") do set "ADD=%%~zA"
    if not defined ADD set ADD=0

    set /a NEWSUM=CURRSIZE+ADD
    if !NEWSUM! gtr !MAXSIZE! (
        set /a PART+=1
        set "OUTFILE=%BASENAME%_!PART!.txt"
        type nul > "!OUTFILE!"
        set "CURRSIZE=0"
        echo 新建分片: !OUTFILE!
    )

    :: 追加临时文件内容
    type "!TMPFILE!" >> "!OUTFILE!"
    del "!TMPFILE!"

    :: 更新当前输出文件大小
    for %%A in ("!OUTFILE!") do set "CURRSIZE=%%~zA"
)

echo.
echo 完成！共生成 %PART% 个分片文件。
dir "%BASENAME%*.txt"
pause