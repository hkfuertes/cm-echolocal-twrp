# AGENTS.md

## Purpose

Build and maintain a reproducible, TWRP-flashable EchoLocal add-on for the
framework-free Biscuit `cm12-minimal` base. Keep this project independent from
`../amazon_device_biscuit` and from the Fire OS-oriented EchoLocal installer.

## Base contract

- Support only Biscuit and the generic base whose reserved
  `/system/bin/ledcontroller` fallback matches the approved hash in
  `scripts/versions.sh`.
- Generic init already starts and supervises `ledcontroller` as root after
  `post-fs-data`. Do not change boot.img, ramdisk, recovery, GPT, cache, or
  persist to integrate EchoLocal.
- Use only the required base commands (`base64`, `cat`, `chown`, `chmod`,
  `cp`, `dd`, `id`, `mkdir`, `mv`, `rm`, `setprop`, and `wc`) through the
  fixed `/system/bin:/system/xbin` path; require each to be executable and
  never overwrite or remove base tools. They may be Toybox/Toolbox symlinks.
  The base also owns TLS trust roots; never package, overwrite, or remove them.
- Fail closed on a wrong device, wrong fallback, missing marker, bad payload,
  bad mode/context, unsafe symlink, or insufficient free space.

## Runtime design

- `/system/bin/ledcontroller` is a symlink to `/system/app/echod/echod` so
  init supervises the upstream daemon through its expected service name.
- If the base has both animation hooks, preserve them as `.orig` and install
  EchoLocal's rollback/stub hooks; restore them on uninstall. The current
  minimal base has neither, so do not create dead hooks during installation.
- The installer initializes a missing ESPHome key and missing seed models on
  first install without overwriting runtime state. A `/data` wipe is repaired
  manually with `echolocal repair`: it ensures the key, copies absent models,
  and restarts `ledcontroller`. The ROM owns Wi-Fi provisioning and credentials
  through `wpa_connect`; EchoLocal never writes them.
- Keep EchoLocal's compatibility paths and the `ledcontroller` init-service
  lifecycle. Do not copy Fire OS boot flashing, package hiding, firewall hooks,
  or Wi-Fi provisioning behavior.

## Installer and uninstaller

- The installer owns `/system` payload files and initializes only missing
  add-on-owned `/data/misc/echolocal` state. Never write Wi-Fi credentials or
  embed an ESPHome key in a ZIP, source file, log, or fixture.
- Preserve the original fallback once as `/system/bin/ledcontroller.orig` and
  require an add-on marker for upgrades or uninstall.
- Attempt to label installed payload from the preserved fallback; preserve that
  fallback's content and label for restoration.
- The uninstaller restores the original fallback, removes only known
  add-on-owned `/system` files, and preserves `/data/misc/echolocal` by
  default.
- A full system OTA removes the add-on. Do not claim OTA survival.

## Pinned inputs and repository hygiene

- `scripts/versions.sh` is the source of truth for revisions and SHA-256s.
  Build both ARM64 and ARMv7 `echod` targets from the pinned EchoLocal tag
  (which must peel to the pinned commit) inside the Docker toolchain image
  pinned by digest. Verify each target binary against its pinned SHA-256 and
  as a static ELF executable for its target architecture. Do not carry local
  ARMv7 source patches or upstream prebuilt binaries. Model assets and any
  future add-on-owned runtime tool follow the same rule.
- Do not commit downloads, generated models, staging trees, or ZIPs. They
  belong under ignored `work/` and `out/`.
- Keep the implementation small: POSIX shell, existing host tools, and no new
  dependency unless it is required and pinned.

## Required checks

Run before committing changes:

```sh
make test
```

This validates hashes, archive contents, modes, contexts, symlinks, install,
upgrade, uninstall, `repair`, managed/absent hook handling, and a simulated
`/data` wipe.

Before hardware use, perform an explicit TWRP smoke test on the supported base:
install without wiping data; verify root ADB, `ledcontroller`, `echod`, key and
model recovery, Wi-Fi/mDNS; test uninstall, reinstall, then a controlled data
wipe. Use `adb devices -l` plus short explicit checks, not `adb wait-for-device`.

## References

- Generic base reference: <https://github.com/hkfuertes/amazon_device_biscuit>
- Existing EchoLocal source/installer: <https://github.com/ygelfand/echolocal> (reference only)
- Base PR: <https://github.com/hkfuertes/amazon_device_biscuit/pull/6>
- Integration reference: <https://github.com/hkfuertes/amazon_device_biscuit/pull/4>
