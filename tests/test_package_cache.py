"""Root-free package-cache and hardware-inventory tests; no network required."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def module(filename):
    spec = importlib.util.spec_from_file_location(filename, ROOT / 'airootfs/root/lib' / filename)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class PackageCacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'source'
        self.source.mkdir()
        self.cache = module('package-cache.py')
        self.name = 'linux-1.0-1-x86_64.pkg.tar.zst'
        (self.source / self.name).write_bytes(b'fixture package')
        (self.source / (self.name + '.sig')).write_bytes(b'fixture signature')
        self.staged = self.root / 'staged'
        self.target = self.root / 'target'

    def stage(self):
        self.cache.stage(self.source, self.staged, 1024)

    def test_stage_filters_partial_unsigned_and_symlink_files(self):
        (self.source / 'bad.pkg.tar.zst.part').write_bytes(b'partial')
        (self.source / 'unsigned.pkg.tar.zst').write_bytes(b'unsigned')
        (self.source / 'link.pkg.tar.zst').symlink_to(self.source / self.name)
        (self.source / 'link.pkg.tar.zst.sig').write_bytes(b'sig')
        self.stage()
        self.assertEqual(set(p.name for p in self.staged.iterdir()),
                         {self.name, self.name + '.sig', 'manifest.json'})

    def test_seed_preserves_existing_downloads_and_source(self):
        self.stage()
        original = (self.staged / self.name).read_bytes()
        self.cache.seed(self.staged, self.target, 0)
        self.assertEqual((self.target / self.name).read_bytes(), original)
        (self.target / self.name).write_bytes(b'existing download')
        self.cache.seed(self.staged, self.target, 0)
        self.assertEqual((self.target / self.name).read_bytes(), b'existing download')
        self.assertEqual((self.staged / self.name).read_bytes(), original)

    def test_corrupt_cache_rejected_before_copying(self):
        self.stage()
        (self.staged / self.name).write_bytes(b'corrupt')
        with self.assertRaises(ValueError):
            self.cache.seed(self.staged, self.target, 0)
        self.assertFalse(self.target.exists())

    def test_manifest_path_traversal_rejected(self):
        self.stage()
        (self.staged / 'manifest.json').write_text(json.dumps(dict(files=[
            dict(name='../escape.pkg.tar.zst', size=0, sha256='x')])))
        with self.assertRaises(ValueError):
            self.cache.seed(self.staged, self.target, 0)
        self.assertFalse(self.target.exists())

    def test_low_disk_reserve_skips_seed(self):
        self.stage()
        self.cache.seed(self.staged, self.target, 2**100)
        self.assertEqual(list(self.target.iterdir()), [])

    def test_limit_and_no_signed_pairs_fail_explicitly(self):
        with self.assertRaises(ValueError):
            self.cache.stage(self.source, self.staged, 1)

    def test_destination_symlink_is_never_overwritten(self):
        self.stage()
        self.target.mkdir()
        sentinel = self.root / 'sentinel'
        sentinel.write_bytes(b'keep')
        (self.target / self.name).symlink_to(sentinel)
        self.cache.seed(self.staged, self.target, 0)
        self.assertEqual(sentinel.read_bytes(), b'keep')

    def test_absent_cache_is_online_noop(self):
        self.cache.seed(self.root / 'absent', self.target, 0)
        self.assertFalse(self.target.exists())

    def test_build_preserves_previous_images_and_uses_staged_profile(self):
        script = (ROOT / 'build.sh').read_text()
        self.assertNotIn('rm -rf "${WORK_DIR}" "${OUT_DIR}"', script)
        self.assertIn('out/build-', script)
        self.assertIn('"${PROFILE_DIR}"', script)
        self.assertIn('HYPRFLUX_PACKAGE_CACHE', script)
        self.assertLess(script.index('flock -n 9'), script.index('rm -rf "${WORK_DIR}"'))

    def test_inventory_does_not_force_resolution_or_drm_card(self):
        hardware = module('hardware-report.py')
        sysroot = self.root / 'sys'
        device = sysroot / 'bus/pci/devices/0000:01:00.0'
        device.mkdir(parents=True)
        (device / 'class').write_text('0x030000')
        (device / 'vendor').write_text('0x10de')
        (device / 'device').write_text('0x1234')
        connector = sysroot / 'class/drm/card1-eDP-1'
        connector.mkdir(parents=True)
        (connector / 'status').write_text('connected')
        (connector / 'modes').write_text('2560x1600\n1920x1200\n')
        report = hardware.inventory(sysroot)
        self.assertEqual(report['connectors'][0]['modes'][0], '2560x1600')
        self.assertIn('No live kernel driver', report['warnings'][0])
        wrapper = (ROOT / 'airootfs/root/lib/hyprflux-chroot-wrapper.sh').read_text()
        self.assertIn('mode = "preferred"', wrapper)
        self.assertIn('monitor=,preferred,auto,1', wrapper)


if __name__ == '__main__':
    unittest.main()
