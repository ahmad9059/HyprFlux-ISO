#!/usr/bin/env python3
"""KVM smoke/full-install runner with read-only source hot-loading and serial logs.

Direct boot is fast but does NOT test ISO firmware loaders. --firmware-boot does.
No host block device is ever attached. Each install gets a new disposable qcow2.
"""
import argparse
import base64
import binascii
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import time

from qmp import request

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()


def send_serial(connection, data):
    # Pace UART input: a large socket write can overrun the emulated 16550
    # while the guest is in its tiny initramfs shell.
    for offset in range(0, len(data), 8):
        connection.sendall(data[offset:offset + 8])
        time.sleep(0.02)


def shell_ready(data):
    return b"Installer exited." in data or b"hyprflux#" in data


def marker_seen(data, marker, details=False):
    ending = rb"(?:[ \r\n]|$)" if details else rb"(?:[\r\n]|$)"
    return re.search(rb"(?:^|[\r\n])" + re.escape(marker) + ending, data) is not None


def guest_screenshot(data):
    match = re.search(rb"(?:^|[\r\n])HYPRFLUX_SCREENSHOT_BEGIN\r?\n([A-Za-z0-9+/=\r\n]+)HYPRFLUX_SCREENSHOT_END(?:[\r\n]|$)", data)
    if match is None:
        return None
    encoded = re.sub(rb"[\r\n]", b"", match[1])
    if len(encoded) > 22369624:
        raise ValueError("Guest screenshot exceeds 16 MiB")
    try:
        image = base64.b64decode(encoded, validate=True)
    except binascii.Error as error:
        raise ValueError("Invalid guest screenshot encoding") from error
    if not image.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError("Guest screenshot is not PNG")
    return image


def resumed_machine(metadata, profile):
    # A desktop-integration resume uses current hot-loaded scripts, even if
    # the original installation exercised the ISO's embedded installer.
    return {**metadata, "profile": profile, "embedded": False, "resumed": True}


