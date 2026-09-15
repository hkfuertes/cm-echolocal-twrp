#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$ROOT/scripts/versions.sh"
INSTALL_ZIP=${1:-"$ROOT/out/$ADDON_NAME-$ECHOLOCAL_TAG-$ECHOD_ARCH.zip"}
FIXTURE="$ROOT/tests/fixtures/ledcontroller"
HOST_UNZIP=$(command -v unzip)
[ -n "$HOST_UNZIP" ] || { printf '%s\n' 'missing host unzip' >&2; exit 1; }
[ "$(sha256sum "$FIXTURE" | awk '{print $1}')" = "$BASE_LEDCONTROLLER_SHA256" ] || {
    printf '%s\n' 'generic fallback fixture hash changed' >&2
    exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/bin" "$tmp/recovery"
cat > "$tmp/bin/getprop" <<'EOF'
#!/bin/sh
printf '%s\n' "${TEST_PRODUCT:-biscuit}"
EOF
cat > "$tmp/bin/chcon" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$tmp/bin/df" <<'EOF'
#!/bin/sh
cat <<'DF'
Filesystem           1K-blocks      Used Available Use% Mounted on
/dev/block/mmcblk0p13
                        761776     44332    701716   6% /system
DF
EOF
cat > "$tmp/bin/chcon-fails" <<'EOF'
#!/bin/sh
exit 1
EOF
cat > "$tmp/bin/chown" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0755 "$tmp/bin/getprop" "$tmp/bin/chcon" "$tmp/bin/df" "$tmp/bin/chcon-fails" "$tmp/bin/chown"
cat > "$tmp/bin/unzip-no-glob" <<EOF
#!/bin/sh
for argument in "\$@"; do
    [ "\$argument" != 'payload/*' ] || exit 1
done
unset UNZIP
exec "$HOST_UNZIP" "\$@"
EOF
chmod 0755 "$tmp/bin/unzip-no-glob"
unzip -q "$INSTALL_ZIP" -d "$tmp/install"
install_binary="$tmp/install/META-INF/com/google/android/update-binary"

setup_system() {
    rm -rf "$1" "$1-data"
    mkdir -p "$1/bin" "$1/etc/ssl/certs" "$1-data/misc"
    cp "$FIXTURE" "$1/bin/ledcontroller"
    for tool in base64 cat chown chmod cp dd id mkdir mv rm setprop wc; do
        printf '%s\n' '#!/bin/sh' 'exit 0' > "$1/bin/$tool"
        chmod 0755 "$1/bin/$tool"
    done
    printf '%s\n' 'base CA bundle' > "$1/etc/ssl/certs/ca-certificates.crt"
    chmod 0755 "$1/bin/ledcontroller"
    chmod 0644 "$1/etc/ssl/certs/ca-certificates.crt"
    case "${2:-managed}" in
        managed)
            printf '%s\n' 'stock start animation' > "$1/bin/start_animation.sh"
            printf '%s\n' 'stock stop animation' > "$1/bin/stop_animation.sh"
            chmod 0755 "$1/bin/start_animation.sh" "$1/bin/stop_animation.sh"
            ;;
        absent) ;;
        *) printf '%s\n' "unknown hook mode: $2" >&2; exit 1 ;;
    esac
}

run_update() {
    TEST_PRODUCT="$4" \
        ECHOLOCAL_SYSTEM="$3" ECHOLOCAL_STATE="$3-data/misc/echolocal" ECHOLOCAL_TMPDIR="$tmp/recovery" \
        ECHOLOCAL_FREE_KB="$5" GETPROP="$tmp/bin/getprop" CHCON="$tmp/bin/chcon" CHOWN="$tmp/bin/chown" \
        sh "$1" 3 1 "$2" >/dev/null
}

run_update_folded_df() {
    TEST_PRODUCT=biscuit ECHOLOCAL_SYSTEM="$2" ECHOLOCAL_STATE="$2-data/misc/echolocal" ECHOLOCAL_TMPDIR="$tmp/recovery" \
        GETPROP="$tmp/bin/getprop" CHCON="$tmp/bin/chcon" CHOWN="$tmp/bin/chown" DF="$tmp/bin/df" \
        sh "$1" 3 1 "$INSTALL_ZIP" >/dev/null
}

