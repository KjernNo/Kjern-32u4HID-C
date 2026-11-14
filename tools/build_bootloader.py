#!/usr/bin/env python3
# /tools/build_bootloader.py
#
# Builds the Kjern-32u4HID-C bootloader from the official Arduino Leonardo bootloader (Caterina).
#
# The machine code is the stock, field-proven Caterina build that ships with the Arduino IDE.
# Only data and ten single-word LED instructions are changed:
#   1. USB vendor/product ID (from tools/usb_ids.py) and the two USB strings (they live in the .data image), plus the
#      two "ldi r18, <descriptor size>" immediates that tell the USB stack how long they are
#   2. every write to PB0 and PD5 (Leonardo RX/TX LEDs) becomes a NOP, so the bootloader never
#      drives those pins. PB0 is a user pin on the castellated edge, PD5 is not connected.
#      The "L" LED on PC7 keeps breathing while the bootloader is active.
# The factory sketch that Arduino bundles below 0x7000 is dropped, only 0x7000..0x7FFF is kept.
#
# Usage: python3 tools/build_bootloader.py
# Output: firmware/bootloader/Kjern-32u4HID-C_bootloader.hex
#         arduino/kjern-avr/bootloaders/kjern/Kjern-32u4HID-C_bootloader.hex (same file)
import hashlib
import os
import shutil
import sys

# ---- identity --------------------------------------------------------------------------------
# The USB IDs live in tools/usb_ids.py so the bootloader, boards.txt and the udev rules can't drift.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from usb_ids import VID as USB_VID, PID_BOOTLOADER as USB_PID_BOOTLOADER  # noqa: E402

PRODUCT_STRING = 'Kjern Bootloader'   # max 16 characters
MANUFACTURER_STRING = 'Kjern'         # max 11 characters
# ---------------------------------------------------------------------------------------------

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UPSTREAM = os.path.join(ROOT, 'firmware', 'bootloader', 'upstream', 'Caterina-Leonardo.hex')
UPSTREAM_SHA256 = '2127dde14f22f9871fefe3b55361458489c32f89feb2de21a2157b2459d5b86e'
OUT = os.path.join(ROOT, 'firmware', 'bootloader', 'Kjern-32u4HID-C_bootloader.hex')
OUT_PACKAGE = os.path.join(ROOT, 'arduino', 'kjern-avr', 'bootloaders', 'kjern', 'Kjern-32u4HID-C_bootloader.hex')

BOOT_START = 0x7000
FLASH_END = 0x8000
NOP = bytes([0x00, 0x00])

# address -> (expected opcode bytes, meaning). Checked before patching so a different
# upstream build can never be patched by accident.
LED_WRITES = {
    0x70FE: ('5d9a', 'sbi PORTD,5  TX LED off, StartSketch'),
    0x7100: ('289a', 'sbi PORTB,0  RX LED off, StartSketch'),
    0x716C: ('5d9a', 'sbi PORTD,5  TX LED off, timer ISR'),
    0x7188: ('289a', 'sbi PORTB,0  RX LED off, timer ISR'),
    0x721C: ('5d98', 'cbi PORTD,5  TX LED on'),
    0x725A: ('2898', 'cbi PORTB,0  RX LED on'),
    0x77D6: ('209a', 'sbi DDRB,0   RX LED pin as output'),
    0x77D8: ('559a', 'sbi DDRD,5   TX LED pin as output'),
    0x77E4: ('5d9a', 'sbi PORTD,5  TX LED off, init'),
    0x77E6: ('289a', 'sbi PORTB,0  RX LED off, init'),
}
VID_ADDR, PID_ADDR = 0x7F4F, 0x7F51
PRODUCT_ADDR, PRODUCT_MAX = 0x7F9B, 16          # string descriptor: bLength, 0x03, UTF-16LE text
MANUF_ADDR, MANUF_MAX = 0x7FBF, 11
PRODUCT_SIZE_LDI = 0x78D8                       # ldi r18, sizeof(ProductString) in the descriptor callback
MANUF_SIZE_LDI = 0x78E6                         # ldi r18, sizeof(ManufNameString)


