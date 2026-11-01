#!/usr/bin/env python3
"""Check KVM/virgl without an ISO or a disk, including clean QEMU shutdown."""
import argparse
from pathlib import Path
import subprocess
import tempfile
import time

from qmp import request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--render-node", type=Path, help="Also test EGL/virgl on this render device")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="hqp-", dir="/tmp/opencode" if Path("/tmp/opencode").is_dir() else None) as temp:
        qmp = Path(temp) / "qmp.sock"
        command = ["qemu-system-x86_64", "-enable-kvm", "-cpu", "host", "-m", "128", "-S",
                   "-monitor", "none", "-serial", "none", "-no-user-config",
                   "-qmp", f"unix:{qmp},server=on,wait=off"]
        command += (["-display", f"egl-headless,rendernode={args.render_node}", "-device", "virtio-vga-gl"]
                    if args.render_node else ["-display", "none"])
        with (Path(temp) / "qemu.log").open("w+") as log:
            process = subprocess.Popen(command, stdout=log, stderr=log)
            try:
                deadline = time.monotonic() + 15
                while not qmp.exists():
                    if process.poll() is not None or time.monotonic() > deadline:
                        raise RuntimeError("QEMU failed to initialize")
                    time.sleep(0.1)
                result = request(qmp, "query-kvm")
                if not result.get("enabled"):
                    raise RuntimeError(f"KVM not enabled: {result}")
                request(qmp, "quit")
                code = process.wait(timeout=10)
                if code != 0:
                    raise RuntimeError(f"QEMU shutdown failed: exit {code}")
                print("PASS: KVM" + (" + EGL/virgl" if args.render_node else "") + "; clean QMP shutdown")
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
                log.seek(0)
                output = log.read()
                if output:
                    print(output)


if __name__ == "__main__":
    main()
