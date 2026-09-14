#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"

for tool in file find grep mktemp sha256sum stat unzip; do
    need "$tool"
done

install_zip=${1:-"$OUT/$ADDON_NAME-$ECHOLOCAL_TAG-$ECHOD_ARCH.zip"}
[ -f "$install_zip" ] || fail "missing ZIP: $install_zip"

verify_sidecar() {
    zip_path=$1
    sidecar="$zip_path.sha256"
    [ -f "$sidecar" ] || fail "missing checksum: $sidecar"
    (
        cd "$(dirname "$zip_path")"
        sha256sum -c "$(basename "$sidecar")" >/dev/null
    ) || fail "ZIP checksum mismatch: $zip_path"
}

mode_is() {
    [ "$(stat -c '%a' "$1")" = "$2" ] || fail "wrong mode on $1"
}

forbidden_operations() {
    script=$1
    if grep -Eq '/(boot|recovery|cache|persist)(/|[[:space:]]|$)' "$script"; then
        fail "forbidden partition reference in $script"
    fi
    if grep -Eq '(^|[[:space:]])(dd|flash_image|write_raw_image|format|delete_recursive)([[:space:]]|$)' "$script"; then
        fail "forbidden flash operation in $script"
    fi
}

verify_sidecar "$install_zip"
unzip -t "$install_zip" >/dev/null

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
unzip -q "$install_zip" -d "$tmp/install"

[ -z "$(find "$tmp/install" -type l -print)" ] || fail 'installer ZIP contains a symlink'
[ ! -e "$tmp/install/payload/system/etc/ssl/certs/ca-certificates.crt" ] ||
    fail 'installer must not package the base CA bundle'
(
    cd "$tmp/install"
    sha256sum -c payload-manifest.sha256 >/dev/null
) || fail 'payload manifest does not verify'

for relative in \
    system/bin/echolocal \
    system/bin/start_animation.sh \
    system/bin/stop_animation.sh \
    system/app/echod/echod \
    system/etc/echolocal/.biscuit-addon \
    system/etc/echolocal/models/okay_nabu.json \
    system/etc/echolocal/models/okay_nabu.tflite \
    system/etc/echolocal/models/hey_jarvis.json \
    system/etc/echolocal/models/hey_jarvis.tflite \
    system/etc/echolocal/models/hey_mycroft.json \
    system/etc/echolocal/models/hey_mycroft.tflite; do
    [ -f "$tmp/install/payload/$relative" ] && [ ! -L "$tmp/install/payload/$relative" ] ||
        fail "missing regular payload file: $relative"
done
for relative in system/bin/echolocal system/bin/start_animation.sh system/bin/stop_animation.sh \
    system/app/echod/echod; do
    mode_is "$tmp/install/payload/$relative" 755
done
for relative in system/etc/echolocal/.biscuit-addon \
    system/etc/echolocal/models/okay_nabu.json system/etc/echolocal/models/okay_nabu.tflite \
    system/etc/echolocal/models/hey_jarvis.json system/etc/echolocal/models/hey_jarvis.tflite \
    system/etc/echolocal/models/hey_mycroft.json system/etc/echolocal/models/hey_mycroft.tflite; do
    mode_is "$tmp/install/payload/$relative" 644
done
require_static "packaged echod" "$tmp/install/payload/system/app/echod/echod" "$GOARCH"
sh -n "$tmp/install/payload/system/bin/echolocal"
sh -n "$tmp/install/payload/system/bin/start_animation.sh"
sh -n "$tmp/install/payload/system/bin/stop_animation.sh"
grep -Fq 'echod.prev' "$tmp/install/payload/system/bin/start_animation.sh" ||
    fail 'start animation hook lacks rollback'
grep -Fq 'exit 0' "$tmp/install/payload/system/bin/stop_animation.sh" ||
    fail 'stop animation hook is not a stub'
grep -Fq 'repair)' "$tmp/install/payload/system/bin/echolocal" ||
    fail 'helper lacks repair command'
! grep -Eq 'wpa_cli|wpa_passphrase|wifi_' "$tmp/install/payload/system/bin/echolocal" ||
    fail 'helper must not manage Wi-Fi'
grep -qx "name=$ADDON_NAME" "$tmp/install/payload/system/etc/echolocal/.biscuit-addon" ||
    fail 'wrong add-on marker'
grep -qx "version=$ECHOLOCAL_TAG" "$tmp/install/payload/system/etc/echolocal/.biscuit-addon" ||
    fail 'wrong add-on version'
grep -qx "base_ledcontroller_sha256=$BASE_LEDCONTROLLER_SHA256" \
    "$tmp/install/payload/system/etc/echolocal/.biscuit-addon" || fail 'wrong base marker'

install_binary="$tmp/install/META-INF/com/google/android/update-binary"
mode_is "$install_binary" 755
sh -n "$install_binary"
forbidden_operations "$install_binary"
grep -Fq -- '--reference="$BACKUP"' "$install_binary" ||
    fail 'installer does not attempt labels from the preserved fallback'
grep -Fq 'BACKUP="$SERVICE.orig"' "$install_binary" || fail 'installer does not preserve fallback'
grep -Fq 'ln -s "$ECHOD"' "$install_binary" || fail 'installer does not create service symlink'
grep -Fq 'initialize_runtime_state' "$install_binary" ||
    fail 'installer does not initialize first-install runtime state'
grep -Fq 'STATE=${ECHOLOCAL_STATE:-/data/misc/echolocal}' "$install_binary" ||
    fail 'installer does not restrict runtime state to the add-on path'
grep -Fq 'START_BACKUP="$START_ANIMATION.orig"' "$install_binary" ||
    fail 'installer does not preserve animation hooks'

printf '%s\n' "verified $install_zip"
