#!/usr/bin/env python3
# /tools/build_release.py
# Builds dist/kjern-avr-<version>.zip from arduino/kjern-avr and writes package_kjern_index.json
# with the matching checksum and size. The version comes from arduino/kjern-avr/platform.txt.
#
# Usage: python3 tools/build_release.py
# Then:  create a GitHub release tagged v<version>, attach dist/kjern-avr-<version>.zip,
#        commit and push package_kjern_index.json.
import hashlib
import json
import os
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'arduino', 'kjern-avr')
INDEX = os.path.join(ROOT, 'package_kjern_index.json')
REPO = 'KjernNo/Kjern-32u4HID-C'

# Tools the platform runs. They are the ones "Arduino AVR Boards" 1.8.6 uses, so the IDE
# normally has them already and downloads nothing.
TOOLS = [
    {'packager': 'arduino', 'name': 'avr-gcc', 'version': '7.3.0-atmel3.6.1-arduino7'},
    {'packager': 'arduino', 'name': 'avrdude', 'version': '6.3.0-arduino17'},
]

boot_package = os.path.join(SRC, 'bootloaders', 'kjern', 'Kjern-32u4HID-C_bootloader.hex')
boot_built = os.path.join(ROOT, 'firmware', 'bootloader', 'Kjern-32u4HID-C_bootloader.hex')
if open(boot_package, 'rb').read() != open(boot_built, 'rb').read():
    sys.exit('bootloader in the package differs from firmware/bootloader, run tools/build_bootloader.py first')

version = re.search(r'^version=(\S+)', open(os.path.join(SRC, 'platform.txt')).read(), re.M).group(1)
name = 'kjern-avr-' + version
os.makedirs(os.path.join(ROOT, 'dist'), exist_ok=True)
out = os.path.join(ROOT, 'dist', name + '.zip')

with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for base, dirs, files in os.walk(SRC):
        dirs.sort()
        for f in sorted(files):
            if f.startswith('.'):
                continue
            path = os.path.join(base, f)
            info = zipfile.ZipInfo(name + '/' + os.path.relpath(path, SRC).replace(os.sep, '/'))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            info.date_time = (2026, 1, 1, 0, 0, 0)
            z.writestr(info, open(path, 'rb').read())

data = open(out, 'rb').read()
index = {'packages': [{
    'name': 'kjern',
    'maintainer': 'Kjern',
    'websiteURL': 'https://www.kjern.no',
    'email': 'kontakt@kjern.no',
    'help': {'online': 'https://github.com/' + REPO},
    'platforms': [{
        'name': 'Kjern AVR Boards',
        'architecture': 'avr',
        'version': version,
        'category': 'Contributed',
        'url': 'https://github.com/%s/releases/download/v%s/%s.zip' % (REPO, version, name),
        'archiveFileName': name + '.zip',
        'checksum': 'SHA-256:' + hashlib.sha256(data).hexdigest(),
        'size': str(len(data)),
        'help': {'online': 'https://github.com/' + REPO},
        'boards': [{'name': 'Kjern-32u4HID-C'}],
        'toolsDependencies': TOOLS,
    }],
    'tools': [],
}]}
with open(INDEX, 'w', newline='\n') as f:
    json.dump(index, f, indent=2)
    f.write('\n')
print('%s\n  %d bytes, %s\n  release tag: v%s' % (os.path.relpath(out, ROOT), len(data), index['packages'][0]['platforms'][0]['checksum'], version))
