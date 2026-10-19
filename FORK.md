# BetterHusk — fork notes

BetterHusk is a tracking fork of [Leviidev/Husk](https://github.com/Leviidev/Husk)
(GPL-2.0-or-later). The goal: everything upstream ships, plus fixes that are
proven but not merged yet, plus build/release infrastructure upstream lacks.

## What differs from upstream

| Change | Origin | State upstream |
|---|---|---|
| Translation-layer sensor manager (Java API → CoreMotion) | [PR #147](https://github.com/Leviidev/Husk/pull/147) | open |
| Unity `Display.Mode` / refresh-rate answers, device memory | [PR #147](https://github.com/Leviidev/Husk/pull/147) | open |
| IPA build workflow `.github/workflows/build-ipa.yml` | [PR #147](https://github.com/Leviidev/Husk/pull/147), adapted | none exists |
| Godot 4.6/4.7 Kotlin `DirectoryAccessHandler`/`FileAccessHandler` natives | [PR #151](https://github.com/Leviidev/Husk/pull/151) | open |
| V8 `--jitless` for Cocos Creator (`libcocos2djs`) | [PR #113](https://github.com/Leviidev/Husk/pull/113) | open |
| Manifest-based base-APK selection for split bundles | [PR #106](https://github.com/Leviidev/Husk/pull/106) | open |
| RemotePairing port discovery for built-in StikJIT | [PR #153](https://github.com/Leviidev/Husk/pull/153) | open |
| W^X-safe xmem dual mapping + TrollStore banned-entitlement stripping | [PR #74](https://github.com/Leviidev/Husk/pull/74) | open |
| Per-game engine/driver override ("Runs as" picker) | [issue #149](https://github.com/Leviidev/Husk/issues/149) | unaddressed upstream |
| JNI: no caching of failed native lookups (Dex2C/RegisterNatives timing) | [issue #152](https://github.com/Leviidev/Husk/issues/152) | unaddressed upstream |
| Emulation userdata self-repair: `init_user0_failed` marks the disk, next launch re-seeds a never-booted /data (qcow2 header preflight, 2-attempt budget, booted/snapshot data never touched) | [issue #128](https://github.com/Leviidev/Husk/issues/128) | unaddressed upstream |
| Simplified Chinese UI (`Localizable.xcstrings`, ~290 strings) | [issue #143](https://github.com/Leviidev/Husk/issues/143), [issue #150](https://github.com/Leviidev/Husk/issues/150) | no localization exists |
| Bundle ID `com.betterhusk.app`, display name "BetterHusk" | this fork | n/a |
| `altsource.json` served from this repo | this fork | n/a |

## Sync policy

1. `git remote add upstream https://github.com/Leviidev/Husk.git`
2. `git fetch upstream && git merge upstream/main` (or cherry-pick releases).
3. Upstream PRs worth shipping early are fetched with
   `git fetch upstream pull/<N>/head:pr-<N>` and either cherry-picked (single
   clean commits, keeps authorship) or squash-merged (branches with broken
   intermediate states — see below).

## Why some PRs were squashed

- **#147** contains a commit that truncates `husk-tl-jni-hle.c` and
  `husk-tl-bionic-io.c` by ~2600 lines, repaired by a later commit on the same
  branch. Cherry-picking individual commits would import the broken state, so
  the branch's net diff was squash-merged with `Co-authored-by` credit.
- **#74** predates a large refactor of the JIT docs/comments; the 3-way squash
  merge resolved cleanly where a raw patch did not.

## Watch list (upstream issues the fork could tackle next)

- [#146](https://github.com/Leviidev/Husk/issues/146) — HVF acceleration for
  Emulation on M1/M2 iPads (iOS 15.5–16.3)
- [#148](https://github.com/Leviidev/Husk/issues/148) — built-in JIT errors on
  iOS 16.7 Dopamine/TrollStore

## Keeping the identity straight

- `HUSK_BUNDLE_IDENTIFIER` in `src/app/project.yml` is the single source of
  truth for the bundle ID (`com.betterhusk.app`); helper and widget IDs derive
  from it. Do not rename it back, or installs collide with upstream.
- Internal target/module names (`Husk`, `libhusk*`, `Payload/Husk.app`) stay
  as upstream names them — renaming them buys nothing and costs merge pain.
- The PS4 runtime module is a verified binary pulled from the official Husk
  3.0 release inside CI (SHA-256 checked); there is no public source for it.

## Localization

`src/app/Husk/Localizable.xcstrings` holds the zh-Hans catalog. It covers
every pure-literal `Text`/`Button`/`Section` key in the SwiftUI sources.
Two classes of string still render in English and are the next pass:

- keys containing `\(interpolation)` -- the catalog format for substituted
  strings is best authored inside Xcode, and the fallback is safe;
- runtime-composed strings (`state = .failed("…")`, `host.say(…)`) which need
  `String(localized:)` call sites before a catalog key can reach them.
