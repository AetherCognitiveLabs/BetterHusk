#!/usr/bin/env python3
"""classify.py <sweep dir> [--min-frames N] -- groups a playsweep run by what went wrong.

Reads each <pkg>.log in <sweep dir>, gives every app one verdict (works, opens, or the first fatal
signature in its log), and prints the signatures most apps share first: the fixes worth making first.
"""
import argparse, collections, glob, json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from playsweep import summarise

def signature(log):
    """The first thing in a log that explains a failure, reduced to something shared across apps."""
    for line in log.splitlines():
        m = re.search(r'=== CRASH: signal (\d+)', line)
        if m:
            lib = re.search(r'pc\s+\S+\s+(\S+\.so)', log)
            return 'crash signal %s%s' % (m.group(1), ' in ' + lib.group(1) if lib else '')
        m = re.search(r"main thread ended with ([\w.$/]+)(?::\s*(.*))?", line)
        if m:
            what = m.group(2) or ''
            what = re.sub(r'0x[0-9a-f]+|\d+', '#', what)[:70]
            return 'main thread ended: %s %s' % (m.group(1).split('/')[-1], what)
        m = re.search(r'No implementation found for ([\w/$.]+)', line)
        if m:
            return 'missing native method'
        if 'start failed' in line or 'could not be started' in line:
            return 'start failed: ' + line.strip()[:70]
        m = re.search(r'NoClassDefFoundError: ([\w/$.]+)', line)
        if m and not m.group(1).startswith(('vBH', 'com/google/android/gms')):
            return 'missing class %s' % '/'.join(m.group(1).split('/')[:3])
    return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('dir')
    ap.add_argument('--min-frames', type=int, default=30, help='frames in the run that count as working')
    a = ap.parse_args()
    # from the logs, not summary.json: a summary written after a drive drop lists only the apps swept since
    verdicts = {}
    for path in sorted(glob.glob(os.path.join(a.dir, '*.log'))):
        pkg = os.path.basename(path)[:-4]
        if pkg.startswith('PlayDownload_'):
            continue
        log = open(path, errors='replace').read()
        r = summarise(log)
        r['rc'] = 0 if not r.get('crash') else 139
        frames = r.get('frames') or 0
        sig = signature(log)
        if frames >= a.min_frames and not (sig or '').startswith('crash'):
            verdicts[pkg] = 'works'
        elif frames > 0 and not sig:
            verdicts[pkg] = 'opens (few frames)'
        else:
            verdicts[pkg] = sig or ('no frames, no error' if r.get('rc') == 0 else 'exit %s, no signature' % r.get('rc'))
    groups = collections.defaultdict(list)
    for pkg, v in verdicts.items():
        groups[v].append(pkg)
    for v, pkgs in sorted(groups.items(), key=lambda kv: (kv[0] != 'works', -len(kv[1]))):
        print('%4d  %s' % (len(pkgs), v))
        if v != 'works':
            print('        ' + ', '.join(sorted(pkgs)[:8]) + (' ...' if len(pkgs) > 8 else ''))

if __name__ == '__main__':
    main()
