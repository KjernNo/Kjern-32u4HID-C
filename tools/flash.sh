#!/usr/bin/env bash
# /tools/flash.sh
#
# Flashing tool for the Kjern-32u4HID-C, for Linux and macOS.
#
#   tools/flash.sh bootloader [-c usbasp|stk500v1|...] [-P port]
#       Installs the Kjern bootloader with an ISP programmer: erase, fuses FF D8 CB,
#       bootloader at 0x7000 (written and verified), lock bits 2F.
#
#   tools/flash.sh sketch <file.hex | sketch folder | file.ino> [-P port]
#       Uploads a sketch over USB, the same way the Arduino IDE does: 1200 baud touch,
#       wait for the bootloader port, avrdude -c avr109. A sketch folder or .ino is compiled
#       first with arduino-cli. Without -P the board is found by its USB ID.
#
#   tools/flash.sh factory [<file.hex | sketch folder>] [-c programmer] [-P isp-port]
#       Production loop: bootloader over ISP, then plug in USB-C and the first sketch goes on
#       over USB. Defaults to the SelfTest example. Every board is logged to tools/factory.log.
#
#   tools/flash.sh list
#       Shows connected Kjern boards and which USB ID they use.
#
# ISP wiring (USBasp 10-pin header, USB-C unplugged, USBasp jumper on 5 V):
#   1 MOSI -> MOSI (TP12 or J1 pin 10)      7 SCK  -> SCK  (TP11 or J2 pin 9)
#   2 VCC  -> +5V  (J2 pin 3)               9 MISO -> MISO (TP13 or J1 pin 9)
#   5 RST  -> RST  (TP15, or the RST pad of the reset button)
#   4/6/8/10 GND -> GND (J2 pin 1 or 2)
# RST has to be wired. Holding the reset button by hand does not work reliably.
#
# avrdude comes from PATH, or from an Arduino IDE install (Arduino AVR Boards).
# arduino-cli is only needed to compile sketches.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
HEX_BOOT="$ROOT/firmware/bootloader/Kjern-32u4HID-C_bootloader.hex"
SELFTEST="$ROOT/arduino/kjern-avr/libraries/KjernBoard/examples/SelfTest"
FQBN="kjern:avr:kjern32u4hidc"
LOG="$HERE/flash.log"
FACTORY_LOG="$HERE/factory.log"

# USB IDs, see tools/usb_ids.py. The 0001/0002 pair is what the first Rev C boards shipped with.
VID="1209"
SKETCH_PIDS="4b4a 0001"
BOOT_PIDS="4b4c 0002"

FUSE_L=0xff
FUSE_H=0xd8
FUSE_E=0xcb
LOCK_OPEN=0x3f
LOCK_BOOT=0x2f

if [ -t 1 ]; then B=$'\e[1m'; G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; N=$'\e[0m'; else B='' G='' R='' Y='' N=''; fi
say()  { printf '%s\n' "${B}==> $*${N}"; }
ok()   { printf '%s\n' "${G}ok${N}  $*"; }
warn() { printf '%s\n' "${Y}!!${N}  $*"; }
die()  { printf '%s\n' "${R}xx${N}  $*" >&2; exit 1; }

OS="$(uname -s)"
SYSFS="${KJERN_SYSFS:-/sys}"

