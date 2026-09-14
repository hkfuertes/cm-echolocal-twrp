# cm-echolocal-twrp

A reproducible, TWRP-flashable EchoLocal add-on for the framework-free Biscuit
`cm12-minimal` base. Its payload lives in `/system`; it owns runtime state under `/data/misc/echolocal`.

## What it does

- verifies the Biscuit device and the exact reserved generic
  `/system/bin/ledcontroller` fallback before installing;
- preserves that fallback once as `ledcontroller.orig`;
- replaces it with a symlink to `/system/app/echod/echod`; when both base
  animation hooks exist, preserves them as `.orig`; the current minimal base
  has neither, so it does not create dead hooks;
- compiles ARM64 and ARMv7 `echod` from the pinned upstream EchoLocal tag with
  verified wake-word models while using the BusyBox and TLS trust store already
  supplied by the base;
- initializes a missing ESPHome key and missing wake-word models on first install,
  without overwriting existing runtime state; and
- provides `echolocal repair` to recreate missing state after a `/data` wipe.

It deliberately does **not** modify boot, ramdisk, recovery, cache, persist,
or partition tables. A full system OTA removes this add-on; reflash the install
ZIP afterwards.

## Base requirements

- `/system/xbin/busybox` must be a regular executable supplied by `cm12-minimal`.
- CM12 owns the TLS trust roots. This ZIP never packages, overwrites, or
  removes certificates.

## Network provisioning

The ROM owns Wi-Fi provisioning through `wpa_connect`; EchoLocal never writes
or stores Wi-Fi credentials.

## ESPHome key

Root ADB is required:

```sh
adb root
adb shell echolocal key show
adb shell echolocal key rotate
```

`key show` prints the current ESPHome key. Treat it as a secret. `key rotate`
generates a new key, restarts `ledcontroller`, and prints the replacement; update
Home Assistant with it before pairing again.

## Build

Requires Docker, git, make, and a GNU/Linux host with the standard tools used
by the scripts (`file`, `sha256sum`, `stat`, `touch`, `zip`, and `unzip`). Both
ARM64 and ARMv7 `echod` binaries are compiled from the pinned EchoLocal tag
inside a toolchain image pulled by digest.

```sh
make package          # arm64 and armv7 ZIPs
make package-arm64    # one target only
make package-armv7
make verify
make test
```

Toolchain caches, source checkouts, staging trees, and ZIPs stay under
ignored `work/` and `out/`. Pins (tag, commit, image digest, per-target binary
and model hashes) live in [`scripts/versions.sh`](scripts/versions.sh). The
installer marker and ZIP names use the pinned upstream tag. Credentials never
enter the repository or ZIP. ARMv7 carries no local source overlays or prebuilt
binaries: upstream `0.0.7` supplies its ARM ABI fixes and architecture-aware
updater.

Flash exactly one architecture-specific ZIP in TWRP:
`out/cm12-echolocal-biscuit-0.0.7-arm64.zip` or
`out/cm12-echolocal-biscuit-0.0.7-armv7.zip`.
Both install only on Biscuit where the reserved generic
`/system/bin/ledcontroller` fallback matches the approved hash. It will reject
a CM14/Fire OS base unless it presents that exact supported fallback. After a
`/data` wipe, run `adb root`, then `adb shell echolocal repair`; obtain the new
key with `adb shell echolocal key show` and reprovision Wi-Fi through the ROM.
Test on hardware before relying on it.

## Credits

This add-on packages and integrates [EchoLocal](https://github.com/ygelfand/echolocal)
by [ygelfand](https://github.com/ygelfand). This repository supplies only the Biscuit
CM12 TWRP integration.
