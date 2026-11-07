"""Regressions for the 2026-11-03 safety audit; never touch host block devices."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

from test_installer import ROOT, bash


class AuditFixTests(unittest.TestCase):
    def check(self, code):
        result = bash('set -euo pipefail\n' + code)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def test_disk_inspection_fails_closed_and_rejects_unmounted_holders(self):
        common = (ROOT / 'airootfs/root/lib/common.sh').read_text()
        function = 'disk_is_installable() {' + common.split('disk_is_installable() {', 1)[1].split('\n}', 1)[0] + '\n}'
        function = function.replace('[[ -b "$disk" ]] || return 1', ': # mocked block device')
        self.check(function + '''
            FAIL=none KIND=part MOUNTED=no LIVE=no
            lsblk() {
                case "$*" in
                    '-dnro TYPE /dev/fixture') echo disk ;;
                    '-dnro RO /dev/fixture') echo 0 ;;
                    '-nr -o MOUNTPOINTS /dev/fixture')
                        [[ $FAIL != mounts ]] || return 1
                        if [[ $MOUNTED == yes ]]; then echo /in-use; fi ;;
                    '-nrpo NAME,TYPE /dev/fixture')
                        [[ $FAIL != topology ]] || return 1
                        printf '/dev/fixture disk\\n/dev/fixture1 %s\\n' "$KIND" ;;
                    '-snrpo NAME /dev/live')
                        [[ $FAIL != ancestor ]] || return 1
                        echo /dev/fixture ;;
                    *) return 1 ;;
                esac
            }
            findmnt() { [[ $LIVE == yes ]] || return 1; echo /dev/live; }
            mountpoint() { [[ $LIVE == yes ]]; }
            disk_is_installable /dev/fixture
            for FAIL in mounts topology; do
                if disk_is_installable /dev/fixture; then exit 10; fi
            done
            FAIL=none
            for KIND in crypt lvm raid1 mpath; do
                if disk_is_installable /dev/fixture; then exit 11; fi
            done
            KIND=part MOUNTED=yes
            if disk_is_installable /dev/fixture; then exit 12; fi
            MOUNTED=no LIVE=yes
            if disk_is_installable /dev/fixture; then exit 13; fi
            FAIL=ancestor
            if disk_is_installable /dev/fixture; then exit 14; fi
        ''')

    def test_parent_disk_rejects_crypt_lvm_and_raid_layers(self):
        self.check('''
            source airootfs/root/lib/common.sh
            lsblk() { printf '/dev/rootpart part\\n/dev/fixture disk\\n'; }
            [[ $(parent_disk /dev/rootpart) == /dev/fixture ]]
            for kind in crypt lvm raid1; do
                lsblk() { printf '/dev/mapping %s\\n/dev/fixture disk\\n' "$kind"; }
                if parent_disk /dev/mapping; then exit 15; fi
            done
            lsblk() { return 1; }
            if parent_disk /dev/rootpart; then exit 16; fi
        ''')

    def test_branding_override_does_not_follow_vendor_symlink(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'etc').mkdir()
            (root / 'usr/lib').mkdir(parents=True)
            vendor = root / 'usr/lib/os-release'
            vendor.write_text('ID=arch\nNAME="Arch Linux"\n')
            (root / 'etc/os-release').symlink_to('../usr/lib/os-release')
            self.check(f'source airootfs/root/lib/common.sh\nwrite_os_release {temp!r}')
            self.assertEqual(vendor.read_text(), 'ID=arch\nNAME="Arch Linux"\n')
            self.assertFalse((root / 'etc/os-release').is_symlink())
            self.assertIn('ID_LIKE=arch', (root / 'etc/os-release').read_text())

    def test_successful_full_recovery_removes_old_missing_report(self):
        wrapper = (ROOT / 'airootfs/root/lib/hyprflux-chroot-wrapper.sh').read_text()
        function = 'record_missing_applications() {' + wrapper.split('record_missing_applications() {', 1)[1].split('\n}', 1)[0] + '\n}'
        with tempfile.TemporaryDirectory() as temp:
            report = Path(temp) / 'missing.txt'
            self.check(function + f'''
                record_missing_applications {str(report)!r} package-one package-two
                grep -qx package-two {str(report)!r}
                record_missing_applications {str(report)!r}
                [[ ! -e {str(report)!r} ]]
            ''')

    def test_keyring_preflight_is_bounded_before_disk_setup(self):
        source = (ROOT / 'airootfs/root/hyprflux-install.sh').read_text()
        main = source.split('main() {', 1)[1]
        self.assertLess(main.index('prepare_installation'), main.index('step_disk '))
        service = (ROOT / 'airootfs/etc/systemd/system/pacman-init.service').read_text()
        self.assertNotIn('time-sync.target', service)
        self.assertIn('TimeoutStartSec=120s', service)
        self.assertFalse(os.path.lexists(ROOT / 'airootfs/etc/systemd/system/sysinit.target.wants/systemd-time-wait-sync.service'))
        self.check('''
            source airootfs/root/hyprflux-install.sh
            confirm_install_clock() { :; }
            start_progress() { PROGRESS_LOG=/dev/null; }
            stop_progress() { :; }
            configure_parallel_downloads() { :; }
            mirrors_ready=false
            refresh_mirrors() { mirrors_ready=true; }
            timeout() {
                [[ $1 == --kill-after=5s && ( $2 == 125 || $2 == 180 ) ]] || return 99
                shift 2; "$@"
            }
            systemctl() { [[ "$*" == 'start pacman-init.service' ]]; }
            pacman() { [[ $mirrors_ready == true && "$*" == '-Sy --needed --noconfirm archlinux-keyring' ]]; }
            prepare_installation
            [[ $INSTALL_PREFLIGHT_READY == true ]]
        ''')

    def test_no_ntp_clock_acknowledgement_is_explicit_and_non_destructive(self):
        self.check('''
            source airootfs/root/hyprflux-install.sh
            timedatectl() { printf no; }
            show_banner() { :; }
            set_status() { :; }
            tui_print() { :; }
            tui_menu() { printf 'Use displayed time (only if correct)'; }
            confirm_install_clock
        ''')

    def test_empty_live_mirrors_get_https_fallback_when_ranking_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            mirrors = Path(temp) / 'mirrorlist'
            mirrors.write_text('# No active servers in fresh live environment\n')
            self.check(f'''
                source airootfs/root/lib/common.sh
                timeout() {{ [[ $1 == 45 && $2 == reflector ]]; return 124; }}
                refresh_mirrors {str(mirrors)!r}
            ''')
            self.assertEqual(mirrors.read_text(),
                             'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n')

    def test_preflight_failure_cancels_cleanly_without_wiping(self):
        result = self.check('''
            source airootfs/root/hyprflux-install.sh
            confirm_install_clock() { :; }
            start_progress() { PROGRESS_LOG=/dev/null; }
            stop_progress() { :; }
            show_banner() { :; }
            configure_parallel_downloads() { :; }
            refresh_mirrors() { :; }
            timeout() { return 124; }
            log_warn() { printf 'PREFLIGHT_CANCELLED\\n'; }
            tui_menu() { return 130; }
            sgdisk() { exit 90; }
            prepare_installation
            printf 'WRONGLY_CONTINUED\\n'
        ''')
        self.assertIn('PREFLIGHT_CANCELLED', result.stdout)
        self.assertNotIn('WRONGLY_CONTINUED', result.stdout)

    def test_required_signing_fails_without_a_key(self):
        env = {**os.environ, 'HYPRFLUX_SIGNING_KEY': '', 'HYPRFLUX_REQUIRE_SIGNATURE': '1'}
        result = subprocess.run(['bash', 'scripts/sign-iso.sh', '--check'], cwd=ROOT, env=env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)

    def test_low_space_fixture_captures_expected_exit_with_installer_err_trap(self):
        fixture = (ROOT / 'tests/guest-offline-smoke.sh').read_text()
        block = fixture[fixture.index('if (\n'):fixture.index("echo 'HYPRFLUX_LOW_SPACE_GUARD_PASS")]
        installer = (ROOT / 'airootfs/root/hyprflux-install.sh').read_text()
        manual = 'step_disk_manual() {' + installer.split('step_disk_manual() {', 1)[1].split('\n}', 1)[0] + '\n}'
        # The guest has a real serial tty and ext4 mount. Here only those two
        # resources are simulated; execute the real prompt/banner/guard code.
        manual = manual.replace('/dev/tty', '/dev/null')
        with tempfile.TemporaryDirectory() as temp:
            self.check(f'''
                source airootfs/root/hyprflux-install.sh
                scratch={temp!r}
                MOUNT_POINT="$scratch/root"
                INSTALL_BOOT_MODE=bios INSTALL_PROFILE=desktop
                mountpoint() {{ return 0; }}
                df() {{ printf 'Avail\\n67108864\\n'; }}
            ''' + manual + '\n' + block)

    def test_ci_uses_the_same_builder_and_keeps_release_draft(self):
        workflow = (ROOT / '.github/workflows/build-iso.yml').read_text()
        self.assertIn('bash build.sh', workflow)
        self.assertNotIn('mkarchiso -v -w work -o out .', workflow)
        self.assertIn('HYPRFLUX_PACKAGE_CACHE: /var/cache/pacman/pkg', workflow)
        self.assertIn('draft: true', workflow)
        self.assertIn('shell: bash', workflow)

    def test_fault_test_options_reject_invalid_runs_before_creating_disks(self):
        for options in (['--memory', '1'], ['--offline', '--install'], ['--no-ntp', '--firmware-boot'],
                        ['--network-diagnostics', '--install'], ['--network-diagnostics', '--offline']):
            result = subprocess.run(['python3', str(ROOT / 'tests/qemu-smoke.py'), *options],
                                    cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)

    def test_password_login_test_has_no_autologin_bypass(self):
        driver = (ROOT / 'tests/guest-install.sh').read_text()
        self.assertIn("grep -qw 'hyprflux.passwordlogin=1'", driver)
        self.assertIn('hyprflux-test-password-login', driver)
        runner = (ROOT / 'tests/qemu-smoke.py').read_text()
        self.assertIn('HYPRFLUX_TEST_GREETER_READY', runner)
        self.assertIn('"--text", "hyprflux-test-only\\n"', runner)

    def test_full_acceptance_audits_repository_and_extended_apps(self):
        driver = (ROOT / 'tests/guest-install.sh').read_text()
        block = driver.split('# Full-profile package acceptance', 1)[1].split('# Test-only autologin', 1)[0]
        # Discard the descriptive comment remainder, preserving the real block.
        block = block[block.index('if [[ "$INSTALL_PROFILE"'):]
        with tempfile.TemporaryDirectory() as temp:
            (Path(temp) / 'var/log/hyprflux-installer').mkdir(parents=True)
            self.check(f'''MOUNT_POINT={temp!r}; INSTALL_PROFILE=full
                arch-chroot() {{ [[ "$*" == *'pacman -Q inxi '* && "$*" == *'freedownloadmanager papirus-icon-theme' ]]; }}
            ''' + block)
            result = bash(f'''set -euo pipefail; MOUNT_POINT={temp!r}; INSTALL_PROFILE=full
                arch-chroot() {{ return 1; }}
            ''' + block)
            self.assertNotEqual(result.returncode, 0)

    @unittest.skipUnless(shutil.which('gpg'), 'GnuPG needed for real ephemeral signature test')
    def test_detached_signature_verifies_and_rejects_tampering(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            env = {**os.environ, 'GNUPGHOME': temp, 'HYPRFLUX_SIGNING_PASSPHRASE': ''}
            try:
                subprocess.run(['gpg', '--batch', '--passphrase', '', '--quick-gen-key',
                                'HyprFlux disposable test <test@example.invalid>', 'ed25519', 'sign', '1d'],
                               env=env, capture_output=True, check=True, timeout=20)
                listing = subprocess.check_output(['gpg', '--batch', '--with-colons', '--list-secret-keys'], env=env, text=True)
                fingerprint = next(line.split(':')[9] for line in listing.splitlines() if line.startswith('fpr:'))
                env['HYPRFLUX_SIGNING_KEY'] = fingerprint
                image = home / 'fixture.iso'
                image.write_bytes(b'disposable fixture, not a bootable image')
                subprocess.run(['bash', 'scripts/sign-iso.sh', str(image)], cwd=ROOT, env=env, capture_output=True, check=True, timeout=20)
                signature = Path(str(image) + '.asc')
                subprocess.run(['gpg', '--batch', '--verify', str(signature), str(image)], env=env, capture_output=True, check=True)
                image.write_bytes(b'tampered')
                result = subprocess.run(['gpg', '--batch', '--verify', str(signature), str(image)], env=env, capture_output=True)
                self.assertNotEqual(result.returncode, 0)
            finally:
                subprocess.run(['gpgconf', '--kill', 'gpg-agent'], env=env, capture_output=True)


if __name__ == '__main__':
    unittest.main()
