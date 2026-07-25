@echo off
setlocal
set "WZDB_DIR=%~dp0"
node "%WZDB_DIR%bridge.js" %*
exit /b %ERRORLEVEL%
