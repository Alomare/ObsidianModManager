@echo off
rem Runs the Kepler Loader tests under the LuaJIT 2.0 build from tools\build-luajit.cmd.
pushd "%~dp0.."
"target\luajit\luajit.exe" loader\tests\run.lua %*
set RESULT=%ERRORLEVEL%
popd
exit /b %RESULT%
