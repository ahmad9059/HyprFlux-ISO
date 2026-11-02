#!/usr/bin/env python3
"""Stage or seed an optional package cache. Never install packages directly."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tempfile

ARCHIVE = re.compile(r"[A-Za-z0-9@_+.:~-]+\.pkg\.tar\.(?:zst|xz|gz)")


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def stage(source, destination, limit):
    if not source.is_dir():
        raise ValueError('Package cache source is not a directory')
    destination.mkdir(parents=True, exist_ok=False)
    entries = []
    total = 0
    # Only complete archives with detached signatures; no links or partial files.
    for archive in sorted(source.iterdir()):
        signature = archive.with_name(archive.name + '.sig')
        if (not ARCHIVE.fullmatch(archive.name) or archive.is_symlink()
                or not archive.is_file() or signature.is_symlink()
                or not signature.is_file()):
            continue
        size = archive.stat().st_size + signature.stat().st_size
        if total + size > limit:
            continue
        for item in (archive, signature):
            target = destination / item.name
            shutil.copyfile(item, target)
            target.chmod(0o644)
            entries.append(dict(name=item.name, size=target.stat().st_size,
                                sha256=digest(target)))
        total += size
    if not entries:
        raise ValueError('No signed package pairs fit the cache limit')
    (destination / 'manifest.json').write_text(json.dumps(dict(files=entries), indent=2) + '\n')
    print(f'Staged {len(entries) // 2} package pairs ({total} bytes).')


def seed(source, destination, reserve):
    manifest = source / 'manifest.json'
    if not manifest.is_file():
        print('No embedded package cache; using online repositories.')
        return
    # An integrity failure disables the optional seed, not signature validation.
    entries = json.loads(manifest.read_text())['files']
    validated = {}
    for entry in entries:
        name = entry['name']
        package = name.removesuffix('.sig')
        if not ARCHIVE.fullmatch(package) or name not in (package, package + '.sig'):
            raise ValueError('Unsafe package-cache manifest filename')
        path = source / name
        if (name in validated or path.is_symlink() or not path.is_file()
                or path.stat().st_size != entry['size'] or digest(path) != entry['sha256']):
            raise ValueError(f'Package-cache integrity failure: {name}')
        validated[name] = path
    destination.mkdir(parents=True, exist_ok=True)
    copied = 0
    for name, path in validated.items():
        if name.endswith('.sig'):
            continue
        if name + '.sig' not in validated:
            raise ValueError(f'Package signature absent from manifest: {name}')
        pair = (path, validated[name + '.sig'])
        # Never overwrite packages/signatures downloaded by pacstrap or a retry.
        if any(os.path.lexists(destination / item.name) for item in pair):
            continue
        needed = sum(item.stat().st_size for item in pair)
        if shutil.disk_usage(destination).free < needed + reserve:
            print('Package-cache seed stopped: preserving target free-space reserve.')
            break
        for item in pair:
            with tempfile.NamedTemporaryFile(dir=destination, prefix='.hyprflux-cache-') as temporary:
                with item.open('rb') as stream:
                    shutil.copyfileobj(stream, temporary)
                temporary.flush()
                os.chmod(temporary.name, 0o644)
                # Atomic, no-clobber publication on the target filesystem.
                try:
                    os.link(temporary.name, destination / item.name)
                except FileExistsError:
                    pass
        copied += 1
    print(f'Seeded {copied} package pairs; pacman still checks versions and signatures.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('stage', 'seed'))
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--limit-mib', type=int, default=2048)
    parser.add_argument('--reserve-mib', type=int, default=2048)
    args = parser.parse_args()
    if args.limit_mib <= 0 or args.reserve_mib < 0:
        parser.error('Cache limit must be positive; reserve must be nonnegative')
    try:
        if args.action == 'stage':
            stage(args.source, args.destination, args.limit_mib * 2**20)
        else:
            seed(args.source, args.destination, args.reserve_mib * 2**20)
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f'Package cache: {error}\n')


if __name__ == '__main__':
    main()
