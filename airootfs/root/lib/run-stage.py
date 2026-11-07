#!/usr/bin/env python3
"""Bound an installer stage, including descendants that create new sessions."""
import argparse
import ctypes
import os
from pathlib import Path
import signal
import subprocess
import time


def descendants():
    processes = {}
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        try:
            fields = (entry / 'stat').read_text().rsplit(') ', 1)[1].split()
            processes[int(entry.name)] = (int(fields[1]), fields[19])
        except (OSError, ValueError, IndexError):
            continue
    found = {}
    parents = {os.getpid()}
    while parents:
        children = {pid for pid, (parent, _) in processes.items() if parent in parents}
        for pid in children:
            found[pid] = processes[pid][1]
        parents = children
    return found


def send(pid, started, sig):
    # A pidfd plus the /proc start time prevents signalling an unrelated process
    # if a child exits and its numeric PID is reused during cleanup.
    try:
        descriptor = os.pidfd_open(pid)
        try:
            current = Path(f'/proc/{pid}/stat').read_text().rsplit(') ', 1)[1].split()[19]
            if current == started:
                signal.pidfd_send_signal(descriptor, sig)
        finally:
            os.close(descriptor)
    except (ProcessLookupError, FileNotFoundError):
        pass


def cleanup(process, grace):
    started = time.monotonic()
    while True:
        process.poll()
        children = descendants()
        if not children:
            return True
        sig = signal.SIGTERM if time.monotonic() - started < grace else signal.SIGKILL
        for pid, birth in children.items():
            send(pid, birth, sig)
        for pid in children:
            if pid != process.pid:
                try:
                    os.waitpid(pid, os.WNOHANG)
                except ChildProcessError:
                    pass
        if time.monotonic() - started > grace + 10:
            print('[ERROR] Stage descendants could not be stopped.', flush=True)
            return False
        time.sleep(0.05)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--timeout', type=float, required=True)
    parser.add_argument('--kill-after', type=float, default=30)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command or args.timeout <= 0 or args.kill_after < 0:
        parser.error('A command, positive timeout and nonnegative grace are required')
    # Linux PR_SET_CHILD_SUBREAPER: adopt orphaned grandchildren, including su,
    # sudo and script PTY sessions. A process-group kill alone cannot catch them.
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(36, 1, 0, 0, 0) != 0:
        raise OSError(ctypes.get_errno(), 'Cannot establish stage supervision')
    interrupted = []
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, lambda number, frame: interrupted.append(number))
    process = subprocess.Popen(command, start_new_session=True)
    deadline = time.monotonic() + args.timeout
    status = None
    try:
        while process.poll() is None:
            if interrupted:
                status = 128 + interrupted[0]
                break
            if time.monotonic() >= deadline:
                print(f'[ERROR] Installer stage exceeded {args.timeout:g}s; stopping its process tree.', flush=True)
                status = 124
                break
            time.sleep(0.05)
        if status is None:
            status = process.returncode
            if status < 0:
                status = 128 - status
    finally:
        stopped = cleanup(process, args.kill_after)
    return status if stopped else 125


if __name__ == '__main__':
    raise SystemExit(main())
