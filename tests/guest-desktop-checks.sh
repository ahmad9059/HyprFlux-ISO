#!/bin/bash
# Sourced by the installed disposable-VM verifier, never on the host desktop.
set -euo pipefail
uid=$(id -u fluxcheck)
wayland_socket="${wayland_socket:?Verifier must discover the live Wayland socket}"
desktop_user=(runuser -u fluxcheck -- env HOME=/home/fluxcheck
    PATH=/usr/local/bin:/usr/bin
    XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" WAYLAND_DISPLAY="${wayland_socket##*/}"
    DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
    HYPRLAND_INSTANCE_SIGNATURE="$HYPRLAND_INSTANCE_SIGNATURE")
pacman -Q qt6-5compat foot kitty papirus-icon-theme
"${desktop_user[@]}" sh -c 'command -v kitty; for driver in /sys/class/drm/card[0-9]*/device/driver; do readlink -f "$driver"; done'
"${desktop_user[@]}" foot --check-config
python - <<'FOOT_CONFIG'
import configparser
config = configparser.ConfigParser(interpolation=None)
config.read('/home/fluxcheck/.config/foot/foot.ini')
assert config.getboolean('colors-dark', 'blur')
assert 0 < config.getfloat('colors-dark', 'alpha') < 1
FOOT_CONFIG
for size in 22x22 24x24 32x32 48x48 64x64; do
    [[ $(readlink -f "/usr/share/icons/Papirus-Dark/$size/places/folder.svg") == */folder-cyan.svg ]]
done
[[ $("${desktop_user[@]}" gsettings get org.gnome.desktop.interface icon-theme) == "'Papirus-Dark'" ]]
"${desktop_user[@]}" hyprctl -j getoption decoration:blur:enabled | python -c \
    'import json,sys; assert json.load(sys.stdin)["bool"] is True'
"${desktop_user[@]}" hyprctl -j getoption decoration:blur:passes | python -c \
    'import json,sys; assert json.load(sys.stdin)["int"] > 0'
mkdir -p /var/log/hyprflux-desktop-checks
desktop_check_dir=$(mktemp -d /var/log/hyprflux-desktop-checks/run.XXXXXX)
chown "$uid:$(id -g fluxcheck)" "$desktop_check_dir"
if [[ -f /etc/hyprflux-test-virtual-audio ]]; then
    audio_ready=false
    for ((attempt=0; attempt<40; attempt++)); do
        if "${desktop_user[@]}" pw-dump | python -c \
            'import json,sys; sys.exit(not any(n.get("info",{}).get("props",{}).get("media.class")=="Audio/Sink" and n.get("info",{}).get("props",{}).get("device.api")=="alsa" for n in json.load(sys.stdin)))'; then
            audio_ready=true
            break
        fi
        sleep .25
    done
    [[ "$audio_ready" == true ]] || { echo 'ERROR: virtual ALSA audio sink missing'; exit 1; }
    python - "$desktop_check_dir/tone.wav" <<'VIRTUAL_AUDIO'
import math, struct, sys, wave
with wave.open(sys.argv[1], 'wb') as output:
    output.setparams((2, 2, 48000, 0, 'NONE', 'not compressed'))
    output.writeframes(b''.join(struct.pack('<hh', *([int(800 * math.sin(2 * math.pi * 440 * i / 48000))] * 2)) for i in range(48000)))
VIRTUAL_AUDIO
    "${desktop_user[@]}" wpctl status
    "${desktop_user[@]}" timeout --kill-after=2s 15 pw-play "$desktop_check_dir/tone.wav"
    echo HYPRFLUX_VIRTUAL_AUDIO_STREAM_PASS
fi
terminal_pids=()
cleanup_desktop_checks() {
    local pid
    for pid in "${terminal_pids[@]}"; do kill "$pid" 2>/dev/null || true; done
    for pid in "${terminal_pids[@]}"; do wait "$pid" 2>/dev/null || true; done
}
for terminal in kitty foot; do
    "${desktop_user[@]}" timeout --kill-after=2s 30 "$terminal" > "$desktop_check_dir/$terminal.log" 2>&1 &
    terminal_pids+=("$!")
    mapped=false
    for ((attempt=0; attempt<40; attempt++)); do
        if "${desktop_user[@]}" hyprctl -j clients | python -c \
            'import json,sys; sys.exit(not any(c["class"] == sys.argv[1] and c.get("mapped") for c in json.load(sys.stdin)))' "$terminal"; then
            mapped=true
            break
        fi
        sleep .25
    done
    cat "$desktop_check_dir/$terminal.log"
    [[ "$mapped" == true ]] || { echo "ERROR: $terminal failed to map a real terminal window"; exit 1; }
done
sleep 3
for terminal in kitty foot; do
    "${desktop_user[@]}" hyprctl -j clients | python -c \
        'import json,sys; assert any(c["class"] == sys.argv[1] and c.get("mapped") for c in json.load(sys.stdin))' "$terminal"
done
"${desktop_user[@]}" grim "$desktop_check_dir/terminals-blur-enabled.png"
echo HYPRFLUX_TERMINALS_AND_CYAN_CHECK_PASS
cleanup_desktop_checks
terminal_pids=()
# Load the actual theme, not SDDM's fallback login. Software Qt rendering only
# isolates QML/theme dependencies from virgl's separate OpenGL limitations.
"${desktop_user[@]}" timeout --kill-after=2s 15 env QT_QUICK_BACKEND=software \
    QT_QPA_PLATFORM=wayland QT_QUICK_CONTROLS_STYLE=Basic \
    sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/HyprFlux-sddm-theme \
    > "$desktop_check_dir/greeter.log" 2>&1 &
terminal_pids+=("$!")
sleep 5
cat "$desktop_check_dir/greeter.log"
if grep -E 'is not installed|is not a type|Cannot assign|failed to load|Error loading|QQmlApplicationEngine failed' "$desktop_check_dir/greeter.log"; then
    echo 'ERROR: actual SDDM theme failed QML rendering'
    exit 1
fi
"${desktop_user[@]}" hyprctl -j clients | python -c \
    'import json,sys; assert any("sddm-greeter" in c["class"] and c.get("mapped") for c in json.load(sys.stdin))'
"${desktop_user[@]}" grim "$desktop_check_dir/greeter.png"
echo "HYPRFLUX_THEMED_GREETER_RENDER_PASS screenshot=$desktop_check_dir/greeter.png"
cleanup_desktop_checks
