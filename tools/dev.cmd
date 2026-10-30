@echo off
rem Runs the app in dev mode with the WebView2 DevTools port open, for tools\cdp.mjs.
set WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=9222
cd /d "%~dp0..pp" && npx tauri dev
