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

for e in errors:
    print('::error file=%s::%s' % (path, e))
print('catalog: %d app entries checked, %d errors' % (len(src.get('apps') or []), len(errors)))
sys.exit(1 if errors else 0)
