#!/usr/bin/env python3
# Finds String(localized: "... \(x) ...") calls whose interpolated pattern key
# is missing from the catalog. Interpolated literals are invisible to
# harvest.py by design; at runtime the lookup uses the pattern with %@ in
# place of each interpolated segment, and a missing pattern means the string
# can never be translated.
#
# Interpolations are cut depth-aware (nested parens and inner string literals
# count), so '\(f(a))' yields '%@', not '%@)'.
import io, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
XC = os.path.join(ROOT, 'src/app/Husk/Localizable.xcstrings')
LIT = re.compile(r'String\(localized:\s*"((?:[^"\\]|\\.)*)"')

def pattern_key(lit):
    out, i, n = [], 0, len(lit)
    while i < n:
        if lit[i] == '\\' and i + 1 < n and lit[i + 1] == '(':
            i += 2
            depth, ins = 1, False
            while i < n and depth:
                c = lit[i]
                if c == '\\':
                    i += 2
                    continue
                if c == '"':
                    ins = not ins
                elif not ins:
                    if c == '(':
                        depth += 1
                    elif c == ')':
                        depth -= 1
                i += 1
            out.append('%@')
        elif lit[i] == '\\' and i + 1 < n:
            out.append(lit[i:i + 2])
            i += 2
        else:
            out.append(lit[i])
            i += 1
    return ''.join(out)

def main():
    cat = json.load(io.open(XC, encoding='utf-8'))['strings']
    missing = []
    for dp, _, fs in os.walk(os.path.join(ROOT, 'src/app/Husk')):
        for f in fs:
            if not f.endswith('.swift'):
                continue
            path = os.path.join(dp, f)
            for m in LIT.finditer(io.open(path, encoding='utf-8').read()):
                lit = m.group(1)
                if '\\(' not in lit:
                    continue
                key = pattern_key(lit)
                if key not in cat:
                    missing.append((os.path.basename(path), key))
    print(f'{len(missing)} interpolated String(localized:) calls without a catalog pattern key')
    for p, k in missing:
        print(' ', p, '|', repr(k[:110]))
    if '--json' in sys.argv:
        out = os.path.join(ROOT, 'tools/i18n/interp_missing.json')
        keys = sorted(set(k for _, k in missing))
        with io.open(out, 'w', encoding='utf-8') as f:
            json.dump(keys, f, ensure_ascii=False, indent=1)
        print('wrote', out, f'({len(keys)} unique keys)')

if __name__ == '__main__':
    main()
