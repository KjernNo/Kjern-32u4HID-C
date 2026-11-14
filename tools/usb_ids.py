#!/usr/bin/env python3
# /tools/usb_ids.py
#
# The one place the Kjern USB IDs are defined. build_bootloader.py reads them from here, and
# `python3 tools/usb_ids.py --check` makes sure boards.txt and the udev rules agree.
#
# Kjern has no USB-IF vendor ID. The IDs come from pid.codes, which hands out free product IDs
# under its vendor ID 0x1209 to open source hardware projects:
#
#   1209:4B4A   Kjern-32u4HID-C            a running sketch (USB serial + keyboard/mouse)
#   1209:4B4C   Kjern-32u4HID-C Bootloader the Caterina bootloader, AVR109 over USB serial
#
# 0x4B4A is "KJ" in ASCII. 0x4B4B was already taken, so the bootloader got 0x4B4C.
# Both are requested from pid.codes (see docs/usb-ids.md) and must not be shipped before that
# request is merged.
#
# LEGACY are the pid.codes *test* IDs the first Rev C boards shipped with. They are not ours to
# keep using, but boards out there still have that bootloader, so the board package, the udev
# rules and Kjern IDE keep recognising them. Nothing new is built with them.
import os
import re
import sys

VID = 0x1209
PID_SKETCH = 0x4B4A
PID_BOOTLOADER = 0x4B4C

LEGACY = [(0x1209, 0x0001, 'sketch'), (0x1209, 0x0002, 'bootloader')]

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def all_ids():
    """(vid, pid, role) for every ID a Kjern-32u4HID-C can show up with, current ones first."""
    return [(VID, PID_SKETCH, 'sketch'), (VID, PID_BOOTLOADER, 'bootloader')] + LEGACY


def check():
    problems = []
    boards = open(os.path.join(ROOT, 'arduino', 'kjern-avr', 'boards.txt')).read()

    def prop(key):
        m = re.search(r'^kjern32u4hidc\.' + re.escape(key) + r'=(\S+)', boards, re.M)
        return int(m.group(1), 16) if m else None

    if prop('build.vid') != VID or prop('build.pid') != PID_SKETCH:
        problems.append('boards.txt: build.vid/build.pid must be %04X:%04X' % (VID, PID_SKETCH))
    listed = set()
    for i in range(16):
        v, p = prop('vid.%d' % i), prop('pid.%d' % i)
        if v is not None and p is not None:
            listed.add((v, p))
    ports = set()
    for i in range(16):
        v, p = prop('upload_port.%d.vid' % i), prop('upload_port.%d.pid' % i)
        if v is not None and p is not None:
            ports.add((v, p))
    rules = open(os.path.join(ROOT, 'tools', 'linux', '99-kjern.rules')).read().lower()
    for v, p, role in all_ids():
        if (v, p) not in listed:
            problems.append('boards.txt: %04X:%04X (%s) missing from vid.N/pid.N' % (v, p, role))
        if (v, p) not in ports:
            problems.append('boards.txt: %04X:%04X (%s) missing from upload_port.N' % (v, p, role))
        if 'idvendor}=="%04x", attrs{idproduct}=="%04x"' % (v, p) not in rules:
            problems.append('99-kjern.rules: %04X:%04X (%s) missing' % (v, p, role))
    return problems


if __name__ == '__main__':
    if '--check' in sys.argv:
        found = check()
        for p in found:
            print(p)
        print('USB IDs consistent' if not found else '%d problem(s)' % len(found))
        sys.exit(1 if found else 0)
    for v, p, role in all_ids():
        print('%04X:%04X  %-10s %s' % (v, p, role, '' if (v, p, role) not in LEGACY else '(legacy, recognised only)'))