run_update_no_glob_unzip() {
    TEST_PRODUCT=biscuit ECHOLOCAL_SYSTEM="$2" ECHOLOCAL_STATE="$2-data/misc/echolocal" ECHOLOCAL_TMPDIR="$tmp/recovery" \
        ECHOLOCAL_FREE_KB=999999 GETPROP="$tmp/bin/getprop" CHCON="$tmp/bin/chcon" CHOWN="$tmp/bin/chown" \
        UNZIP="$tmp/bin/unzip-no-glob" \
        sh "$1" 3 1 "$INSTALL_ZIP" >/dev/null
}

run_update_label_failure() {
    TEST_PRODUCT=biscuit ECHOLOCAL_SYSTEM="$2" ECHOLOCAL_STATE="$2-data/misc/echolocal" ECHOLOCAL_TMPDIR="$tmp/recovery" \
        ECHOLOCAL_FREE_KB=999999 GETPROP="$tmp/bin/getprop" CHCON="$tmp/bin/chcon-fails" CHOWN="$tmp/bin/chown" \
        sh "$1" 3 1 "$INSTALL_ZIP" >/dev/null
}

system="$tmp/system"
setup_system "$system"
base_ca_hash=$(sha256sum "$system/etc/ssl/certs/ca-certificates.crt" | awk '{print $1}')
run_update "$install_binary" "$INSTALL_ZIP" "$system" biscuit 999999
[ -f "$system/bin/ledcontroller.orig" ]
[ -L "$system/bin/ledcontroller" ]
[ "$(readlink "$system/bin/ledcontroller")" = "$system/app/echod/echod" ]
[ "$(sha256sum "$system/bin/ledcontroller.orig" | awk '{print $1}')" = "$BASE_LEDCONTROLLER_SHA256" ]
[ -f "$system/etc/echolocal/.biscuit-addon" ]
grep -qx "version=$ECHOLOCAL_TAG" "$system/etc/echolocal/.biscuit-addon"
[ "$(sha256sum "$system/etc/ssl/certs/ca-certificates.crt" | awk '{print $1}')" = "$base_ca_hash" ]
grep -qx 'animation_hooks=managed' "$system/etc/echolocal/.biscuit-addon"
[ "$(cat "$system/bin/start_animation.sh.orig")" = 'stock start animation' ]
[ "$(cat "$system/bin/stop_animation.sh.orig")" = 'stock stop animation' ]
grep -Fq 'echod.prev' "$system/bin/start_animation.sh"
grep -Fq 'exit 0' "$system/bin/stop_animation.sh"
state="$system-data/misc/echolocal"
[ -s "$state/psk" ]
[ "$(wc -c < "$state/psk")" = 45 ]
for model in okay_nabu hey_jarvis hey_mycroft; do
    cmp "$system/etc/echolocal/models/$model.json" "$state/models/$model.json"
    cmp "$system/etc/echolocal/models/$model.tflite" "$state/models/$model.tflite"
done
key_hash=$(sha256sum "$state/psk" | awk '{print $1}')
printf '%s\n' 'custom model' > "$state/models/okay_nabu.json"
backup_hash=$(sha256sum "$system/bin/ledcontroller.orig" | awk '{print $1}')
start_backup_hash=$(sha256sum "$system/bin/start_animation.sh.orig" | awk '{print $1}')
stop_backup_hash=$(sha256sum "$system/bin/stop_animation.sh.orig" | awk '{print $1}')
run_update "$install_binary" "$INSTALL_ZIP" "$system" biscuit 999999
[ "$(sha256sum "$system/bin/ledcontroller.orig" | awk '{print $1}')" = "$backup_hash" ]
[ "$(sha256sum "$system/bin/start_animation.sh.orig" | awk '{print $1}')" = "$start_backup_hash" ]
[ "$(sha256sum "$system/bin/stop_animation.sh.orig" | awk '{print $1}')" = "$stop_backup_hash" ]
[ -L "$system/bin/ledcontroller" ]
[ "$(readlink "$system/bin/ledcontroller")" = "$system/app/echod/echod" ]
[ "$(sha256sum "$state/psk" | awk '{print $1}')" = "$key_hash" ]
[ "$(cat "$state/models/okay_nabu.json")" = 'custom model' ]

