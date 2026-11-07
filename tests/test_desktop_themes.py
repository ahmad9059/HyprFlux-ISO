"""ISO integration checks; desktop implementation tests live in HyprFlux."""
import re
import unittest

from test_installer import ROOT


class DesktopThemeTests(unittest.TestCase):
    def test_no_iso_desktop_implementation_copies(self):
        installer = (ROOT / 'airootfs/root/hyprflux-install.sh').read_text()
        wrapper = (ROOT / 'airootfs/root/lib/hyprflux-chroot-wrapper.sh').read_text()
        for name in ('fix-foot-config.py', 'kitty-launcher.sh', 'papirus-cyan.sh'):
            self.assertFalse((ROOT / 'airootfs/root/lib' / name).exists())
            self.assertNotIn(name, installer)
            self.assertNotIn(name, wrapper)
        self.assertNotIn('prepare_iso_theme_module', wrapper)
        self.assertNotIn('Target = papirus-icon-theme', installer)
        self.assertNotIn('Exec = /usr/local/libexec/hyprflux-papirus-cyan', installer)

    def test_published_shared_desktop_revision_is_pinned(self):
        installer = (ROOT / 'airootfs/root/hyprflux-install.sh').read_text()
        revision = re.search(r'^HYPRFLUX_REF="([0-9a-f]{40})"$', installer, re.M)
        self.assertIsNotNone(revision)
        self.assertEqual(revision[1], '74735688a2703a717694518b5699e79991c33a74')

    def test_iso_validates_desktop_output_without_owning_theme_setup(self):
        wrapper = (ROOT / 'airootfs/root/lib/hyprflux-chroot-wrapper.sh').read_text()
        transaction = wrapper.split('pacman_retry -Syu --needed --noconfirm hyprland', 1)[1].split('||', 1)[0]
        self.assertNotIn('qt6-5compat', transaction)
        self.assertIn('foot --check-config || exit 1', wrapper)
        audit = wrapper.split('pacman -Qk hyprland', 1)[1].split('|| critical_failed=1', 1)[0]
        self.assertIn('qt6-5compat', audit)

    def test_boot_acceptance_checks_windows_not_only_processes(self):
        checks = (ROOT / 'tests/guest-desktop-checks.sh').read_text()
        self.assertIn('foot --check-config', checks)
        self.assertIn('folder-cyan.svg', checks)
        self.assertIn('decoration:blur:enabled', checks)
        self.assertIn('c.get("mapped")', checks)
        self.assertIn('sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/HyprFlux-sddm-theme', checks)
        self.assertIn('is not installed', checks)
        installer = (ROOT / 'tests/guest-install.sh').read_text()
        verifier = (ROOT / 'tests/guest-verify.sh').read_text()
        self.assertIn('tests/guest-desktop-checks.sh', installer)
        self.assertLess(verifier.index('source /root/guest-desktop-checks.sh'),
                        verifier.index('echo HYPRFLUX_TEST_BOOT_PASS'))
