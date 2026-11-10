@echo off
python "%~dp0nuget_offline.py" %*
exit /b %errorlevel%
