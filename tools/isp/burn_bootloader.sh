#!/bin/sh
# /tools/isp/burn_bootloader.sh
# One-time install of the Kjern bootloader with an ISP programmer (macOS and Linux).
# Does the same as Tools > Burn Bootloader in the Arduino IDE.
#
# Usage:  sh tools/isp/burn_bootloader.sh            (USBasp)
#         sh tools/isp/burn_bootloader.sh stk500v1 /dev/cu.usbmodemXXXX   (Arduino as ISP)
#
# Wiring, USBasp 10-pin header -> board. USB-C unplugged, USBasp jumper on 5 V:
#   1 MOSI -> MOSI (TP12 or J1 pin 10)      7 SCK  -> SCK  (TP11 or J2 pin 9)
#   2 VCC  -> +5V  (J2 pin 3)               9 MISO -> MISO (TP13 or J1 pin 9)
#   5 RST  -> RST  (TP15, or the RST pad of the reset button)
#   4/6/8/10 GND -> GND (J2 pin 1 or 2)
# RST has to be wired. Holding the reset button by hand does not work reliably.
#
# What it writes: fuses low FF, high D8, extended CB (the Arduino Leonardo values),
# the bootloader at 0x7000, lock bits 2F. The whole chip is erased first.

PROG="${1:-usbasp}"
PORT="$2"
HERE="$(cd "$(dirname "$0")" && pwd)"
HEX="$HERE/../../firmware/bootloader/Kjern-32u4HID-C_bootloader.hex"
LOG="$HERE/burn_bootloader.log"

AVRDUDE="$(command -v avrdude 2>/dev/null)"
CONF=""
if [ -z "$AVRDUDE" ]; then
    for d in "$HOME/Library/Arduino15/packages/arduino/tools/avrdude"/* "$HOME/.arduino15/packages/arduino/tools/avrdude"/*; do
        if [ -x "$d/bin/avrdude" ]; then AVRDUDE="$d/bin/avrdude"; CONF="$d/etc/avrdude.conf"; fi
    done
fi
if [ -z "$AVRDUDE" ]; then
    echo "avrdude not found. Install the Arduino IDE with 'Arduino AVR Boards', or 'brew install avrdude'."
    exit 1
fi
if [ ! -f "$HEX" ]; then echo "Bootloader file missing: $HEX"; exit 1; fi

run() {
    echo "" | tee -a "$LOG"
    echo "> avrdude $*" | tee -a "$LOG"
    # tee would hide avrdude's exit code, so it is passed through a small file
    if [ -n "$CONF" ]; then ( "$AVRDUDE" -C "$CONF" "$@" 2>&1; echo $? > "$LOG.rc" ) | tee -a "$LOG"
    else ( "$AVRDUDE" "$@" 2>&1; echo $? > "$LOG.rc" ) | tee -a "$LOG"; fi
    RC="$(cat "$LOG.rc" 2>/dev/null)"; rm -f "$LOG.rc"
    [ "$RC" = "0" ]
}

if [ -n "$PORT" ]; then CONN="-c $PROG -P $PORT -b 19200"; else CONN="-c $PROG"; fi
: > "$LOG"
echo "Using $AVRDUDE"

echo "=== 1/3  Talking to the chip: signature, fuses, lock bits ==="
if ! run $CONN -p atmega32u4 -B 32 -U lfuse:r:-:h -U hfuse:r:-:h -U efuse:r:-:h -U lock:r:-:h; then
    echo ""
    echo "Could not talk to the chip. Nothing has been changed."
    echo "Check: RST wired to the programmer, MOSI/MISO not swapped, GND connected,"
    echo "USBasp jumper on 5 V, USB-C cable unplugged. Full output: $LOG"
    exit 1
fi

echo "=== 2/3  Erase, set fuses FF D8 CB ==="
if ! run $CONN -p atmega32u4 -B 32 -e -U lock:w:0x3F:m -U efuse:w:0xcb:m -U hfuse:w:0xd8:m -U lfuse:w:0xff:m; then
    echo "Erase / fuse step failed. Full output: $LOG"; exit 1
fi

echo "=== 3/3  Write the bootloader, lock the boot section ==="
if ! run $CONN -p atmega32u4 -B 8 -U "flash:w:$HEX:i" -U lock:w:0x2F:m; then
    echo "Bootloader write failed. Run the script again. Full output: $LOG"; exit 1
fi

echo ""
echo "Done. Disconnect the programmer and plug the board into USB."
echo "It shows up as a serial port named 'Kjern Bootloader' until the first sketch is uploaded."
