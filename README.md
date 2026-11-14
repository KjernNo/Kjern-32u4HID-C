<!-- /README.md -->
# Kjern-32u4HID-C

ATmega32U4 board with USB-C, made for keyboards, macro pads and other USB HID devices.
18 x 32 mm, 20 castellated pins, Arduino compatible. Designed and built by [Kjern](https://kjern.no) in Bergen.

Getting started: <https://kjern.no/quick-start/kjern-32u4hid-c>

## What's in here

| Path | What |
|---|---|
| `arduino/kjern-avr/` | The "Kjern AVR Boards" package for the Arduino IDE: board definition, pin map, bootloader, KjernBoard library and examples |
| `package_kjern_index.json` | Boards Manager index. The URL to paste into the Arduino IDE |
| `firmware/bootloader/` | The bootloader (Arduino Caterina with Kjern USB IDs), plus the untouched upstream file it is built from |
| `tools/build_bootloader.py` | Builds the bootloader from upstream Caterina |
| `tools/usb_ids.py` | The USB IDs, defined once. `--check` verifies the rest of the repo |
| `tools/flash.sh` | Bootloader over ISP, sketches over USB, and a production loop |
| `tools/build_release.py` | Builds a board package release and updates the index |
| `tools/linux/99-kjern.rules` | udev rules for Linux |
| `docs/usb-ids.md` | Which USB IDs the board uses, and why |

## Arduino IDE

File, Preferences, Additional boards manager URLs:

```
https://raw.githubusercontent.com/KjernNo/Kjern-32u4HID-C/main/package_kjern_index.json
```

Then Tools, Board, Boards Manager, search for "Kjern" and install **Kjern AVR Boards**.
It uses the compiler and core from Arduino AVR Boards, so nothing else needs downloading.

On Linux, install the udev rules once so the port can be opened without root:

```
sudo cp tools/linux/99-kjern.rules /etc/udev/rules.d/ && sudo udevadm control --reload-rules
```

## Flashing

Everything goes through `tools/flash.sh` (Linux and macOS). It finds avrdude on PATH or in an
Arduino IDE install.

```sh
tools/flash.sh list                         # connected boards and their USB IDs
tools/flash.sh bootloader                   # new board, USBasp: fuses + bootloader + lock bits
tools/flash.sh bootloader -c stk500v1 -P /dev/ttyACM0   # Arduino as ISP
tools/flash.sh sketch build/Blink.ino.hex   # upload over USB, like the Arduino IDE does
tools/flash.sh sketch path/to/MySketch      # compile with arduino-cli first, then upload
tools/flash.sh factory                      # production: ISP, then SelfTest over USB, board after board
```

The ISP wiring is at the top of `tools/flash.sh`. On Windows, `tools/isp/burn_bootloader.bat`
installs the bootloader with a USBasp.

### Bootloader behaviour

| Situation | What happens |
|---|---|
| Power on with a sketch in flash | The sketch starts straight away |
| No sketch in flash | Stays in the bootloader |
| RESET button | Bootloader for 8 seconds, then the sketch |
| Port opened at 1200 baud and closed | Bootloader for 8 seconds (this is how uploads start) |

The LED on D13 fades in and out while the bootloader runs. Fuses are low `FF`, high `D8`, extended `CB`, lock `2F`.

## USB IDs

| VID:PID | |
|---|---|
| `1209:4B4A` | running sketch |
| `1209:4B4C` | bootloader |
| `1209:0001`, `1209:0002` | first Rev C batch, still recognised |

See [docs/usb-ids.md](docs/usb-ids.md).

## Making a release of the board package

1. Change `version=` in `arduino/kjern-avr/platform.txt`.
2. If the bootloader changed: `python3 tools/build_bootloader.py`.
3. `python3 tools/usb_ids.py --check && python3 tools/build_release.py`
4. `gh release create v<version> dist/kjern-avr-<version>.zip --title "Kjern AVR Boards <version>"`
5. Commit and push `package_kjern_index.json` **after** the release exists, or the Boards Manager
   tries to download a file that isn't there yet.

## Licence

Apache-2.0, see [LICENSE](LICENSE). The bootloader is Arduino Caterina on LUFA and keeps its own
licence, see [firmware/bootloader/NOTICE.txt](firmware/bootloader/NOTICE.txt).
