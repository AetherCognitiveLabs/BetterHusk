#!/usr/bin/env python3
# Harvests every string literal used in a localisable position across the app
# target's Swift sources, and diffs them against Localizable.xcstrings.
#
# Localisable positions here: Text("x"), Label("x", ...), Button("x" ...),
# Section("x"), Toggle("x", ...), Picker("x", ...), Menu("x"),
# TextField("x", ...), .navigationTitle("x"), .alert("x"), String(localized:"x"),
# and "x".l10n / x.l10n chains (the codebase's own helper -- Theme.swift:443).
#
# Usage: python tools/i18n/harvest.py        -> prints report
#        python tools/i18n/harvest.py --json -> writes tools/i18n/missing.json
import io, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
XC = os.path.join(ROOT, 'src/app/Husk/Localizable.xcstrings')
SRC_DIRS = [os.path.join(ROOT, 'src/app/Husk'), os.path.join(ROOT, 'src/app/Shared')]

# "literal" used directly inside a localising call/position.
LITERAL = r'"((?:[^"\\\n]|\\.)*)"'
PATTERNS = [
    re.compile(r'\b(?:Text|Label|Button|Section|Toggle|Picker|Menu|TextField|SecureField|Link|navigationTitle|navigationBarTitle|alert|confirmationDialog|prompt|placeholder|help|badge|title)\(\s*' + LITERAL),
    re.compile(r'String\(localized:\s*' + LITERAL),
    re.compile(r'LocalizedStringKey\(\s*' + LITERAL),
]
# "x".l10n -- the literal before the helper.
L10N = re.compile(LITERAL + r'\.l10n\b')

def swift_files():
    for d in SRC_DIRS:
        for dirpath, _, files in os.walk(d):
            for f in files:
                if f.endswith('.swift'):
                    yield os.path.join(dirpath, f)

UNICODE_ESC = re.compile(r'\\u\{([0-9A-Fa-f]+)\}')

def unescape(s):
    # Swift string escapes close enough for keys (no interpolated strings
    # survive the regex anyway -- those are excluded on purpose).
    s = UNICODE_ESC.sub(lambda m: chr(int(m.group(1), 16)), s)
    return s.replace('\\"', '"').replace("\\'", "'").replace('\\n', '\n').replace('\\\\', '\\')

def main():
    catalog = json.load(io.open(XC, encoding='utf-8-sig'))['strings']
    keys_in_catalog = set(catalog.keys())
    used = {}  # key -> set(files)
    for path in swift_files():
        text = io.open(path, encoding='utf-8').read()
        rel = os.path.relpath(path, ROOT)
        found = set()
        for pat in PATTERNS:
            found.update(m.group(1) for m in pat.finditer(text))
        found.update(m.group(1) for m in L10N.finditer(text))
        for lit in found:
            if '\\(' in lit or not lit or lit.isascii() and not lit.strip():
                continue
            used.setdefault(unescape(lit), set()).add(rel)

    missing = {k: sorted(v) for k, v in used.items() if k not in keys_in_catalog}
    stale = keys_in_catalog - set(used.keys())

    print(f'catalog keys: {len(keys_in_catalog)}')
    print(f'literals used in localisable positions: {len(used)}')
    print(f'MISSING from catalog: {len(missing)}')
    for k in sorted(missing, key=str.lower):
        print(f'  {k!r:100} <- {", ".join(os.path.basename(f) for f in missing[k])}')
    print(f'in catalog but not found by this scan (dynamic keys are fine): {len(stale)}')
    if '--json' in sys.argv:
        out = os.path.join(ROOT, 'tools/i18n/missing.json')
        with io.open(out, 'w', encoding='utf-8') as f:
            json.dump({k: v for k, v in sorted(missing.items())}, f, ensure_ascii=False, indent=1)
        print('wrote', out)

if __name__ == '__main__':
    main()
