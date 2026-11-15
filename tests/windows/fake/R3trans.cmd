@echo off
rem stand-in for R3trans.exe (tests)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0r3trans_fake.ps1" %*
exit /b %errorlevel%
