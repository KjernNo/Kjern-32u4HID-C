#!/usr/bin/env python3
# /tools/build_release.py
# Builds dist/kjern-avr-<version>.zip from arduino/kjern-avr and rewrites package_kjern_index.json
# with the new version, checksum and size. Usage: python3 tools/build_release.py
# Version comes from arduino/kjern-avr/platform.txt. Existing versions in the index are kept.
import hashlib, json, os, re, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'arduino', 'kjern-avr')
INDEX = os.path.join(ROOT, 'package_kjern_index.json')
REPO = 'KjernNo/Kjern-32u4HID-C'

version = re.search(r'^version=(\S+)', open(os.path.join(SRC, 'platform.txt')).read(), re.M).group(1)
name = f'kjern-avr-{version}'
os.makedirs(os.path.join(ROOT, 'dist'), exist_ok=True)
out = os.path.join(ROOT, 'dist', name + '.zip')

with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for base, _, files in os.walk(SRC):
        for f in sorted(files):
            p = os.path.join(base, f)
            info = zipfile.ZipInfo(os.path.join(name, os.path.relpath(p, SRC)))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (0o755 if f.endswith('.sh') else 0o644) << 16
            info.date_time = (2026, 1, 1, 0, 0, 0)
            z.writestr(info, open(p, 'rb').read())

data = open(out, 'rb').read()
entry = {
    'name': 'Kjern AVR Boards', 'architecture': 'avr', 'version': version, 'category': 'Contributed',
    'url': f'https://github.com/{REPO}/releases/download/v{version}/{name}.zip',
    'archiveFileName': f'{name}.zip', 'checksum': 'SHA-256:' + hashlib.sha256(data).hexdigest(),
    'size': str(len(data)), 'help': {'online': f'https://github.com/{REPO}'},
    'boards': [{'name': 'Kjern-32u4HID-C'}], 'toolsDependencies': [],
}
idx = json.load(open(INDEX)) if os.path.exists(INDEX) else {'packages': [{
    'name': 'kjern', 'maintainer': 'Kjern', 'websiteURL': 'https://www.kjern.no', 'email': 'kontakt@kjern.no',
    'help': {'online': f'https://github.com/{REPO}'}, 'platforms': [], 'tools': []}]}
plats = [p for p in idx['packages'][0]['platforms'] if p['version'] != version] + [entry]
idx['packages'][0]['platforms'] = sorted(plats, key=lambda p: [int(x) for x in p['version'].split('.')])
json.dump(idx, open(INDEX, 'w'), indent=2)
open(INDEX, 'a').write('\n')
print(f'{out}\n{entry["checksum"]}  {entry["size"]} bytes\nupload it to release v{version}, then commit package_kjern_index.json')
