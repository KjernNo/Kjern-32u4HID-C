#!/bin/sh
# /tools/kjern-dfu-upload.sh
# Waits for the Kjern-32u4HID-C to appear as Atmel DFU (03eb:2ff4), then erases, flashes and starts the sketch.
HEX="$1"
DFU="${DFU_PROGRAMMER:-dfu-programmer}"
MCU=atmega32u4

if ! command -v "$DFU" >/dev/null 2>&1; then
    echo "dfu-programmer not found. Install it (Linux: apt install dfu-programmer, macOS: brew install dfu-programmer)."
    exit 1
fi

echo "Waiting for Kjern-32u4HID-C in DFU mode (03eb:2ff4)..."
i=0
until "$DFU" $MCU get bootloader-version >/dev/null 2>&1; do
    i=$((i + 1))
    if [ $i -gt 60 ]; then
        echo "No DFU device found. Unplug, tie PB0 to GND, plug back in (board becomes ATm32U4DFU), then upload again."
        exit 1
    fi
    sleep 0.25
done

"$DFU" $MCU erase --force || exit 1
"$DFU" $MCU flash "$HEX" || exit 1
"$DFU" $MCU launch 2>/dev/null || "$DFU" $MCU start 2>/dev/null || "$DFU" $MCU reset
echo "Done. Sketch is running."
