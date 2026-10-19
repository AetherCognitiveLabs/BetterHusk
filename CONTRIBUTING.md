# Contributing to BetterHusk

BetterHusk is a tracking fork of [Leviidev/Husk](https://github.com/Leviidev/Husk).
Two kinds of changes live here:

- **Upstream sync** — everything `Leviidev/Husk:main` ships. Keep fork edits
  small and localized so merges stay easy.
- **BetterHusk patches** — fixes upstream has not merged, plus fork-only
  infrastructure (the IPA workflow, the `com.betterhusk.app` identity,
  this repo's `altsource.json`).

If your change fixes a Husk bug, consider opening it upstream too — every fix
that lands there is one less patch this fork has to carry. See
[FORK.md](FORK.md) for the current patch list and sync procedure.

## Building

A Mac with Xcode; the scripts also need `meson`, `ninja`, `pkg-config`,
`python3`, `xcodegen`, `qemu-img` and a Rust toolchain with the
`aarch64-apple-ios` target.

```sh
./scripts/ci_build.sh build/BetterHusk.ipa   # full build, hours the first time
./scripts/package_ipa.sh                    # repackage just the app afterwards
```

No Mac? `Actions → Build BetterHusk IPA → Run workflow` builds the same IPA on
GitHub's runners.

## Working on the app

- `src/app/project.yml` is the source of truth for the Xcode project —
  `xcodegen generate` rewrites `Husk.xcodeproj`. Edit the yml, not the
  pbxproj (the checked-in pbxproj is kept in sync for builders without
  xcodegen).
- The bundle ID is `HUSK_BUNDLE_IDENTIFIER` in `project.yml`. Do not change it
  back to `com.husk.app`: the fork deliberately installs alongside upstream.

## Testing

- `tests/translation-layer/run.sh` runs the translation-layer checks under
  arm64 Linux + qemu-user.
- `python3 tests/translation-layer/test_apk_order.py` exercises the APK
  ordering logic with `swiftc` — Foundation only, no iOS SDK needed.
- `tools/regress/run.sh` replays games on a Mac against reference
  screenshots (see `tools/regress/cases.txt`).

## Style

Match the file you are in. C sources carry SPDX headers
(`SPDX-License-Identifier: GPL-2.0-or-later`); SwiftUI views follow the
existing struct-per-screen layout.
