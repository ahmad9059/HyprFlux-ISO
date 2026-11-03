#!/bin/bash
# Installed test VM only. A successful service start is not a desktop test.
set -euo pipefail
boot_exit() {
    local result=$?
    if [[ -n "${capture_dir:-}" ]]; then rm -rf -- "$capture_dir"; fi
    if (( result != 0 )); then
        ps -eo user,pid,ppid,etime,args
        cat /home/fluxcheck/.local/state/hyprflux/first-boot.log || true
        runuser -u fluxcheck -- env XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR:-/run/user/1000}/bus" \
            systemctl --user list-jobs --no-pager || true
        # Diagnose a missing bar only AFTER acceptance has already failed. This
        # bounded launch must never turn failed autostart into a passing test.
        if ! pgrep -u "${uid:-1000}" -x waybar >/dev/null; then
            for diagnostic_socket in "${XDG_RUNTIME_DIR:-/run/user/1000}"/wayland-*; do
                [[ -S "$diagnostic_socket" ]] || continue
                echo '=== Failed-autostart Waybar diagnostic (not acceptance) ==='
                timeout --kill-after=2s 10 runuser -u fluxcheck -- env \
                    XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
                    WAYLAND_DISPLAY="${diagnostic_socket##*/}" \
                    HYPRLAND_INSTANCE_SIGNATURE="${instance##*/}" \
                    DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus" \
                    waybar -l debug || true
                break
            done
        fi
        journalctl -b --no-pager -n 80
        journalctl --sync || true
        sync
        echo "HYPRFLUX_TEST_BOOT_FAILED exit=$result"
    fi
}
trap boot_exit EXIT
assert_installer_cleanup() {
    local root="${1%/}" path
    for path in etc/sudoers.d/hyprflux-temp etc/sudoers.d/hyprflux-pacman \
        usr/local/bin/chsh usr/local/bin/gsettings usr/local/bin/nwg-look \
        usr/local/bin/yay-iso usr/local/bin/systemctl-shim tmp/hyprflux-module-env.sh; do
        if [[ -e "$root/$path" || -L "$root/$path" ]]; then
            echo "ERROR: installer artifact remains: /$path"
            return 1
        fi
    done
    [[ $(head -c 4 "$root/usr/bin/systemctl") == $'\177ELF' ]] || return 1
    echo 'Installer cleanup verified; systemctl is ELF.'
}
assert_installer_cleanup /
uid=$(id -u fluxcheck)
export XDG_RUNTIME_DIR="/run/user/$uid"
if [[ -f /etc/hyprflux-test-password-login ]]; then
    if grep -R -Eq '^[[:space:]]*User[[:space:]]*=[[:space:]]*fluxcheck[[:space:]]*$' \
        /etc/sddm.conf /etc/sddm.conf.d 2>/dev/null; then
        echo 'ERROR: password-login test has a configured test autologin user'
        exit 1
    fi
    for ((attempt=0; attempt<90; attempt++)); do
        if pgrep -f '/sddm-greeter' >/dev/null; then break; fi
        sleep 1
    done
    pgrep -f '/sddm-greeter' >/dev/null
    echo HYPRFLUX_TEST_GREETER_READY
fi
for ((attempt=0; attempt<180; attempt++)); do
    instance=$(find "$XDG_RUNTIME_DIR/hypr" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1 || true)
    if [[ -n "$instance" && -S "$instance/.socket.sock" \
        && -f /home/fluxcheck/.config/hyprflux-first-boot-done ]] \
        && pgrep -u "$uid" -x waybar >/dev/null; then
        break
    fi
    sleep 1
