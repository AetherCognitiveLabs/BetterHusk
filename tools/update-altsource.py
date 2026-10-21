#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""
Regenerate altsource.json, the AltStore/SideStore source, from the GitHub releases.

    python3 tools/update-altsource.py

Run it after publishing a release and commit the result. Sideloaders read the file from raw.githubusercontent.com, so a pushed
change is what they see. Each release's BetterHusk.ipa becomes a version, newest first, with its real size and date.

The identity below is the fork's: AetherCognitiveLabs/BetterHusk, com.betterhusk.app. The file this writes must be
idempotent against the committed altsource.json -- upstream's copy of this tool would clobber that identity back to
Leviidev/Husk, which is why this one carries its own.
"""
import json
import os
import re
import urllib.request

REPO = "AetherCognitiveLabs/BetterHusk"
RAW = f"https://raw.githubusercontent.com/{REPO}/main"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "altsource.json")
KEEP = 10   # how many releases to list


def project_min_os():
    """The deployment target in project.yml: what the newest release needs."""
    with open(os.path.join(ROOT, "src/app/project.yml")) as f:
        m = re.search(r'deploymentTarget:\s*\n(?:\s*#.*\n)*\s*iOS:\s*"([\d.]+)"', f.read())
    return m.group(1) if m else "16.0"


def min_os(version, newest_min):
    # Fork releases before 1.0.0 were still built from the upstream tree with
    # its iOS 16.4 floor; from 1.0.0 on, the floor is the project's.
    parts = [int(p) for p in re.findall(r"\d+", version)[:3]] + [0, 0, 0]
    return "16.4" if parts[:3] < [1, 0, 0] else newest_min


def releases():
    req = urllib.request.Request(f"https://api.github.com/repos/{REPO}/releases?per_page=30",
                                 headers={"User-Agent": "husk-altsource", "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def main():
    newest_min = project_min_os()
    versions = []
    for rel in releases():
        if rel.get("draft") or rel.get("prerelease"):
            continue
        ipa = next((a for a in rel["assets"] if a["name"].lower().endswith(".ipa")), None)
        if not ipa:
            continue
        version = rel["tag_name"].lstrip("vV")
        notes = (rel.get("body") or "").strip() or f"BetterHusk {version}."
        versions.append({
            "version": version,
            "date": rel["published_at"],
            "localizedDescription": notes[:4000],
            "downloadURL": ipa["browser_download_url"],
            "size": ipa["size"],
            "minOSVersion": min_os(version, newest_min),
        })
        if len(versions) >= KEEP:
            break

    icon = f"{RAW}/src/app/Husk/Assets.xcassets/AppIcon.appiconset/Icon-Default.png"
    shots = sorted(f for f in os.listdir(os.path.join(ROOT, "Screenshots")) if f.lower().endswith((".png", ".jpeg", ".jpg")))
    source = {
        "name": "BetterHusk",
        "identifier": "com.betterhusk.source",
        "subtitle": "Android apps and games on your iPhone — Husk, plus the fixes upstream hasn't merged.",
        "description": ("The official source for BetterHusk, a community fork of Leviidev's Husk. Add it to SideStore, "
                        "AltStore or another sideloader to install BetterHusk and get its updates. BetterHusk installs "
                        "next to Husk (com.betterhusk.app), it does not replace it."),
        "iconURL": icon,
        "website": f"https://github.com/{REPO}",
        "tintColor": "#5865F2",
        "featuredApps": ["com.betterhusk.app"],
        "apps": [{
            "name": "BetterHusk",
            "bundleIdentifier": "com.betterhusk.app",
            "developerName": "BetterHusk (fork of Leviidev's Husk)",
            "subtitle": "Android apps and PS4 games on your iPhone.",
            "localizedDescription": ("BetterHusk is a fork of Husk that tracks upstream and additionally ships fixes "
                                     "upstream has not merged yet: a Java sensor-manager API for Unity games, Godot "
                                     "4.6/4.7 file and directory handlers, V8 --jitless for Cocos Creator games, "
                                     "manifest-based base-APK selection for split bundles, dynamic RemotePairing port "
                                     "discovery for built-in JIT, and a W^X-safe executable-memory path for "
                                     "TrollStore devices."),
            "iconURL": icon,
            "tintColor": "#5865F2",
            "category": "games",
            "screenshots": [f"{RAW}/Screenshots/{s}" for s in shots],
            "versions": versions,
            "appPermissions": {
                "entitlements": [
                    "get-task-allow",
                    "dynamic-codesigning",
                    "com.apple.developer.kernel.increased-memory-limit",
                    "com.apple.developer.kernel.extended-virtual-addressing",
                ],
                "privacy": {
                    "NSLocalNetworkUsageDescription": "BetterHusk uses the local network to pair with this iPhone for JIT, without a computer.",
                },
            },
        }],
        "news": [],
    }
    with open(OUT, "w") as f:
        json.dump(source, f, indent=2)
        f.write("\n")
    print(f"wrote {os.path.relpath(OUT, ROOT)}: {len(versions)} versions, newest {versions[0]['version'] if versions else 'none'}")


if __name__ == "__main__":
    main()
