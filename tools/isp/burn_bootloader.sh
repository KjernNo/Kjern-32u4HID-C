#!/bin/sh
# /tools/isp/burn_bootloader.sh
# One-time install of the Kjern bootloader with an ISP programmer (macOS and Linux).
# Kept for older instructions. It now just runs tools/flash.sh, which does the work.
#
# Usage:  sh tools/isp/burn_bootloader.sh                                (USBasp)
#         sh tools/isp/burn_bootloader.sh stk500v1 /dev/cu.usbmodemXXXX  (Arduino as ISP)
HERE="$(cd "$(dirname "$0")" && pwd)"
PROG="${1:-usbasp}"
if [ -n "$2" ]; then exec bash "$HERE/../flash.sh" bootloader -c "$PROG" -P "$2"; fi
exec bash "$HERE/../flash.sh" bootloader -c "$PROG"