folded_df="$tmp/folded-df"
setup_system "$folded_df"
run_update_folded_df "$install_binary" "$folded_df"
[ -L "$folded_df/bin/ledcontroller" ]

no_glob_unzip="$tmp/no-glob-unzip"
setup_system "$no_glob_unzip"
run_update_no_glob_unzip "$install_binary" "$no_glob_unzip"
[ -L "$no_glob_unzip/bin/ledcontroller" ]

label_failure="$tmp/label-failure"
setup_system "$label_failure"
run_update_label_failure "$install_binary" "$label_failure"
[ -L "$label_failure/bin/ledcontroller" ]

minimal="$tmp/minimal"
setup_system "$minimal" absent
run_update "$install_binary" "$INSTALL_ZIP" "$minimal" biscuit 999999
[ -L "$minimal/bin/ledcontroller" ]
grep -qx 'animation_hooks=absent' "$minimal/etc/echolocal/.biscuit-addon"
[ ! -e "$minimal/bin/start_animation.sh" ]
[ ! -e "$minimal/bin/stop_animation.sh" ]

toybox_symlink="$tmp/toybox-symlink"
setup_system "$toybox_symlink"
mv "$toybox_symlink/bin/base64" "$toybox_symlink/bin/toybox"
ln -s toybox "$toybox_symlink/bin/base64"
run_update "$install_binary" "$INSTALL_ZIP" "$toybox_symlink" biscuit 999999
[ -L "$toybox_symlink/bin/base64" ]
[ "$(readlink "$toybox_symlink/bin/base64")" = toybox ]
[ -L "$toybox_symlink/bin/ledcontroller" ]

wrong_device="$tmp/wrong-device"
setup_system "$wrong_device"
if run_update "$install_binary" "$INSTALL_ZIP" "$wrong_device" not-biscuit 999999; then
    printf '%s\n' 'wrong device was accepted' >&2
    exit 1
fi
[ ! -e "$wrong_device/bin/ledcontroller.orig" ]
[ ! -e "$wrong_device/bin/start_animation.sh.orig" ]

missing_tool="$tmp/missing-tool"
setup_system "$missing_tool"
rm "$missing_tool/bin/base64"
if run_update "$install_binary" "$INSTALL_ZIP" "$missing_tool" biscuit 999999; then
    printf '%s\n' 'missing base tool was accepted' >&2
    exit 1
fi
[ ! -e "$missing_tool/bin/ledcontroller.orig" ]

wrong_base="$tmp/wrong-base"
setup_system "$wrong_base"
printf 'not the generic fallback\n' > "$wrong_base/bin/ledcontroller"
if run_update "$install_binary" "$INSTALL_ZIP" "$wrong_base" biscuit 999999; then
    printf '%s\n' 'wrong base was accepted' >&2
    exit 1
fi

no_space="$tmp/no-space"
setup_system "$no_space"
if run_update "$install_binary" "$INSTALL_ZIP" "$no_space" biscuit 0; then
    printf '%s\n' 'insufficient space was accepted' >&2
    exit 1
fi

bad_tree="$tmp/bad-tree"
bad_zip="$tmp/bad.zip"
unzip -q "$INSTALL_ZIP" -d "$bad_tree"
printf 'broken\n' >> "$bad_tree/payload-manifest.sha256"
(
    cd "$bad_tree"
    zip -X -q -r "$bad_zip" .
)
bad_hash="$tmp/bad-hash"
setup_system "$bad_hash"
if run_update "$install_binary" "$bad_zip" "$bad_hash" biscuit 999999; then
    printf '%s\n' 'bad payload manifest was accepted' >&2
    exit 1
fi

printf '%s\n' 'installer refusal, base-tool/CA preservation, symlink takeover, managed/absent hook, first-install state, and persistent-state checks passed'
