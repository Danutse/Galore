@echo off
cd /d "C:\Users\lafle\OneDrive\Desktop\scrcpy-win64-v4.1"

:: 1. Force kill any frozen background connection tasks in Windows memory
taskkill /F /IM adb.exe >nul 2>&1

:: 2. Sit silently until the refreshed hardware link connects
echo Connecting to your Pixel 9...
adb.exe wait-for-device

:: 3. Launch scrcpy windowed immediately with high-quality settings
start "" scrcpy.exe --video-bit-rate=32M --max-fps=120 --audio-codec=aac --stay-awake --power-off-on-close

:: 4. Instantly close this cmd window
exit
