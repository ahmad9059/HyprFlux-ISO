#!/usr/bin/env python3
"""Stage or seed an optional package cache. Never install packages directly."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

ARCHIVE = re.compile(r"[A-Za-z0-9@_+.:~-]+\.pkg\.tar\.(?:zst|xz|gz)")
PRIORITY = ('linux', 'linux-firmware', 'mkinitcpio', 'glibc', 'systemd', 'pacman',
            'archlinux-keyring', 'grub', 'networkmanager', 'mesa', 'hyprland',
            'waybar', 'pipewire', 'wireplumber', 'sddm', 'firefox', 'chromium')


def identity(name):
    if not ARCHIVE.fullmatch(name):
        raise ValueError('Invalid package archive filename')
    package, version, release, arch = name.split('.pkg.tar.')[0].rsplit('-', 3)
    if arch not in ('x86_64', 'any'):
        raise ValueError('Cache only supports x86_64/any packages')
    return package, f'{version}-{release}', arch


def repository_versions(path):
    versions = {}
    for line in path.read_text().splitlines():
        fields = line.split()
        if len(fields) >= 3:
            versions.setdefault(fields[1], fields[2])
    return versions


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def stage(source, destination, limit, versions=None):
    if not source.is_dir():
        raise ValueError('Package cache source is not a directory')
    destination.mkdir(parents=True, exist_ok=False)
    entries = []
    total = 0
    selected = {}
    skipped_stale = 0
    # Prefer a current repository version, never several cached versions of the
    # same package. Repo metadata is a build input, not installed into the ISO.
    for archive in sorted(source.iterdir()):
        signature = archive.with_name(archive.name + '.sig')
        if (not ARCHIVE.fullmatch(archive.name) or archive.is_symlink()
                or not archive.is_file() or signature.is_symlink()
                or not signature.is_file()):
            continue
        try:
            package, version, arch = identity(archive.name)
        except ValueError:
            continue
        if versions is not None and versions.get(package, '').removeprefix('0:') != version.removeprefix('0:'):
            skipped_stale += 1
            continue
        key = (package, arch)
        if key in selected:
            previous, previous_version = selected[key]
            if version != previous_version:
                if not shutil.which('vercmp'):
                    raise ValueError('vercmp or a repository version list is required to choose cached versions safely')
                comparison = int(subprocess.check_output(['vercmp', version, previous_version], text=True))
                if comparison <= 0:
                    continue
            elif archive.suffix != '.zst':
                continue
        selected[key] = (archive, version)
    rank = {name: index for index, name in enumerate(PRIORITY)}
    packages = sorted(selected.items(), key=lambda pair: (
        rank.get(pair[0][0], len(rank)) if not pair[0][0].startswith('linux-firmware-') else rank['linux-firmware'],
        pair[0]))
    for _, (archive, _) in packages:
        signature = archive.with_name(archive.name + '.sig')
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
    (destination / 'manifest.json').write_text(json.dumps(dict(
        files=entries, selection='current-repository-versions' if versions is not None else 'newest-cached-version',
        skipped_stale=skipped_stale, priority=list(PRIORITY)), indent=2) + '\n')
    print(f'Staged {len(entries) // 2} package pairs ({total} bytes).')
    print(f'Skipped {skipped_stale} stale/non-repository archives; base/Desktop packages take priority.')


def seed(source, destination, reserve, report=None):
    started = time.monotonic()
    manifest = source / 'manifest.json'
    if not manifest.is_file():
        print('No embedded package cache; using online repositories.')
        if report is not None:
            report.parent.mkdir(parents=True, exist_ok=True)
            report.write_text(json.dumps(dict(available_pairs=0, copied_pairs=0,
                copied_bytes=0, skipped_existing=0, source_absent=True)) + '\n')
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
    copied_bytes = 0
    skipped_existing = 0
    for name, path in validated.items():
        if name.endswith('.sig'):
            continue
        if name + '.sig' not in validated:
            raise ValueError(f'Package signature absent from manifest: {name}')
        pair = (path, validated[name + '.sig'])
        # Never overwrite packages/signatures downloaded by pacstrap or a retry.
        if any(os.path.lexists(destination / item.name) for item in pair):
            skipped_existing += 1
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
        copied_bytes += needed
    if report is not None:
        report.parent.mkdir(parents=True, exist_ok=True)
        report.write_text(json.dumps(dict(available_pairs=len(validated) // 2,
            copied_pairs=copied, copied_bytes=copied_bytes, skipped_existing=skipped_existing,
            elapsed_seconds=round(time.monotonic() - started, 3)), indent=2) + '\n')
    print(f'Seeded {copied} package pairs; pacman still checks versions and signatures.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('stage', 'seed'))
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--limit-mib', type=int, default=2048)
    parser.add_argument('--reserve-mib', type=int, default=2048)
    parser.add_argument('--repository-list', type=Path, help='Build host pacman -Sl output; exclude stale/unavailable versions')
    parser.add_argument('--report', type=Path, help='Write seed transfer metrics, not a claim of network bytes avoided')
    args = parser.parse_args()
    if args.limit_mib <= 0 or args.reserve_mib < 0:
        parser.error('Cache limit must be positive; reserve must be nonnegative')
    try:
        if args.action == 'stage':
            stage(args.source, args.destination, args.limit_mib * 2**20,
                  repository_versions(args.repository_list) if args.repository_list else None)
        else:
            seed(args.source, args.destination, args.reserve_mib * 2**20, args.report)
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f'Package cache: {error}\n')


if __name__ == '__main__':
    main()
