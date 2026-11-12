@echo off
rem /tools/isp/burn_bootloader.bat
rem One-time install of the Kjern bootloader with a USBasp (Windows).
rem Does the same as Tools > Burn Bootloader in the Arduino IDE.
rem
rem Wiring, USBasp 10-pin header to board. USB-C unplugged, USBasp jumper on 5 V:
rem   1 MOSI to MOSI (TP12 or J1 pin 10)      7 SCK  to SCK  (TP11 or J2 pin 9)
rem   2 VCC  to +5V  (J2 pin 3)               9 MISO to MISO (TP13 or J1 pin 9)
rem   5 RST  to RST  (TP15, or the RST pad of the reset button)
rem   4/6/8/10 GND to GND (J2 pin 1 or 2)
rem RST has to be wired. Holding the reset button by hand does not work reliably.
rem
rem Writes fuses low FF, high D8, extended CB, the bootloader at 0x7000, lock bits 2F.
setlocal enabledelayedexpansion
cd /d "%~dp0"
set "HEX=..\..\firmware\bootloader\Kjern-32u4HID-C_bootloader.hex"
set "LOG=burn_bootloader.log"
set "AVRDUDE="
set "CONF="
for %%A in (avrdude.exe) do set "AVRDUDE=%%~$PATH:A"
if not defined AVRDUDE (
  for /d %%D in ("%LOCALAPPDATA%\Arduino15\packages\arduino\tools\avrdude\*") do (
    if exist "%%D\bin\avrdude.exe" (
      set "AVRDUDE=%%D\bin\avrdude.exe"
      set "CONF=%%D\etc\avrdude.conf"
    )
  )
)
if not defined AVRDUDE (
  echo avrdude.exe not found. Put it on PATH or install the Arduino IDE with "Arduino AVR Boards".
  pause & exit /b 1
)
if not exist "%HEX%" (echo Bootloader file missing: %HEX% & pause & exit /b 1)
if defined CONF (set CF=-C "%CONF%") else (set CF=)
echo Using %AVRDUDE%
echo. > "%LOG%"

echo === 1/3  Talking to the chip: signature, fuses, lock bits ===
"%AVRDUDE%" %CF% -c usbasp -p atmega32u4 -B 32 -U lfuse:r:-:h -U hfuse:r:-:h -U efuse:r:-:h -U lock:r:-:h
if errorlevel 1 (
  echo.
  echo Could not talk to the chip. Nothing has been changed.
  echo Check: RST wired to the programmer, MOSI/MISO not swapped, GND connected,
  echo USBasp jumper on 5 V, USB-C cable unplugged.
  echo If avrdude cannot find the USBasp itself: install its driver with Zadig ^(libusbK or WinUSB^).
  pause & exit /b 1
)

echo.
echo === 2/3  Erase, set fuses FF D8 CB ===
"%AVRDUDE%" %CF% -c usbasp -p atmega32u4 -B 32 -e -U lock:w:0x3F:m -U efuse:w:0xcb:m -U hfuse:w:0xd8:m -U lfuse:w:0xff:m
if errorlevel 1 (echo. & echo Erase / fuse step failed. & pause & exit /b 1)

echo.
echo === 3/3  Write the bootloader, lock the boot section ===
"%AVRDUDE%" %CF% -c usbasp -p atmega32u4 -B 8 -U "flash:w:%HEX%:i" -U lock:w:0x2F:m
if errorlevel 1 (echo. & echo Bootloader write failed. Run this file again. & pause & exit /b 1)

echo.
echo Done. Disconnect the programmer and plug the board into USB.
echo It shows up as a COM port until the first sketch is uploaded.
pause
