#!/usr/bin/env python3
"""Re-derive catalog/probes.json: download each catalogued APK (into a cache),
run the javagap framework check, and write the results the precheck validates.

  probe-catalog.py [catalog/source.json] [--framework build/husk-framework.dex]

APKs land in build/apks/ under their F-Droid-style name; the manifest reports
missingClasses/missingMembers per bundleIdentifier + the pinned versionCode.
"""
import json, os, re, subprocess, sys, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CAT = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith('--') else os.path.join(ROOT, 'catalog/source.json')
FW = os.path.join(ROOT, 'build/husk-framework.dex')
if '--framework' in sys.argv:
    FW = sys.argv[sys.argv.index('--framework') + 1]
CACHE = os.path.join(ROOT, 'build/apks')
os.makedirs(CACHE, exist_ok=True)

src = json.load(open(CAT, encoding='utf-8'))
apps = {}
for app in src.get('apps') or []:
    url = app.get('downloadURL') or ''
    bid = app.get('bundleIdentifier')
    if not url.endswith('.apk') or not bid:
        continue
    apk = os.path.join(CACHE, os.path.basename(url))
    if not os.path.exists(apk):
        print('download %s' % url)
        urllib.request.urlretrieve(url, apk)
    out = subprocess.run([sys.executable, os.path.join(ROOT, 'tools/compat/javagap.py'), apk, FW],
                         capture_output=True, text=True).stdout
    head = out.splitlines()[0] if out else ''
    m = re.search(r'(\d+) framework classes missing, (\d+) present classes lacking members', head)
    if not m:
        print('javagap failed on %s' % apk, file=sys.stderr)
        continue
    vc = re.search(r'_(\d+)\.apk$', url)
    apps[bid] = {'versionCode': int(vc.group(1)) if vc else None,
                 'missingClasses': int(m.group(1)), 'missingMembers': int(m.group(2))}
    print('%-50s %s' % (bid, head))

out = {
    'comment': ('tools/compat/javagap.py results against build/husk-framework.dex for each catalogued app. '
                'tools/precheck/catalog.py requires a zero-gap entry here for every route:tl app (and records '
                'them for android apps too). Regenerate with tools/compat/probe-catalog.py.'),
    'framework': 'build/husk-framework.dex',
    'apps': apps,
}
path = os.path.join(os.path.dirname(CAT), 'probes.json')
json.dump(out, open(path, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
open(path, 'a', encoding='utf-8').write('\n')
print('wrote %s (%d apps)' % (path, len(apps)))
