# BetterHusk

[![BetterHusk Downloads](https://img.shields.io/github/downloads/aethercognitivelabs/betterhusk/total?style=for-the-badge&color=5865F2&labelColor=111111)](https://github.com/AetherCognitiveLabs/BetterHusk/releases)
[![Build BetterHusk IPA](https://img.shields.io/github/actions/workflow/status/aethercognitivelabs/betterhusk/build-ipa.yml?style=for-the-badge&label=build)](https://github.com/AetherCognitiveLabs/BetterHusk/actions/workflows/build-ipa.yml)

**BetterHusk is a fork of [Leviidev/Husk](https://github.com/Leviidev/Husk) that
tracks upstream and ships the fixes upstream has not merged yet.** It installs
next to Husk (`com.betterhusk.app`), so you can run both.

Android apps and games on your iPhone.

Add an APK, tap it, and it opens full-screen. BetterHusk runs it in one of two ways,
shown as the two sides of its Library:

- **Translation Layer.** The game's own 64-bit Android code runs directly on
  the iPhone's processor, and Husk stands in for Android around it: the C
  library, the Java calls the game makes, OpenGL ES (through ANGLE), Vulkan
  (through MoltenVK), sound, touch and controllers. No Android boots, so a
  game starts in seconds, and its code is never emulated.
  See [docs/04-translation-layer.md](docs/04-translation-layer.md).
- **Emulation.** A full Android system (LineageOS) boots under QEMU inside
  BetterHusk, for apps the translation layer cannot run yet and for using Android
  itself. iOS gives apps no hypervisor, so the processor is emulated, and
  this is much slower than the translation layer.
  See [docs/00-architecture.md](docs/00-architecture.md).

## What BetterHusk adds over Husk

Everything in upstream `Leviidev/Husk`, plus these unmerged upstream fixes
and fork-level work:

- **Translation-layer sensor manager** — Unity games that enumerate sensors at
  startup (e.g. Stickman Dismounting hanging on the ViperGames splash screen)
  get real accelerometer/gyro answers from CoreMotion
  ([Leviidev/Husk#147](https://github.com/Leviidev/Husk/pull/147)).
- **Unity display modes + device memory** — `Display.getSupportedModes`
  answers a 60 Hz mode instead of `null`, so `Enumerable.Max` no longer
  throws during Unity startup (same PR).
- **Godot 4.6/4.7 file & directory handlers** — the Kotlin-moved
  `DirectoryAccessHandler`/`FileAccessHandler` natives are answered, fixing
  the `NoSuchMethodError` crash on startup
  ([Leviidev/Husk#151](https://github.com/Leviidev/Husk/pull/151), fixes
  [#140](https://github.com/Leviidev/Husk/issues/140)).
- **Cocos Creator games boot** — V8 is told `--jitless` before its
  `JNI_OnLoad`, so `libcocos2djs` games (Top War and friends) no longer die
  asking for writable+executable memory
  ([Leviidev/Husk#113](https://github.com/Leviidev/Husk/pull/113)).
- **Correct base-APK selection for split bundles** — the manifest's `split`
  attribute decides, not the file name, so `.xapk`/`.apkm` installs pick the
  real base APK ([Leviidev/Husk#106](https://github.com/Leviidev/Husk/pull/106)).
- **Built-in JIT port discovery** — the RemotePairing port is discovered via
  Bonjour instead of assumed to be 49152, fixing built-in StikJIT on devices
  where the port differs
  ([Leviidev/Husk#153](https://github.com/Leviidev/Husk/pull/153)).
- **W^X-safe JIT mapping + TrollStore packaging** — the dual mapping allocates
  RWX-max then demotes to RX via `vm_protect`, and `package_ipa.sh` strips the
  `dynamic-codesigning` entitlement that TrollStore bans under PPL/TXM
  ([Leviidev/Husk#74](https://github.com/Leviidev/Husk/pull/74)).
- **Per-game engine override** — a "Runs as" picker in each game's settings
  forces the runtime driver (SDL, Unreal/Vulkan, Godot…), for games whose
  setup screen runs on a different engine than the game itself
  ([Leviidev/Husk#149](https://github.com/Leviidev/Husk/issues/149)).
- **Dex2C timing fix** — a failed JNI native lookup is no longer cached, so
  methods bound late by `RegisterNatives` (Balatro's protector library)
  resolve instead of crashing with `UnsatisfiedLinkError`
  ([Leviidev/Husk#152](https://github.com/Leviidev/Husk/issues/152)).
- **Emulation first-boot self-repair** — when Android's `init_user0_failed`
  strands first boot in a recovery that cannot format the half-built data
  partition, the next launch of BetterHusk resets it to a clean disk
  automatically. A qcow2 header preflight catches the same class of dead-end
  before QEMU ever sees it, a shipped snapshot or a disk that ever booted is
  never touched, and two failed repairs surface an actual error instead of an
  endless recovery loop
  ([Leviidev/Husk#128](https://github.com/Leviidev/Husk/issues/128)).
- **Simplified Chinese UI** — a `Localizable.xcstrings` catalog translates the
  whole interface (onboarding, settings, library, JIT setup, emulation
  screens) into zh-Hans; devices set to Chinese get it automatically
  ([Leviidev/Husk#143](https://github.com/Leviidev/Husk/issues/143),
  [#150](https://github.com/Leviidev/Husk/issues/150)). Upstream has no
  localization at all.
- **A real CI** — `.github/workflows/build-ipa.yml` builds a complete,
  verified IPA (with the checksummed PS4 module) on every push to `main` and
  publishes it as a prerelease. Upstream has no CI at all.
- **Its own identity** — `com.betterhusk.app`, so BetterHusk installs
  alongside Husk instead of fighting it for the same bundle ID.

See [FORK.md](FORK.md) for how the fork is kept in sync and how upstream PRs
are picked.

## Screenshots

### Games on the Translation Layer

<table>
  <tr>
    <td align="center"><img src="Screenshots/gta-san-andreas.jpeg" alt="GTA: San Andreas" width="100%"><br><sub><b>GTA: San Andreas</b></sub></td>
    <td align="center"><img src="Screenshots/minecraft-dungeons.jpeg" alt="Minecraft Dungeons" width="100%"><br><sub><b>Minecraft Dungeons</b></sub></td>
  </tr>
  <tr>
    <td align="center"><img src="Screenshots/beach-buggy-racing-2.jpeg" alt="Beach Buggy Racing 2" width="100%"><br><sub><b>Beach Buggy Racing 2</b></sub></td>
    <td align="center"><img src="Screenshots/geometry-dash.jpeg" alt="Geometry Dash" width="100%"><br><sub><b>Geometry Dash</b></sub></td>
  </tr>
</table>

### The app

<table>
  <tr>
    <td align="center" width="33%"><img src="Screenshots/library.png" alt="Library" width="100%"><br><sub><b>Library</b></sub></td>
    <td align="center" width="33%"><img src="Screenshots/game-settings.png" alt="Game Settings" width="100%"><br><sub><b>Game Settings</b></sub></td>
    <td align="center" width="33%"><img src="Screenshots/settings.png" alt="Settings" width="100%"><br><sub><b>Settings</b></sub></td>
  </tr>
</table>

## What the Translation Layer runs

Games made with an engine Husk has a driver for:

- Unity
- Unreal Engine 4 (through Vulkan)
- cocos2d-x
- Godot 3 and 4 (GLES2, GLES3 and the Compatibility renderer)
- SDL2 and SDL3, including LÖVE games
- GameActivity (Minecraft) and NativeActivity
- Rockstar's own engine (GTA: San Andreas)

Games see Google Play services as installed and signed out, so the ones that
check for it start normally; Play Games sign-in, cloud saves and purchases are
not available. Geometry Dash can load [Geode](https://geode-sdk.org) mods.

An APK needs 64-bit (`arm64-v8a`) native code. iPhones cannot run 32-bit ARM
code, so an APK that only has 32-bit libraries cannot run here. APKs and
split bundles (`.xapk`, `.apkm`, `.apks`, or a Play download's separate split
APKs and asset packs) can all be added. Apps written only
in Java, with no native engine, are not supported on the translation layer;
Emulation is the way to run those.

One game runs per launch of Husk. To switch, press **Close Husk to Play** on
the other game's page; when you open Husk again, that game starts by itself.

A game's saves can be backed up to a `.zip` from its page and restored later,
on the same iPhone or another. If a game crashes Husk, the next launch shows
what happened, with a report you can share.

## Installing

**SideStore, AltStore and other sideloaders:** add BetterHusk's source, and the
sideloader installs BetterHusk and offers each update as it comes out.

```
https://raw.githubusercontent.com/AetherCognitiveLabs/BetterHusk/main/altsource.json
```

In SideStore or AltStore: Sources › + › paste the address above.

**Or by hand:** download `BetterHusk.ipa` from
[Releases](https://github.com/AetherCognitiveLabs/BetterHusk/releases) and install it with
SideStore, AltStore or TrollStore. It is one IPA for all of them: it carries
BetterHusk's entitlements, which TrollStore keeps, and a sideloader re-signs it with
your own.

BetterHusk needs iOS 15.5 or later.

## JIT

Both the translation layer and Emulation need JIT, which on iOS comes from a
debugger. BetterHusk can get it in several ways, and walks you through each one
(Settings › JIT & Sideload):

- **Built-in StikJIT** (iOS 26 and later): BetterHusk turns JIT on itself, with no
  second app. On iOS 27 it pairs with your iPhone from Settings, with no
  computer. See [docs/06-built-in-jit.md](docs/06-built-in-jit.md).
- **StikDebug**, installed alongside BetterHusk.
- **TrollStore or a Dopamine jailbreak** ("Allow JIT in Apps"), on iOS
  versions before 26 only. From iOS 26 only a debugger can grant JIT.

## Building

BetterHusk is built on a Mac with Xcode, or in the cloud with the included
GitHub Actions workflow (`Actions › Build BetterHusk IPA › Run workflow` — no
Mac needed). The build scripts also call `meson`,
`ninja`, `pkg-config`, `python3`, `xcodegen`, `qemu-img` and a Rust
toolchain with the `aarch64-apple-ios` target.

```sh
./scripts/ci_build.sh build/BetterHusk.ipa
```

From a clean checkout this fetches and cross-compiles everything BetterHusk links:

- QEMU and its dependencies
- ANGLE and virglrenderer
- MoltenVK
- the on-device pairing library

It then builds the app and writes the IPA to `build/BetterHusk.ipa`. The first run
takes a couple of hours, and later runs reuse what is already built. After
that, `./scripts/package_ipa.sh` rebuilds just the app and writes
`~/Desktop/BetterHusk.ipa` (`--trollstore` produces a `.tipa` with the banned
entitlements stripped).

`tools/regress/run.sh` plays a set of games on the Mac through the
translation layer and checks each against a reference screenshot (see the
top of `tools/regress/cases.txt` for what it needs).

## Licence

GPL-2.0-or-later, same as upstream. BetterHusk links QEMU, which is GPLv2, so
the shipped binary is a combined GPLv2 work and the full source is public.
BetterHusk cannot go on the App Store, both
because of that and because it needs `get-task-allow` plus a debugger
attaching at runtime. See [docs/01-licensing.md](docs/01-licensing.md).

All credit for the engine and the app goes to
[Leviidev](https://github.com/Leviidev) and Husk's contributors; BetterHusk
only curates and adds on top.
