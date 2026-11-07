"""Guards for acceptance diagnostics added during the production KVM run."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from test_installer import ROOT, bash


class ProductionChecksTests(unittest.TestCase):
    def test_installer_policy_validation_fails_closed_without_repair(self):
        source = (ROOT / 'airootfs/root/lib/hyprflux-chroot-wrapper.sh').read_text()
        function = 'validate_dbus_policies() {' + source.split('validate_dbus_policies() {', 1)[1].split('\n}', 1)[0] + '\n}'
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp) / 'usr/share/dbus-1/system.d'
            directory.mkdir(parents=True)
            policy = directory / 'interrupted.conf'
            policy.write_text('')
            result = bash(function + f'\nvalidate_dbus_policies {temp!r}')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('interrupted.conf', result.stderr)
            self.assertEqual(policy.read_bytes(), b'')
            policy.write_text('<busconfig/>')
            result = bash(function + f'\nvalidate_dbus_policies {temp!r}')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('validate_dbus_policies || critical_failed=1', source)

    def test_installed_sudo_must_authenticate_and_temporary_grants_are_rejected(self):
        guest = (ROOT / 'tests/guest-verify.sh').read_text()
        self.assertIn('etc/sudoers.d/99-hyprflux-temp', guest)
        self.assertIn('runuser -u fluxcheck -- sudo -n true', guest)
        self.assertLess(guest.index('HYPRFLUX_SUDO_AUTHENTICATION_REQUIRED_PASS'),
                        guest.index('HYPRFLUX_TEST_BOOT_PASS'))

    def test_system_bus_policy_check_rejects_empty_and_preserves_file(self):
        source = (ROOT / 'tests/guest-verify.sh').read_text()
        program = source.split("python - <<'DBUS_POLICIES'\n", 1)[1].split('\nDBUS_POLICIES', 1)[0]
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            program = program.replace('/usr/share/dbus-1/system.d', temp).replace('/etc/dbus-1/system.d', temp + '/etc')
            policy = directory / 'test.conf'
            policy.write_text('<busconfig/>')
            good = subprocess.run([sys.executable, '-c', program], text=True, capture_output=True)
            self.assertEqual(good.returncode, 0, good.stdout + good.stderr)
            policy.write_text('')
            bad = subprocess.run([sys.executable, '-c', program], text=True, capture_output=True)
            self.assertNotEqual(bad.returncode, 0)
            self.assertIn('test.conf', bad.stderr)
            self.assertTrue(policy.exists())
            self.assertEqual(policy.read_bytes(), b'')

    def test_virtual_audio_is_explicit_and_not_hardware_certification(self):
        driver = (ROOT / 'tests/qemu-smoke.py').read_text()
        self.assertIn('"--virtual-audio"', driver)
        self.assertIn('none,id=testaudio', driver)
        self.assertIn('hda-duplex,audiodev=testaudio', driver)
        self.assertIn('args.virtual_audio = metadata.get("virtual_audio", False)', driver)
        guest = (ROOT / 'tests/guest-install.sh').read_text()
        self.assertIn('hyprflux.virtualaudio=1', guest)
        checks = (ROOT / 'tests/guest-desktop-checks.sh').read_text()
        self.assertIn('hyprflux-test-virtual-audio', checks)
        self.assertIn('pw-dump', checks)
        self.assertIn('pw-play', checks)
        self.assertIn('HYPRFLUX_VIRTUAL_AUDIO_STREAM_PASS', checks)
