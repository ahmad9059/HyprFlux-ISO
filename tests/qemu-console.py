#!/usr/bin/env python3
"""Send keyboard input to a disposable test VM without interrupting its installer.

Use VT2 for a separate live-root shell; installer output continues on ttyS0.
"""
import argparse
import hashlib
from pathlib import Path
import re
import shutil
import time

from qmp import request

ROOT = Path(__file__).resolve().parents[1]
KEYS = {
    " ": "spc", "\n": "ret", "\t": "tab", "/": "slash", ".": "dot",
    "-": "minus", "_": "shift-minus", ">": "shift-dot", "<": "shift-comma",
    "\\": "backslash", "|": "shift-backslash", ":": "shift-semicolon", ";": "semicolon",
    '"': "shift-apostrophe", "'": "apostrophe", "=": "equal", "+": "shift-equal",
    ",": "comma", "[": "bracket_left", "]": "bracket_right",
    "{": "shift-bracket_left", "}": "shift-bracket_right",
    "`": "grave_accent", "~": "shift-grave_accent", "(": "shift-9", ")": "shift-0",
    "*": "shift-8", "&": "shift-7", "^": "shift-6", "%": "shift-5", "$": "shift-4",
    "#": "shift-3", "@": "shift-2", "!": "shift-1", "?": "shift-slash",
}


def key_for(char):
    if char in KEYS:
        return KEYS[char]
    if char.isascii() and char.isalpha():
        return f"shift-{char.lower()}" if char.isupper() else char
    if char in "0123456789":
        return char
    raise ValueError(f"Unsupported console character: {char!r}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("state", type=Path)
    parser.add_argument("--login-root", action="store_true", help="Switch to VT2 and log in as live root (empty password)")
    parser.add_argument("--key", action="append", default=[], help="HMP key chord, e.g. ctrl-alt-f2")
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--text", help="Type text without automatically pressing Enter")
    action.add_argument("--command", help="Type a shell command and press Enter")
    action.add_argument("--diagnose", action="store_true", help="Print read-only target package diagnostics to serial.log")
    action.add_argument("--probe-config", action="store_true", help="Validate source config in a temporary guest HOME")
    parser.add_argument("--screenshot", action="store_true")
    args = parser.parse_args()
    state = args.state.resolve()
    if not state.is_relative_to((ROOT / ".qemu-tests").resolve()):
        parser.error("State must be inside this project's .qemu-tests directory")
    command = (state / "command.txt").read_text().splitlines()
    endpoint = command[command.index("-qmp") + 1]
    qmp = endpoint.split("unix:", 1)[1].split(",", 1)[0]

    def key(chord):
        if not re.fullmatch(r"[a-z0-9_-]+", chord):
            parser.error("Invalid key chord")
        request(qmp, "human-monitor-command", {"command-line": f"sendkey {chord} 20"})
        time.sleep(0.05)

    def text(value):
        # Validate the whole string before injecting any input.
        chords = [key_for(char) for char in value]
        for chord in chords:
            key(chord)

    if args.login_root:
        key("ctrl-alt-f2")
        time.sleep(1)
        text("root\n")
        time.sleep(1)
    for chord in args.key:
        key(chord)
    if args.diagnose or args.probe_config:
        source_option = command[command.index("-fsdev") + 1]
        source = Path(source_option.split("path=", 1)[1].split(",", 1)[0]).resolve()
        if not source.is_relative_to(state):
            parser.error("Unexpected source-share location")
        # Add only a read-only diagnostic script; never modify the running
        # installer's frozen inputs. Record this extra tool separately.
        name = "guest-config-probe.sh" if args.probe_config else "guest-diagnostics.sh"
        diagnostic = ROOT / "tests" / name
        shutil.copyfile(diagnostic, source / "tests" / name)
        (state / f"{diagnostic.stem}.sha256").write_text(hashlib.sha256(diagnostic.read_bytes()).hexdigest() + f"  {name}\n")
        text(f"bash /run/hyprflux-source/tests/{name}\n")
    elif args.command is not None:
        text(args.command + "\n")
    elif args.text is not None:
        text(args.text)
    if args.screenshot:
        request(qmp, "screendump", {"filename": str(state / "console-debug.png"), "format": "png"})
    print(f"Input sent. Installer output remains in {state}/serial.log")


if __name__ == "__main__":
    main()
