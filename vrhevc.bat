@echo off
REM ============================================================
REM  HEVC (H.265) VR STREAM  -  for the HEVC build of the app
REM  OBS one-time settings:
REM    Settings > Video > Base AND Output = 
REM    Settings > Video > FPS = 60
REM  Start your game, then double-click this.
REM ============================================================
set IP=
set BR=100M
set OBS="C:\Program Files\obs-studio\bin\64bit"

echo Cleaning up any running OBS / ffmpeg...
taskkill /f /im ffmpeg.exe >nul 2>&1
taskkill /f /im obs64.exe >nul 2>&1
taskkill /f /im vrxrctl.exe >nul 2>&1
timeout /t 2 /nobreak >nul

echo Launching one OBS + virtual camera...
pushd %OBS%
start "" obs64.exe --startvirtualcam --minimize-to-tray --disable-shutdown-check
popd

echo Waiting for the virtual camera...
timeout /t 12 /nobreak >nul

echo Launching gamepad control (L3+R3 full/fit)...
start "" "%~dp0vrxrctl.exe" 

:loop
echo Streaming 1440p60 HEVC -> %IP% ...  (close this window to stop)
ffmpeg -f dshow -rtbufsize 256M -i video="OBS Virtual Camera" ^
  -c:v hevc_nvenc -preset p1 -tune ll -rc cbr -b:v %BR% -maxrate %BR% -bufsize %BR% -g 60 -bf 0 ^
  -pix_fmt yuv420p ^
  -an -f rtp -payload_type 96 "rtp://%IP%:5000?pkt_size=1316"
timeout /t 1 /nobreak >nul
goto loop