done
systemctl is-active sddm NetworkManager
pgrep -u "$uid" -x Hyprland
pgrep -u "$uid" -x waybar
[[ -f /home/fluxcheck/.config/hyprflux-first-boot-done ]]
export HYPRLAND_INSTANCE_SIGNATURE="${instance##*/}"
errors=$(runuser -u fluxcheck -- env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    HYPRLAND_INSTANCE_SIGNATURE="$HYPRLAND_INSTANCE_SIGNATURE" hyprctl configerrors)
[[ -z "${errors//[[:space:]]/}" ]] || { echo "$errors"; exit 1; }
runuser -u fluxcheck -- env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    HYPRLAND_INSTANCE_SIGNATURE="$HYPRLAND_INSTANCE_SIGNATURE" hyprctl monitors
# Compare the exact legacy dispatch packet used by official Waybar 0.15.0 with
# the Lua packet supported by waybar-git. Do not silently replace a working bar.
runuser -u fluxcheck -- env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    HYPRLAND_INSTANCE_SIGNATURE="$HYPRLAND_INSTANCE_SIGNATURE" python - <<'PY'
import json, os, socket
from pathlib import Path
path = Path(os.environ['XDG_RUNTIME_DIR']) / 'hypr' / os.environ['HYPRLAND_INSTANCE_SIGNATURE'] / '.socket.sock'
def request(message):
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(3)
        client.connect(str(path))
        client.sendall(message.encode())
        return client.recv(65536).decode()
original = json.loads(request('j/activeworkspace'))['name']
legacy = request('dispatch workspace 2')
modern = request('/dispatch hl.dsp.focus({ workspace = "2" })')
restored = request('/dispatch hl.dsp.focus({ workspace = ' + json.dumps(original, ensure_ascii=False) + ' })')
print('HYPRFLUX_WAYBAR_PROTOCOL_EVALUATION=' + json.dumps(dict(
    official_0_15_legacy_reply=legacy, lua_reply=modern, restored_reply=restored)))
if modern.strip() != 'ok' or restored.strip() != 'ok':
    raise SystemExit('Lua workspace dispatch failed; cannot accept a merely running bar')
PY
runuser -u fluxcheck -- env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    HYPRLAND_INSTANCE_SIGNATURE="$HYPRLAND_INSTANCE_SIGNATURE" hyprctl deprecated-config
runuser -u fluxcheck -- env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    HYPRLAND_INSTANCE_SIGNATURE="$HYPRLAND_INSTANCE_SIGNATURE" hyprctl layers
runuser -u fluxcheck -- env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus" systemctl --user is-active pipewire wireplumber
# EGL/virgl can expose a DMA-BUF without a QMP screendump surface. Capture
# inside the actual compositor and transfer the PNG through the serial log.
sleep 3
pgrep -u "$uid" -x waybar
settled_layers=$(runuser -u fluxcheck -- env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    HYPRLAND_INSTANCE_SIGNATURE="$HYPRLAND_INSTANCE_SIGNATURE" hyprctl layers)
printf '%s\n' "$settled_layers"
grep -Eq 'namespace: waybar([,[:space:]]|$)' <<< "$settled_layers"
wayland_socket=""
# Do not stat unrelated FUSE/portal mounts as root or use head under pipefail.
for candidate in "$XDG_RUNTIME_DIR"/wayland-*; do
    if [[ -S "$candidate" ]]; then
        wayland_socket="$candidate"
        break
    fi
done
[[ -n "$wayland_socket" ]]
capture_dir=$(mktemp -d /tmp/hyprflux-desktop-capture.XXXXXX)
chown "$uid:$(id -g fluxcheck)" "$capture_dir"
runuser -u fluxcheck -- env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    WAYLAND_DISPLAY="${wayland_socket##*/}" grim "$capture_dir/desktop.png"
[[ $(stat -c %s "$capture_dir/desktop.png") -le 16777216 ]]
echo HYPRFLUX_SCREENSHOT_BEGIN
base64 "$capture_dir/desktop.png"
echo HYPRFLUX_SCREENSHOT_END
journalctl --sync
sync
echo HYPRFLUX_TEST_BOOT_PASS
