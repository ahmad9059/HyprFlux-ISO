#!/usr/bin/env python3
"""Read-only live hardware inventory; never use live DRM names as target config."""
import json
from pathlib import Path
import platform


def text(path):
    try:
        return path.read_text().strip()
    except OSError:
        return ''


def inventory(sysroot=Path('/sys')):
    devices = []
    for device in sorted((sysroot / 'bus/pci/devices').glob('*')):
        pci_class = text(device / 'class')
        # Display, network and storage controllers, without serial numbers.
        if not pci_class.startswith(('0x03', '0x02', '0x01')):
            continue
        driver = device / 'driver'
        devices.append(dict(address=device.name, pci_class=pci_class,
                            vendor=text(device / 'vendor'), device=text(device / 'device'),
                            driver=driver.resolve().name if driver.is_symlink() else None,
                            boot_vga=text(device / 'boot_vga') == '1'))
    connectors = []
    for connector in sorted((sysroot / 'class/drm').glob('card*-*')):
        if (connector / 'status').is_file():
            connectors.append(dict(name=connector.name, status=text(connector / 'status'),
                                   modes=text(connector / 'modes').splitlines()))
    warnings = []
    for device in devices:
        if not device['driver']:
            warnings.append(f"No live kernel driver bound to PCI device {device['address']}")
    if not any(item['status'] == 'connected' for item in connectors):
        warnings.append('No connected DRM display reported; headless or driver setup may be required')
    return dict(architecture=platform.machine(),
                firmware='uefi' if (sysroot / 'firmware/efi').is_dir() else 'bios',
                pci=devices, connectors=connectors, warnings=warnings,
                display_policy='Use preferred mode at desktop startup; live connector names are diagnostic only')


if __name__ == '__main__':
    print(json.dumps(inventory(), indent=2))