def read_hex(path):
    mem, base = {}, 0
    for line in open(path):
        line = line.strip()
        if not line:
            continue
        raw = bytes.fromhex(line[1:])
        if sum(raw) & 0xFF:
            sys.exit('bad checksum in ' + path)
        n, addr, rtype, data = raw[0], (raw[1] << 8) | raw[2], raw[3], raw[4:-1]
        if rtype == 0:
            for i, b in enumerate(data):
                mem[base + addr + i] = b
        elif rtype == 2:
            base = int.from_bytes(data, 'big') << 4
        elif rtype == 4:
            base = int.from_bytes(data, 'big') << 16
    return mem


def write_hex(path, mem, start, end):
    lines = []
    addr = start
    while addr < end:
        chunk = bytes(mem[a] for a in range(addr, min(addr + 16, end)))
        rec = bytes([len(chunk), (addr >> 8) & 0xFF, addr & 0xFF, 0]) + chunk
        lines.append(':' + (rec + bytes([(-sum(rec)) & 0xFF])).hex().upper())
        addr += len(chunk)
    lines.append(':00000001FF')
    with open(path, 'w', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')


def expect(mem, addr, data, what):
    have = bytes(mem[addr + i] for i in range(len(data)))
    if have != data:
        sys.exit('unexpected upstream bytes at %#06x (%s): %s' % (addr, what, have.hex()))


def put(mem, addr, data):
    for i, b in enumerate(data):
        mem[addr + i] = b


def ldi_r18(value):
    return bytes([0x20 | (value & 0x0F), 0xE0 | (value >> 4)])


def patch_string(mem, addr, size_ldi, old, new, max_chars):
    if len(new) > max_chars or not new:
        sys.exit('"%s" must be 1 to %d characters' % (new, max_chars))
    old_size, new_size = 2 + 2 * len(old), 2 + 2 * len(new)
    expect(mem, addr, bytes([old_size, 0x03]) + old.encode('utf-16le'), 'string ' + old)
    expect(mem, size_ldi, ldi_r18(old_size), 'size of string ' + old)
    put(mem, addr, bytes([new_size, 0x03]) + new.encode('utf-16le') + bytes(old_size - new_size))
    put(mem, size_ldi, ldi_r18(new_size))


def main():
    if hashlib.sha256(open(UPSTREAM, 'rb').read()).hexdigest() != UPSTREAM_SHA256:
        sys.exit('upstream Caterina-Leonardo.hex is not the expected file')
    mem = read_hex(UPSTREAM)
    last = max(a for a in mem if a >= BOOT_START)
    for a in range(BOOT_START, FLASH_END):
        mem.setdefault(a, 0xFF)

    for addr, (opcode, what) in sorted(LED_WRITES.items()):
        expect(mem, addr, bytes.fromhex(opcode), what)
        put(mem, addr, NOP)

    expect(mem, VID_ADDR, bytes.fromhex('41233600'), 'Arduino VID/PID')
    put(mem, VID_ADDR, USB_VID.to_bytes(2, 'little'))
    put(mem, PID_ADDR, USB_PID_BOOTLOADER.to_bytes(2, 'little'))
    patch_string(mem, PRODUCT_ADDR, PRODUCT_SIZE_LDI, 'Arduino Leonardo', PRODUCT_STRING, PRODUCT_MAX)
    patch_string(mem, MANUF_ADDR, MANUF_SIZE_LDI, 'Arduino LLC', MANUFACTURER_STRING, MANUF_MAX)

    os.makedirs(os.path.dirname(OUT_PACKAGE), exist_ok=True)
    write_hex(OUT, mem, BOOT_START, last + 1)
    shutil.copyfile(OUT, OUT_PACKAGE)
    data = open(OUT, 'rb').read()
    print('%s\n  %d bytes of code at %#06x..%#06x, USB %04X:%04X "%s" by "%s"\n  sha256 %s' % (
        os.path.relpath(OUT, ROOT), last + 1 - BOOT_START, BOOT_START, last, USB_VID, USB_PID_BOOTLOADER,
        PRODUCT_STRING, MANUFACTURER_STRING, hashlib.sha256(data).hexdigest()))


if __name__ == '__main__':
    main()
