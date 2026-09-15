#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
HELPER="$ROOT/payload/system/bin/echolocal"
sh -n "$HELPER"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
sys="$tmp/system"
state="$tmp/data/misc/echolocal"
props="$tmp/properties"
mkdir -p "$sys/bin" "$sys/etc/echolocal/models"
sed '1c#!/bin/sh' "$HELPER" > "$sys/bin/echolocal"
chmod 0755 "$sys/bin/echolocal"

cat > "$sys/bin/id" <<'EOF'
#!/bin/sh
printf '%s\n' 'uid=0(root) gid=0(root)'
EOF
cat > "$sys/bin/chown" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$sys/bin/setprop" <<'EOF'
#!/bin/sh
printf '%s=%s\n' "$1" "$2" >> "$TEST_PROPS"
EOF
chmod 0755 "$sys/bin/id" "$sys/bin/chown" "$sys/bin/setprop"

for model in okay_nabu hey_jarvis hey_mycroft; do
    printf '{"name":"%s"}\n' "$model" > "$sys/etc/echolocal/models/$model.json"
    printf 'model-%s\n' "$model" > "$sys/etc/echolocal/models/$model.tflite"
done

run_repair() {
    ECHOLOCAL_SYSTEM="$sys" ECHOLOCAL_STATE="$state" TEST_PROPS="$props" \
        sh "$sys/bin/echolocal" repair
}

if ECHOLOCAL_SYSTEM="$sys" ECHOLOCAL_STATE="$state" TEST_PROPS="$props" PATH="$sys/bin" \
    /bin/sh "$sys/bin/echolocal" repair >"$tmp/missing.out" 2>"$tmp/missing.err"; then
    printf '%s\n' 'missing base tool was accepted' >&2
    exit 1
fi
grep -Fq 'missing base tool: base64' "$tmp/missing.err"

run_repair >/dev/null 2>"$tmp/first.err"
[ -s "$state/psk" ]
for model in okay_nabu hey_jarvis hey_mycroft; do
    [ -f "$state/models/$model.json" ]
    [ -f "$state/models/$model.tflite" ]
done
grep -qx 'ctl.restart=ledcontroller' "$props"
key_hash=$(sha256sum "$state/psk" | awk '{print $1}')
printf 'custom\n' > "$state/models/okay_nabu.json"
: > "$props"
run_repair >/dev/null
[ "$(cat "$state/models/okay_nabu.json")" = custom ]
[ "$(sha256sum "$state/psk" | awk '{print $1}')" = "$key_hash" ]
grep -qx 'ctl.restart=ledcontroller' "$props"

rm -rf "$state"
: > "$props"
run_repair >/dev/null 2>"$tmp/wipe.err"
[ -s "$state/psk" ]
[ -f "$state/models/hey_mycroft.tflite" ]
grep -qx 'ctl.restart=ledcontroller' "$props"
grep -Fq 'new ESPHome key was generated' "$tmp/wipe.err"

printf '%s\n' 'repair first-run, preservation, and data-wipe checks passed'
