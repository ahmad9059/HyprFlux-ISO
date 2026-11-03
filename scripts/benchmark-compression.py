#!/usr/bin/env python3
"""Measure candidate compression on build artifacts; never change build defaults."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time


def timed(command, output=None, cwd=None):
    started = time.monotonic()
    subprocess.run(command, stdout=output or subprocess.DEVNULL,
                   stderr=subprocess.PIPE, check=True, cwd=cwd)
    return round(time.monotonic() - started, 3)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rootfs', type=Path, required=True, help='Completed, unmounted mkarchiso airootfs')
    parser.add_argument('--initramfs', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True, help='New directory for durable JSON results')
    args = parser.parse_args()
    root = args.rootfs.resolve()
    if not root.is_dir() or not (root / 'usr').is_dir():
        parser.error('rootfs must be a completed live filesystem tree')
    if args.output.resolve().is_relative_to(root):
        parser.error('Benchmark output must be outside the source filesystem tree')
    if not args.output.parent.is_dir():
        parser.error('Benchmark output parent directory must already exist')
    mounts = subprocess.check_output(['findmnt', '-rn', '-o', 'TARGET'], text=True).splitlines()
    if any(path == str(root) or path.startswith(str(root) + '/') for path in mounts):
        parser.error('Unmount the build filesystem before benchmarking')
    # Conservative disk guard. Scratch images/extraction are deleted when done.
    if shutil.disk_usage(args.output.parent).free < 12 * 2**30:
        parser.error('Need 12 GiB free for benchmark scratch; no files were removed')
    args.output.mkdir(parents=True, exist_ok=False)
    results = dict(note='Artifact compression/decompression only; not USB boot or installed-desktop acceptance',
                   threads=2, rootfs={}, initramfs={})
    with tempfile.TemporaryDirectory(prefix='scratch-', dir=args.output) as temporary:
        scratch = Path(temporary)
        for mode, options in (
            ('xz', ['-Xbcj', 'x86', '-Xdict-size', '1M']),
            ('zstd', ['-Xcompression-level', '15']),
        ):
            image = scratch / f'rootfs-{mode}.sfs'
            compressed = timed(['mksquashfs', str(root), str(image), '-noappend', '-processors', '2',
                                '-comp', mode, '-b', '1M', *options])
            extracted = scratch / f'extracted-{mode}'
            decompressed = timed(['unsquashfs', '-processors', '2', '-d', str(extracted), str(image)])
            results['rootfs'][mode] = dict(bytes=image.stat().st_size,
                compression_seconds=compressed, extraction_seconds=decompressed)
            shutil.rmtree(extracted)
            image.unlink()
            print(json.dumps(dict(rootfs=mode, **results['rootfs'][mode])), flush=True)
        # Standard Arch initramfs: uncompressed early CPIO followed by XZ/Zstd
        # main CPIO. Validate a main archive before measuring it in isolation.
        payload = args.initramfs.read_bytes()
        raw = None
        for magic, decoder in ((b'\xfd7zXZ\x00', ['xz', '-dc', '--single-stream']),
                               (b'\x28\xb5\x2f\xfd', ['zstd', '-qdc'])):
            offset = payload.find(magic)
            if offset < 0:
                continue
            decoded = subprocess.run(decoder, input=payload[offset:], capture_output=True)
            if decoded.returncode == 0 and decoded.stdout.startswith((b'070701', b'070702')):
                raw = decoded.stdout
                break
        if raw is None:
            raise ValueError('Unsupported main initramfs archive; no compression conclusion recorded')
        source = scratch / 'main.cpio'
        source.write_bytes(raw)
        del payload, raw
        for mode, compressor, decompressor in (
            ('xz-9e', ['xz', '-T2', '-9e', '-c'], ['xz', '-dc']),
            ('zstd-3', ['zstd', '-T2', '-3', '-qc'], ['zstd', '-qdc']),
        ):
            destination = scratch / mode
            with destination.open('wb') as stream:
                compressed = timed([*compressor, str(source)], output=stream)
            decompressed = timed([*decompressor, str(destination)])
            results['initramfs'][mode] = dict(bytes=destination.stat().st_size,
                compression_seconds=compressed, decompression_seconds=decompressed)
            print(json.dumps(dict(initramfs=mode, **results['initramfs'][mode])), flush=True)
    (args.output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')


if __name__ == '__main__':
    main()