def latest_iso(directory):
    # A checksum sidecar is written only after mkarchiso completes. Do not
    # silently select a partial image from a failed or still-running build.
    candidates = [path for pattern in ('*.iso', '*/*.iso')
                  for path in directory.glob(pattern)
                  if path.is_file() and not path.is_symlink()
                  and path.with_name(path.name + '.sha256').is_file()]
    return max(candidates, key=lambda path: (path.stat().st_mtime_ns, str(path)), default=None)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("iso", nargs="?", type=Path)
    parser.add_argument("--bios", action="store_true")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--install", action="store_true", help="Install onto a NEW disposable VM disk")
    mode.add_argument("--boot", type=Path, help="Boot and verify an installed test state directory")
    mode.add_argument("--resume", type=Path, help="Retry desktop integration on a configured test disk; never repartition")
    parser.add_argument("--firmware-boot", action="store_true", help="Test ISO firmware loader, not direct kernel boot")
    parser.add_argument("--3d", dest="three_d", action="store_true", help="Use virgl/EGL for real Hyprland session tests")
    parser.add_argument("--render-node", type=Path, help="EGL render device (otherwise probe available devices)")
    parser.add_argument("--disk-bus", choices=("virtio", "scsi", "sata", "nvme"), default="virtio")
    parser.add_argument("--swap", type=int, default=0, help="Swap GiB for full-install testing (0-8)")
    parser.add_argument("--profile", choices=("desktop", "full"), help="Application profile (new installs default to desktop)")
    parser.add_argument("--embedded", action="store_true", help="Test the ISO's embedded installer, not hot-loaded installer scripts (new installs only)")
    parser.add_argument("--package-cache", type=Path, help="Read-only host package cache to seed into the disposable target (normal pacman signature checks still apply)")
    parser.add_argument("--manual-layout", action="store_true", help="Use a prepared GPT manual-partition fixture and real manual validation (new install, no swap)")
    parser.add_argument("--timeout", type=int, default=None)
    args = parser.parse_args()
    if args.embedded and not args.install:
        parser.error("--embedded requires a new --install run")
    if args.manual_layout and (not args.install or args.swap != 0):
        parser.error("--manual-layout requires a new --install with --swap 0")
    if args.package_cache:
        if args.boot or not (args.install or args.resume):
            parser.error("--package-cache requires --install or --resume")
        args.package_cache = args.package_cache.resolve()
        if not args.package_cache.is_dir() or any(char in str(args.package_cache) for char in ',\n\r'):
            parser.error("Package cache must be an existing directory without commas or newlines in its path")
    if args.boot and args.profile is not None:
        parser.error("--profile selects installation contents; it cannot change an already-installed boot test")
    args.install = args.install or bool(args.resume)
    args.timeout = args.timeout or (10800 if args.install else 600)
    if not 0 <= args.swap <= 8:
        parser.error("--swap must be between 0 and 8 GiB")
    for tool in ("qemu-system-x86_64", "qemu-img", "xorriso", "blkid"):
        if not shutil.which(tool):
            parser.error(f"Missing dependency: {tool}")
    if not os.access("/dev/kvm", os.R_OK | os.W_OK):
        parser.error("KVM unavailable; enable virtualization and grant /dev/kvm access")
    if args.install and args.firmware_boot:
        parser.error("Use direct boot for automated installation; firmware ISO boot is a separate smoke test")
    base = ROOT / ".qemu-tests"
    base.mkdir(mode=0o700, exist_ok=True)
    if args.boot or args.resume:
        state = (args.boot or args.resume).resolve()
        if not state.is_relative_to(base.resolve()):
            parser.error("Installed test states must be inside this project's .qemu-tests directory")
        if args.boot and not (state / "installed.ok").is_file():
            parser.error("Not a completed test installation (installed.ok missing)")
        metadata = json.loads((state / "machine.json").read_text())
        args.bios = metadata["bios"]
        args.disk_bus = metadata["disk_bus"]
        args.profile = args.profile or metadata.get("profile", "full")
        if args.profile not in ("desktop", "full"):
            parser.error("Invalid application profile in machine metadata")
        if not isinstance(args.bios, bool) or args.disk_bus not in ("virtio", "scsi", "sata", "nvme"):
            parser.error("Invalid machine metadata")
    else:
        import tempfile
        state = Path(tempfile.mkdtemp(prefix="bios-" if args.bios else "uefi-", dir=base))
        run("qemu-img", "create", "-f", "qcow2", str(state / "disk.qcow2"), "40G")
        args.profile = args.profile or "desktop"
        metadata = {"bios": args.bios, "disk_bus": args.disk_bus, "profile": args.profile, "embedded": args.embedded, "layout": "manual-gpt" if args.manual_layout else "automatic"}
        (state / "machine.json").write_text(json.dumps(metadata))
    disk_path = state / "disk.qcow2"
    if disk_path.is_symlink() or not disk_path.is_file():
        parser.error("Test disk must be a regular qcow2 file, never a symlink or host device")
    lock = (state / "runner.lock").open("w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        parser.error("This test state is already running")
    previous_command = (state / "command.txt").read_text() if (state / "command.txt").is_file() else ""
    if args.boot or args.resume:
        history = state / "previous-attempts" / str(time.time_ns())
        history.mkdir(parents=True)
        for name in ("serial.log", "qemu.log", "command.txt", "source.sha256", "image.sha256", "machine.json", "failure.png", "desktop.png"):
            if (state / name).is_file():
                shutil.copyfile(state / name, history / name)
    if args.resume:
        metadata = resumed_machine(metadata, args.profile)
        (state / "machine.json").write_text(json.dumps(metadata))
    # QEMU UNIX socket paths must fit sockaddr_un (108 bytes).
    import tempfile
    sockets = tempfile.TemporaryDirectory(prefix="hq-", dir="/tmp/opencode" if Path("/tmp/opencode").is_dir() else None)
    serial = Path(sockets.name) / "serial.sock"
    qmp = Path(sockets.name) / "qmp.sock"
    command = ["qemu-system-x86_64", "-machine", "q35", "-enable-kvm", "-cpu", "host", "-m", "6G", "-smp", "4",
               "-netdev", "user,id=net0", "-device", "virtio-net-pci,netdev=net0",
               "-chardev", f"socket,id=serial0,path={serial},server=on,wait=off",
               "-device", "isa-serial,chardev=serial0", "-monitor", "none", "-no-reboot",
               "-qmp", f"unix:{qmp},server=on,wait=off"]
    devices = {"virtio": "vda", "scsi": "sda", "sata": "sda", "nvme": "nvme0n1"}
    if args.disk_bus == "virtio":
        command += ["-drive", f"file={state}/disk.qcow2,if=virtio,format=qcow2"]
    else:
        command += ["-drive", f"file={state}/disk.qcow2,if=none,id=target,format=qcow2"]
        if args.disk_bus == "scsi":
            command += ["-device", "virtio-scsi-pci,id=scsi", "-device", "scsi-hd,drive=target,bus=scsi.0"]
        elif args.disk_bus == "sata":
            command += ["-device", "ich9-ahci,id=ahci", "-device", "ide-hd,drive=target,bus=ahci.0"]
        else:
            command += ["-device", "nvme,drive=target,serial=HYPRFLUX_TEST"]
    if args.three_d:
        nodes = sorted(Path("/dev/dri").glob("renderD*"))
        node = None
        with (state / "graphics-preflight.log").open("w") as preflight:
            for candidate in ([args.render_node] if args.render_node else nodes):
                if not os.access(candidate, os.R_OK | os.W_OK):
                    continue
                result = subprocess.run(
                    [sys.executable, str(ROOT / "tests/qemu-preflight.py"), "--render-node", str(candidate)],
                    text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30,
                )
                preflight.write(f"{candidate}: exit {result.returncode}\n{result.stdout}\n")
                if result.returncode == 0:
                    node = candidate
                    break
        if node is None:
            parser.error(f"No working EGL render node; inspect {state}/graphics-preflight.log")
        print(f"Verified graphics device: {node}", flush=True)
        command += ["-display", f"egl-headless,rendernode={node}", "-device", "virtio-vga-gl"]
    else:
        command += ["-display", "none", "-device", "virtio-vga"]
    if not args.bios:
        code = Path("/usr/share/edk2/x64/OVMF_CODE.4m.fd")
        template = code.with_name("OVMF_VARS.4m.fd")
        if not code.is_file() or not template.is_file():
            parser.error("Install edk2-ovmf (expected /usr/share/edk2/x64/*.4m.fd)")
        # Fresh firmware state also tests EFI/BOOT/BOOTX64.EFI after installation.
        shutil.copyfile(template, state / "vars.fd")
        command += ["-drive", f"if=pflash,format=raw,readonly=on,file={code}",
                    "-drive", f"if=pflash,format=raw,file={state}/vars.fd"]
    if not args.boot:
        # Freeze this run's scripts. New runs pick up edits without rebuilding
        # the ISO, but an in-progress install cannot see half-written edits.
        source = state / (f"source-resume-{time.time_ns()}" if args.resume else "source")
        shutil.copytree(ROOT / "airootfs/root", source / "airootfs/root")
        (source / "tests").mkdir()
        for script in (ROOT / "tests").glob("guest-*.sh"):
            shutil.copyfile(script, source / "tests" / script.name)
        (state / "source.sha256").write_text("".join(
            f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(source)}\n"
            for path in sorted(source.rglob("*")) if path.is_file()
        ))
        iso = args.iso.resolve() if args.iso else latest_iso(ROOT / "out")
        if iso is None or not iso.is_file():
            parser.error("Build an ISO or supply its path")
        if args.embedded:
            with iso.open("rb") as image:
                digest = hashlib.file_digest(image, "sha256").hexdigest()
            (state / "image.sha256").write_text(f"{digest}  {iso}\n")
        command += ["-cdrom", str(iso), "-boot", "once=d"]
        if not args.firmware_boot:
            uuid = run("blkid", "-p", "-s", "UUID", "-o", "value", str(iso))
            payload = state
            names = ("vmlinuz-linux", "initramfs-linux.img")
            reuse_payload = args.resume and f"archisosearchuuid={uuid}" in previous_command and all((state / name).is_file() for name in names)
            if not reuse_payload:
                if args.resume:
                    payload = state / f"payload-resume-{time.time_ns()}"
                    payload.mkdir()
                for name in names:
                    run("xorriso", "-osirrox", "on", "-indev", str(iso), "-extract",
                        f"/hyprflux/boot/x86_64/{name}", str(payload / name))
            command += ["-kernel", str(payload / "vmlinuz-linux"), "-initrd", str(payload / "initramfs-linux.img"),
                        "-append", f"archisobasedir=hyprflux archisosearchuuid={uuid} cow_spacesize=2G plymouth.enable=0 console=ttyS0,115200n8 hyprflux.test=1 hyprflux.testdisk={devices[args.disk_bus]} hyprflux.testswap={args.swap} hyprflux.profile={args.profile} systemd.mask=getty@tty1.service"]
        command += ["-fsdev", f"local,id=src,path={source},security_model=none,readonly=on",
                    "-device", "virtio-9p-pci,fsdev=src,mount_tag=hyprflux"]
        if args.package_cache:
            command += ["-fsdev", f"local,id=pkgcache,path={args.package_cache},security_model=none,readonly=on",
                        "-device", "virtio-9p-pci,fsdev=pkgcache,mount_tag=hyprflux-pkgcache"]
            (state / "package-cache.txt").write_text(f"Read-only package seed: {args.package_cache}\nNormal guest pacman signature validation remains enabled.\n")
    (state / "command.txt").write_text("\n".join(command) + "\n")
    print(f"State and logs: {state}", flush=True)
    with (state / "qemu.log").open("wb") as err, (state / "serial.log").open("wb") as log:
        process = subprocess.Popen(command, stdout=err, stderr=err)
        connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        completed = False
        try:
            deadline = time.monotonic() + args.timeout
            while not serial.exists():
                if process.poll() is not None:
                    raise RuntimeError((state / "qemu.log").read_text())
                if time.monotonic() > deadline:
                    raise TimeoutError("No QEMU serial socket")
                time.sleep(0.1)
            connection.connect(str(serial))
            connection.settimeout(1)
            buffer = b""
            interrupted = False
            started = False
            diagnosing = False
            firmware_stage = 0
            while time.monotonic() < deadline:
                if shutil.disk_usage(base).free < 2 * 1024 ** 3:
                    raise RuntimeError("Host has less than 2 GiB free; stopping the VM before the host filesystem fills")
                try:
                    data = connection.recv(65536)
                except socket.timeout:
                    if process.poll() is not None:
                        break
                    continue
                if not data:
                    break
                log.write(data)
                log.flush()
                buffer = (buffer + data)[-100000:]
                plain = re.sub(rb"\x1b\[[0-?]*[ -/]*[@-~]", b"", buffer)
                if args.firmware_boot and not args.bios:
                    if firmware_stage == 0 and b"Serial console" in plain:
                        # Select the third, serial-console entry from the real
                        # menu. Re-entering `normal` would reload grub.cfg and
                        # reset its default/timeout variables.
                        send_serial(connection, b"\x1b[B\x1b[B\r")
                        firmware_stage = 2
                elif args.firmware_boot and args.bios:
                    if firmware_stage == 0 and b"HyprFlux Installer" in plain:
                        send_serial(connection, b"\x1b")
                        firmware_stage = 1
                    elif firmware_stage == 1 and b"boot:" in plain:
                        send_serial(connection, b"hyprflux-serial\n")
                        firmware_stage = 2
                if not diagnosing and b"[rootfs ~]#" in plain:
                    send_serial(connection, b"echo HYPRFLUX_DIAG_BEGIN; cat /proc/cmdline; ls /dev/sr* /dev/vd* /dev/disk/by-uuid/*; blkid; dmesg | tail -40; echo HYPRFLUX_DIAG_END\n")
                    diagnosing = True
                if diagnosing and re.search(rb"[\r\n]HYPRFLUX_DIAG_END[\r\n]", plain):
                    raise RuntimeError(f"Live initramfs failed to find the ISO; diagnostics saved in {state}/serial.log")
                if not args.boot and not interrupted and (b"Welcome to the HyprFlux" in plain or b"Continue with installation" in plain):
                    connection.sendall(b"\x03")
                    interrupted = True
                if not args.boot and not started and shell_ready(plain):
                    mount = "mkdir -p /run/hyprflux-source; mount -t 9p -o trans=virtio,version=9p2000.L,ro hyprflux /run/hyprflux-source"
                    task = "bash /run/hyprflux-source/tests/guest-install.sh" if args.install else "bash /run/hyprflux-source/tests/guest-smoke.sh"
                    if args.embedded:
                        task = "HYPRFLUX_TEST_EMBEDDED=1 " + task
                    if args.package_cache:
                        task = "HYPRFLUX_TEST_PACKAGE_CACHE=1 " + task
                    if args.manual_layout:
                        task = "HYPRFLUX_TEST_MANUAL_LAYOUT=1 " + task
                    if args.resume:
                        task += " --resume"
                    command_line = mount + " && " + task
                    command_line += '; test_code=$?; [ "$test_code" -eq 0 ] || printf "\\nHYPRFLUX_TEST_FAILED guest-command-exit=%s\\n" "$test_code"\n'
                    send_serial(connection, command_line.encode())
                    started = True
                    buffer = b""
                marker = b"HYPRFLUX_TEST_BOOT_PASS" if args.boot else (b"HYPRFLUX_TEST_INSTALL_PASS" if args.install else b"HYPRFLUX_TEST_SMOKE_PASS")
                if marker_seen(plain, marker):
                    if args.boot:
                        image = guest_screenshot((state / "serial.log").read_bytes())
                        if image is not None:
                            (state / "desktop.png").write_bytes(image)
                        else:
                            request(qmp, "screendump", {"filename": str(state / "desktop.png"), "format": "png"})
                    if args.install:
                        # Require the real reboot path to finish before making
                        # this disk eligible for installed-system boot tests.
                        result_code = process.wait(timeout=30)
                        if result_code != 0:
                            raise RuntimeError(f"QEMU installation exit: {result_code}")
                        (state / "installed.ok").touch()
                    print(marker.decode(), flush=True)
                    completed = True
                    return
                if marker_seen(plain, b"HYPRFLUX_TEST_FAILED", details=True) or marker_seen(plain, b"HYPRFLUX_TEST_BOOT_FAILED", details=True):
                    raise RuntimeError("Guest test failed; inspect serial.log and guest install logs")
            raise TimeoutError("Guest did not report success; inspect serial.log and qemu.log")
        finally:
            connection.close()
            if process.poll() is None:
                if not completed:
                    try:
                        request(qmp, "screendump", {"filename": str(state / "failure.png"), "format": "png"})
                    except (OSError, RuntimeError) as error:
                        (state / "screenshot-error.log").write_text(str(error))
                try:
                    request(qmp, "quit")
                    result_code = process.wait(timeout=10)
                    if result_code != 0:
                        raise RuntimeError(f"QEMU shutdown failed: exit {result_code}")
                except (OSError, subprocess.TimeoutExpired):
                    process.kill()
                    process.wait()
            sockets.cleanup()


if __name__ == "__main__":
    main()