# ---- tools --------------------------------------------------------------------------------------
AVRDUDE="" AVRCONF=""
find_avrdude() {
    [ -n "$AVRDUDE" ] && return 0
    if command -v avrdude >/dev/null 2>&1; then AVRDUDE="$(command -v avrdude)"; return 0; fi
    local d
    for d in "$HOME/Library/Arduino15/packages/arduino/tools/avrdude"/* \
             "$HOME/.arduino15/packages/arduino/tools/avrdude"/* \
             "$HOME/snap/arduino/current/.arduino15/packages/arduino/tools/avrdude"/*; do
        if [ -x "$d/bin/avrdude" ]; then AVRDUDE="$d/bin/avrdude"; AVRCONF="$d/etc/avrdude.conf"; fi
    done
    [ -n "$AVRDUDE" ] || die "avrdude not found. Install it (apt install avrdude / brew install avrdude) or the Arduino IDE with Arduino AVR Boards."
}

avrdude_run() {
    find_avrdude
    local args=("$@")
    [ -n "$AVRCONF" ] && args=(-C "$AVRCONF" "${args[@]}")
    printf '\n> avrdude %s\n' "${args[*]}" >> "$LOG"
    "$AVRDUDE" "${args[@]}" >> "$LOG" 2>&1
}

compile() {
    # $1: sketch folder or .ino. Prints the path of the built .hex.
    local src="$1" dir out
    command -v arduino-cli >/dev/null 2>&1 || die "arduino-cli is needed to compile $src. Pass a .hex instead, or install arduino-cli."
    [ -f "$src" ] && src="$(dirname "$src")"
    dir="$(cd "$src" && pwd)" || die "No such sketch: $1"
    out="$(mktemp -d "${TMPDIR:-/tmp}/kjern-build.XXXXXX")"
    say "Compiling $(basename "$dir")" >&2
    arduino-cli compile --fqbn "$FQBN" --output-dir "$out" "$dir" >> "$LOG" 2>&1 \
        || die "Compile failed. Is 'Kjern AVR Boards' installed in arduino-cli? Output: $LOG"
    local f
    for f in "$out"/*.ino.hex; do
        case "$f" in *with_bootloader*) ;; *) [ -f "$f" ] && { printf '%s\n' "$f"; return 0; } ;; esac
    done
    die "arduino-cli did not produce a .hex. Output: $LOG"
}

resolve_hex() {
    case "$1" in
        *.hex) [ -f "$1" ] || die "No such file: $1"; printf '%s\n' "$1" ;;
        *)     compile "$1" ;;
    esac
}

# ---- finding the board --------------------------------------------------------------------------
# Prints "port vid pid" for every USB serial port.
list_ports() {
    if [ "$OS" = "Linux" ]; then
        local t dev
        for t in "$SYSFS"/class/tty/ttyACM* "$SYSFS"/class/tty/ttyUSB*; do
            [ -e "$t/device" ] || continue
            dev="$(readlink -f "$t/device")"
            while [ "$dev" != "/" ] && [ ! -f "$dev/idVendor" ]; do dev="$(dirname "$dev")"; done
            [ -f "$dev/idVendor" ] || continue
            printf '/dev/%s %s %s\n' "$(basename "$t")" "$(cat "$dev/idVendor")" "$(cat "$dev/idProduct")"
        done
    elif [ "$OS" = "Darwin" ]; then
        ioreg -r -c IOUSBHostDevice -l -w0 2>/dev/null | awk '
            /"idVendor" = /       { v = sprintf("%04x", $NF) }
            /"idProduct" = /      { p = sprintf("%04x", $NF) }
            /"IOCalloutDevice" = / { gsub(/"/, "", $NF); print $NF, v, p }'
    fi
}

ports_matching() {
    # $1: list of PIDs. Prints matching ports.
    local port vid pid want
    list_ports | while read -r port vid pid; do
        [ "$vid" = "$VID" ] || continue
        for want in $1; do [ "$pid" = "$want" ] && printf '%s\n' "$port"; done
    done
}

wait_for_port() {
    # $1: PIDs, $2: seconds, $3: ports to ignore. Prints the first new matching port.
    local pids="$1" secs="$2" skip="${3:-}" end p
    end=$(( $(date +%s) + secs ))
    while [ "$(date +%s)" -lt "$end" ]; do
        for p in $(ports_matching "$pids"); do
            case " $skip " in *" $p "*) ;; *) printf '%s\n' "$p"; return 0 ;; esac
        done
        sleep 0.2
    done
    return 1
}

touch_1200() {
    # Opening the port at 1200 baud and closing it makes the sketch jump to the bootloader.
    if [ "$OS" = "Darwin" ]; then stty -f "$1" 1200 hupcl 2>/dev/null; else stty -F "$1" 1200 hupcl 2>/dev/null; fi
}

# ---- commands -----------------------------------------------------------------------------------
cmd_list() {
    local port vid pid kind found=0
    while read -r port vid pid; do
        [ "$vid" = "$VID" ] || continue
        case " $SKETCH_PIDS " in *" $pid "*) kind="sketch running";; *)
        case " $BOOT_PIDS " in *" $pid "*) kind="in the bootloader";; *) continue;; esac;; esac
        case "$pid" in 0001|0002) kind="$kind, old test ID (first Rev C batch)";; esac
        printf '%-22s %s:%s  Kjern-32u4HID-C, %s\n' "$port" "$vid" "$pid" "$kind"
        found=1
    done < <(list_ports)
    [ "$found" = 1 ] || echo "No Kjern board found. Plug it straight into the computer and try again."
}

cmd_bootloader() {
    local prog="usbasp" port=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -c) prog="$2"; shift 2 ;;
            -P) port="$2"; shift 2 ;;
            *) die "Unknown option: $1" ;;
        esac
    done
    [ -f "$HEX_BOOT" ] || die "Bootloader missing: $HEX_BOOT (run python3 tools/build_bootloader.py)"
    local conn=(-p atmega32u4 -c "$prog")
    [ -n "$port" ] && conn+=(-P "$port" -b 19200)
    : > "$LOG"

    say "1/3  Talking to the chip"
    if ! avrdude_run "${conn[@]}" -B 32 -U lfuse:r:-:h -U hfuse:r:-:h -U efuse:r:-:h -U lock:r:-:h; then
        printf '%s\n' "Could not talk to the chip. Nothing was changed." \
            "Check: RST wired, MOSI/MISO not swapped, GND connected, USBasp jumper on 5 V, USB-C unplugged." \
            "Full output: $LOG"
        return 1
    fi
    ok "ATmega32U4 found"

    say "2/3  Erase and set fuses ($FUSE_L $FUSE_H $FUSE_E)"
    avrdude_run "${conn[@]}" -B 32 -e -U lock:w:$LOCK_OPEN:m -U efuse:w:$FUSE_E:m -U hfuse:w:$FUSE_H:m -U lfuse:w:$FUSE_L:m \
        || { echo "Erase or fuse write failed. Full output: $LOG"; return 1; }
    ok "fuses set"

    say "3/3  Write and verify the bootloader, lock the boot section"
    avrdude_run "${conn[@]}" -B 8 -U "flash:w:$HEX_BOOT:i" -U lock:w:$LOCK_BOOT:m \
        || { echo "Bootloader write failed. Run it again. Full output: $LOG"; return 1; }
    ok "bootloader written and verified"
    return 0
}

upload_over_usb() {
    # $1: hex, $2: port or empty. Uses the bootloader port if the board is already there.
    local hex="$1" port="$2" boot before
    : >> "$LOG"
    boot="$(ports_matching "$BOOT_PIDS" | head -1)"
    if [ -z "$boot" ]; then
        if [ -z "$port" ]; then
            port="$(ports_matching "$SKETCH_PIDS" | head -1)"
            [ -n "$port" ] || die "No Kjern board found. Plug it in, or press RESET and run this again within 8 seconds."
        fi
        before="$(ports_matching "$BOOT_PIDS" | tr '\n' ' ')"
        say "Restarting $port into the bootloader"
        touch_1200 "$port"
        boot="$(wait_for_port "$BOOT_PIDS" 10 "$before")" || boot=""
        if [ -z "$boot" ]; then
            warn "The board did not restart by itself. Press RESET on the board now."
            boot="$(wait_for_port "$BOOT_PIDS" 20 "")" || die "No bootloader port showed up."
        fi
    fi
    say "Uploading $(basename "$hex") on $boot"
    avrdude_run -p atmega32u4 -c avr109 -P "$boot" -b 57600 -D -U "flash:w:$hex:i" \
        || die "Upload failed. Full output: $LOG"
    ok "uploaded and verified"
}

cmd_sketch() {
    local src="" port=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -P) port="$2"; shift 2 ;;
            -*) die "Unknown option: $1" ;;
            *) src="$1"; shift ;;
        esac
    done
    [ -n "$src" ] || die "Usage: tools/flash.sh sketch <file.hex | sketch folder> [-P port]"
    local hex
    hex="$(resolve_hex "$src")" || exit 1
    : > "$LOG"
    upload_over_usb "$hex" "$port"
    if wait_for_port "$SKETCH_PIDS" 8 "" >/dev/null; then ok "board is running the sketch"
    else warn "Upload went fine, but no USB serial port came back. Normal if the sketch does not use USB."; fi
}

cmd_factory() {
    local src="$SELFTEST" prog="usbasp" port=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -c) prog="$2"; shift 2 ;;
            -P) port="$2"; shift 2 ;;
            -*) die "Unknown option: $1" ;;
            *) src="$1"; shift ;;
        esac
    done
    local hex
    hex="$(resolve_hex "$src")" || exit 1
    local isp=(-c "$prog")
    [ -n "$port" ] && isp+=(-P "$port")
    local n=0 boot answer
    [ -f "$FACTORY_LOG" ] && n="$(grep -c ' PASS ' "$FACTORY_LOG" 2>/dev/null || true)"
    n="${n:-0}"
    echo "Factory flashing with $(basename "$hex"). $n board(s) passed so far. Ctrl+C to stop."
    while true; do
        echo
        read -r -p "${B}Connect the ISP programmer to the next board (USB-C unplugged), Enter to start, q to quit: ${N}" answer
        [ "$answer" = "q" ] && break
        if ! cmd_bootloader "${isp[@]}"; then
            printf '%s FAIL isp\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "$FACTORY_LOG"
            continue
        fi
        echo
        echo "${B}Disconnect the programmer and plug the board into USB-C.${N}"
        boot="$(wait_for_port "$BOOT_PIDS" 90 "")" || {
            warn "No bootloader port within 90 s. Check the USB-C solder joints and the crystal."
            printf '%s FAIL usb\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "$FACTORY_LOG"
            continue
        }
        ok "enumerated as $boot"
        if ! ( upload_over_usb "$hex" "" ); then
            printf '%s FAIL upload\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "$FACTORY_LOG"
            continue
        fi
        if wait_for_port "$SKETCH_PIDS" 10 "" >/dev/null; then
            n=$((n + 1))
            printf '%s PASS #%d %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$n" "$(basename "$hex")" >> "$FACTORY_LOG"
            echo "${G}${B}PASS${N}  board #$n is done. Unplug it."
        else
            printf '%s FAIL no-sketch-port\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "$FACTORY_LOG"
            warn "The sketch is on, but the board did not come back as a serial port."
        fi
    done
    echo "$n board(s) passed in total. Log: $FACTORY_LOG"
}

usage() {
    sed -n '4,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

case "${1:-}" in
    bootloader) shift; cmd_bootloader "$@" ;;
    sketch)     shift; cmd_sketch "$@" ;;
    factory)    shift; cmd_factory "$@" ;;
    list)       shift; cmd_list ;;
    -h|--help|help|"") usage ;;
    *) usage; exit 1 ;;
esac
