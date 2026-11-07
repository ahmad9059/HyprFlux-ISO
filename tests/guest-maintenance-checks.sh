#!/bin/bash
# Additional fault-injection/application checks on a disposable overlay ONLY.
# Not sourced by the clean-install fixture or copied into a production image.
set -euo pipefail
[[ $(systemd-detect-virt) == qemu || $(systemd-detect-virt) == kvm ]]
[[ $(< /etc/hostname) == hyprflux-test && -f /etc/hyprflux-test-maintenance-overlay ]]
uid=$(id -u fluxcheck)
wayland_socket="${wayland_socket:?Verifier must discover the active Wayland socket}"
work=$(mktemp -d /var/log/hyprflux-desktop-checks/maintenance.XXXXXX)
chown "$uid:$(id -g fluxcheck)" "$work"
maintenance_user=(runuser -u fluxcheck -- env HOME=/home/fluxcheck PATH=/usr/local/bin:/usr/bin
    XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" WAYLAND_DISPLAY="${wayland_socket##*/}"
    HYPRLAND_INSTANCE_SIGNATURE="$HYPRLAND_INSTANCE_SIGNATURE"
    DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus")
# Match ordinary desktop launches, including XWayland applications. A root
# system service does not inherit the graphical user's DISPLAY/session values.
while IFS= read -r session_value; do
    case "$session_value" in
        DISPLAY=*|XAUTHORITY=*|XDG_SESSION_TYPE=*|XDG_CURRENT_DESKTOP=*)
            maintenance_user+=("$session_value") ;;
    esac
done < <("${maintenance_user[@]}" systemctl --user show-environment)

# Test the actual pacman upgrade hook, not another direct helper invocation.
version=$(pacman -Q papirus-icon-theme)
version="${version#* }"
archive=""
for candidate in /var/cache/pacman/pkg/papirus-icon-theme-"$version"-*.pkg.tar.*; do
    [[ -f "$candidate" && "$candidate" != *.sig && -f "$candidate.sig" ]] || continue
    archive="$candidate"
    break
done
[[ -n "$archive" ]]
sed -E 's/^[#[:space:]]*LocalFileSigLevel[[:space:]]*=.*/LocalFileSigLevel = Required/' \
    /etc/pacman.conf > "$work/require-signatures.conf"
grep -Eq '^LocalFileSigLevel[[:space:]]*=[[:space:]]*Required' "$work/require-signatures.conf"
[[ -f /usr/share/icons/Papirus/48x48/places/folder-blue.svg ]]
ln -sfn folder-blue.svg /usr/share/icons/Papirus/48x48/places/folder.svg
[[ $(readlink -f /usr/share/icons/Papirus/48x48/places/folder.svg) == */folder-blue.svg ]]
pacman --config "$work/require-signatures.conf" -U --noconfirm "$archive" | tee "$work/papirus-reinstall.log"
grep -q 'Restoring HyprFlux cyan Papirus folders' "$work/papirus-reinstall.log"
for size in 22x22 24x24 32x32 48x48 64x64; do
    [[ $(readlink -f "/usr/share/icons/Papirus-Dark/$size/places/folder.svg") == */folder-cyan.svg ]]
done
echo HYPRFLUX_PAPIRUS_REAL_REINSTALL_HOOK_PASS

for app in thunar firefox chromium; do
    args=("$app")
    case "$app" in
        thunar) args+=(/home/fluxcheck) ;;
        firefox) args+=(--no-remote --profile "$work/firefox-profile" about:blank) ;;
        chromium) args+=(--user-data-dir="$work/chromium-profile" --no-first-run --disable-default-apps about:blank) ;;
    esac
    if [[ "$app" == firefox ]]; then
        install -d -o "$uid" -g "$(id -g fluxcheck)" "$work/firefox-profile"
    fi
    "${maintenance_user[@]}" timeout --kill-after=3s 90 "${args[@]}" > "$work/$app.log" 2>&1 &
    app_pid=$!
    mapped=false
    for ((attempt=0; attempt<240; attempt++)); do
        if "${maintenance_user[@]}" hyprctl -j clients | python -c \
            'import json,sys; sys.exit(not any(sys.argv[1] in c["class"].lower() and c.get("mapped") for c in json.load(sys.stdin)))' "$app"; then
            mapped=true
            break
        fi
        sleep .25
    done
    "${maintenance_user[@]}" hyprctl -j clients > "$work/$app-clients.json"
    cat "$work/$app.log"
    [[ "$mapped" == true ]] || { kill "$app_pid" 2>/dev/null || true; echo "ERROR: $app did not map"; exit 1; }
    workspace=$(python - "$work/$app-clients.json" "$app" <<'FOCUS_WORKSPACE'
import json, sys
with open(sys.argv[1]) as stream:
    clients = json.load(stream)
print(next(c['workspace']['name'] for c in clients if sys.argv[2] in c['class'].lower() and c.get('mapped')))
FOCUS_WORKSPACE
)
    [[ "$workspace" =~ ^[0-9]+$ ]]
    "${maintenance_user[@]}" hyprctl dispatch "hl.dsp.focus({ workspace = \"$workspace\" })"
    address=$(python - "$work/$app-clients.json" "$app" <<'FOCUS_ADDRESS'
import json, sys
with open(sys.argv[1]) as stream:
    clients = json.load(stream)
print(next(c['address'] for c in clients if sys.argv[2] in c['class'].lower() and c.get('mapped')))
FOCUS_ADDRESS
)
    [[ "$address" =~ ^0x[0-9a-fA-F]+$ ]]
    "${maintenance_user[@]}" hyprctl dispatch "hl.dsp.focus({ window = \"address:$address\" })"
    "${maintenance_user[@]}" hyprctl -j activeworkspace > "$work/$app-activeworkspace.json"
    "${maintenance_user[@]}" hyprctl -j activewindow > "$work/$app-activewindow.json"
    python - "$work" "$app" "$workspace" <<'VERIFY_FOCUS'
import json, pathlib, sys
work, app, workspace = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
active_workspace = json.loads((work / f'{app}-activeworkspace.json').read_text())
active_window = json.loads((work / f'{app}-activewindow.json').read_text())
assert active_workspace['name'] == workspace, active_workspace
assert app in active_window['class'].lower(), active_window
assert active_window.get('mapped') and not active_window.get('hidden'), active_window
VERIFY_FOCUS
    sleep 3
    "${maintenance_user[@]}" grim "$work/$app.png"
    echo "HYPRFLUX_APPLICATION_WINDOW_PASS app=$app"
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
done
echo "HYPRFLUX_MAINTENANCE_OVERLAY_PASS evidence=$work"
