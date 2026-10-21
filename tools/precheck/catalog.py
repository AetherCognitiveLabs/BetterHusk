#!/usr/bin/env python3
"""catalog/source.json is the seeded default source: a malformed entry breaks the
Discover tab silently. Shape-check it in the precheck, where a typo fails in seconds.

  catalog.py [catalog/source.json]
"""
import json, sys

path = sys.argv[1] if len(sys.argv) > 1 else 'catalog/source.json'
src = json.load(open(path, encoding='utf-8'))
errors = []

for key in ('name', 'identifier'):
    if not isinstance(src.get(key), str) or not src[key]:
        errors.append('source: missing %s' % key)

ROUTES = {'tl', 'android', 'heuristic'}
REQUIRED = ('name', 'bundleIdentifier', 'version', 'downloadURL', 'iconURL', 'localizedDescription')
seen = set()
for i, app in enumerate(src.get('apps') or []):
    where = 'apps[%d] (%s)' % (i, app.get('bundleIdentifier') or app.get('name') or '?')
    for key in REQUIRED:
        if not isinstance(app.get(key), str) or not app[key]:
            errors.append('%s: missing %s' % (where, key))
    route = app.get('route')
    if route is not None and route not in ROUTES:
        errors.append('%s: route %r not one of %s' % (where, route, sorted(ROUTES)))
    bid = app.get('bundleIdentifier')
    if bid in seen:
        errors.append('%s: duplicate bundleIdentifier' % where)
    seen.add(bid)
    for key in ('downloadURL', 'iconURL'):
        url = app.get(key) or ''
        if url and not url.startswith('https://'):
            errors.append('%s: %s is not https' % (where, key))
    dl = app.get('downloadURL') or ''
    if dl and not dl.endswith('.apk'):
        errors.append('%s: downloadURL does not end in .apk' % where)

if not src.get('apps'):
    errors.append('source: no apps')

# Every route:tl entry must carry javagap evidence at its pinned versionCode: the
# Translation Layer is what loads husk-framework.dex, and an unprobed game is a
# coin flip on missing framework APIs. catalog/probes.json is filled by the
# compat workflow (javagap.py); android-route entries are recorded as evidence too.
import os, re
probes_path = os.path.join(os.path.dirname(path), 'probes.json')
probes = {}
try:
    probes = json.load(open(probes_path, encoding='utf-8')).get('apps') or {}
except OSError:
    pass
for app in src.get('apps') or []:
    if app.get('route') != 'tl':
        continue
    bid = app.get('bundleIdentifier') or ''
    where = 'app %s' % (bid or app.get('name') or '?')
    probe = probes.get(bid)
    if probe is None:
        errors.append('%s: route tl but no entry in catalog/probes.json' % where)
        continue
    if probe.get('missingClasses') != 0 or probe.get('missingMembers') != 0:
        errors.append('%s: probe records %s missing classes / %s missing members' %
                      (where, probe.get('missingClasses'), probe.get('missingMembers')))
    m = re.search(r'_(\d+)\.apk$', app.get('downloadURL') or '')
    if m and probe.get('versionCode') != int(m.group(1)):
        errors.append('%s: probe versionCode %s does not match pinned %s' %
                      (where, probe.get('versionCode'), m.group(1)))

for e in errors:
    print('::error file=%s::%s' % (path, e))
print('catalog: %d app entries checked, %d errors' % (len(src.get('apps') or []), len(errors)))
sys.exit(1 if errors else 0)
