@echo off
rem /tools/kjern-dfu-upload.bat
rem Waits for the Kjern-32u4HID-C to appear as Atmel DFU (03eb:2ff4), then erases, flashes and starts the sketch.
setlocal
set "HEX=%~1"
set "DFU=%~dp0dfu-programmer.exe"
if not exist "%DFU%" set "DFU=dfu-programmer"
set MCU=atmega32u4

echo Waiting for Kjern-32u4HID-C in DFU mode (03eb:2ff4)...
set /a n=0
:wait
"%DFU%" %MCU% get bootloader-version >nul 2>&1
if not errorlevel 1 goto found
set /a n+=1
if %n% gtr 30 goto nodev
ping -n 2 127.0.0.1 >nul
goto wait

:found
"%DFU%" %MCU% erase --force || exit /b 1
"%DFU%" %MCU% flash "%HEX%" || exit /b 1
"%DFU%" %MCU% launch >nul 2>&1 || "%DFU%" %MCU% start >nul 2>&1 || "%DFU%" %MCU% reset
echo Done. Sketch is running.
exit /b 0

:nodev
echo No DFU device found. Unplug, tie PB0 to GND, plug back in (board becomes ATm32U4DFU), then upload again.
echo On Windows the DFU device also needs the libusb driver (Zadig, see LES_MEG.txt).
exit /b 1
