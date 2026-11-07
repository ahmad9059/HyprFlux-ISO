#!/usr/bin/env python3
"""Report recorded VM acceptance for one exact ISO; never certify hardware."""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
REQUIRED_CASES = (
    ("desktop", "uefi", "automatic"),
    ("desktop", "bios", "automatic"),
    ("desktop", "uefi", "manual-gpt"),
    ("desktop", "bios", "manual-gpt"),
    ("full", "uefi", "automatic"),
    ("full", "bios", "automatic"),
)


def has_marker(path, marker):
    if not path.is_file():
        return False
    with path.open("rb") as stream:
        stream.seek(max(0, path.stat().st_size - 65536))
        data = stream.read()
    return re.search(rb"(?:^|[\r\n])" + re.escape(marker) + rb"(?:[\r\n]|$)", data) is not None


def recorded_results(base, digest):
    results = []
    for image_record in sorted(base.glob("*/image.sha256")):
        state = image_record.parent
        recorded = image_record.read_text().split()
        if not recorded or recorded[0] != digest:
            continue
        metadata = json.loads((state / "machine.json").read_text())
        embedded = (metadata.get("embedded", False) and not metadata.get("resumed", False)
                    and not metadata.get("tui_preview", False)
                    and not metadata.get("maintenance_test", False))
        screenshot = state / "desktop.png"
        png = False
        if screenshot.is_file():
            with screenshot.open("rb") as stream:
                png = stream.read(8) == b"\x89PNG\r\n\x1a\n"
        results.append({
            "state": str(state),
            "profile": metadata.get("profile", "full"),
            "firmware": "bios" if metadata["bios"] else "uefi",
            "layout": metadata.get("layout", "automatic"),
            "disk_bus": metadata["disk_bus"],
            "ipv4_network": metadata.get("ipv4_network", False),
            "virtual_audio": metadata.get("virtual_audio", False),
            "embedded_unmodified": bool(embedded),
            "install_pass": embedded and (state / "installed.ok").is_file(),
            "boot_pass": bool(embedded and (state / "installed.ok").is_file() and png
                              and has_marker(state / "serial.log", b"HYPRFLUX_TEST_BOOT_PASS")),
            "screenshot": str(screenshot) if png else None,
            "disk_retained": (state / "disk.qcow2").is_file(),
        })
    return results


def missing_cases(results):
    passed = {(row["profile"], row["firmware"], row["layout"])
              for row in results if row["install_pass"] and row["boot_pass"]}
    return [dict(profile=profile, firmware=firmware, layout=layout)
            for profile, firmware, layout in REQUIRED_CASES
            if (profile, firmware, layout) not in passed]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("iso", type=Path)
    parser.add_argument("--require-vm-matrix", action="store_true",
                        help="Exit nonzero if any required install/boot case is missing")
    args = parser.parse_args()
    image = args.iso.resolve()
    with image.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    results = recorded_results(ROOT / ".qemu-tests", digest)
    missing = missing_cases(results)
    print(json.dumps({
        "image": str(image), "sha256": digest, "results": results,
        "missing_vm_cases": missing, "vm_install_boot_matrix_complete": not missing,
        "production_certified": False,
        "separate_release_gates": ["ISO firmware smoke", "human TUI operation",
                                   "physical Intel/AMD and supported NVIDIA hardware",
                                   "Wi-Fi, audio playback, suspend/resume, external displays"],
        "note": "Recorded test results, not a rerun or visual/hardware inspection.",
    }, indent=2))
    if args.require_vm_matrix and missing:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
