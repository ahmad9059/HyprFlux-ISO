"""Focused cancellation, connectivity and base-download regression checks."""
from pathlib import Path
import tempfile
import unittest

from test_installer import ROOT, bash


class PromptDownloadTests(unittest.TestCase):
    def check_bash(self, code):
        result = bash('set -euo pipefail\n' + code)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def test_text_input_distinguishes_cancel_from_submitted_blank(self):
        source = (ROOT / 'airootfs/root/lib/tui.sh').read_text()
        function = 'tui_input() {' + source.split('tui_input() {', 1)[1].split('\n}', 1)[0] + '\n}'
        # Redirect only terminal control bytes; gum output/status are real shell
        # values. No physical terminal or production prompt is modified.
        function = function.replace('/dev/tty', '/dev/null')
        self.check_bash(function + '''
            ANSI_SHOW_CURSOR= ANSI_HIDE_CURSOR= PAD= LOGO_DISPLAY_WIDTH=60
            gum() { return 130; }
            value=unexpected
            if value=$(tui_input Hostname hyprflux); then exit 10; fi
            [[ -z "$value" ]]
            gum() { return 0; }
            [[ $(tui_input Hostname hyprflux) == hyprflux ]]
            gum() { printf custom-name; }
            [[ $(tui_input Hostname hyprflux) == custom-name ]]
        ''')

    def test_locale_defaults_to_english_without_a_selection_step(self):
        installer = (ROOT / 'airootfs/root/hyprflux-install.sh').read_text()
        self.assertNotIn('step_locale', installer)
        self.assertNotIn('Locale Configuration', installer)
        self.check_bash('''
            source airootfs/root/hyprflux-install.sh
            [[ "$INSTALL_LOCALE" == en_US.UTF-8 ]]
        ''')

    def test_guest_locale_assertion_accepts_glibc_whitespace_not_comments(self):
        fixture = (ROOT / 'tests/guest-install.sh').read_text()
        assertion = next(line.strip() for line in fixture.splitlines()
                         if 'grep -Eq' in line and 'locale.gen' in line)
        with tempfile.TemporaryDirectory() as temp:
            etc = Path(temp) / 'etc'
            etc.mkdir()
            for content, accepted in [('en_US.UTF-8 UTF-8  \n', True),
                                      ('en_US.UTF-8\tUTF-8\n', True),
                                      ('#en_US.UTF-8 UTF-8\n', False)]:
                (etc / 'locale.gen').write_text(content)
                result = bash(f'MOUNT_POINT={temp!r}\n' + assertion)
                self.assertEqual(result.returncode == 0, accepted, result.stderr)

    def test_both_profile_descriptions_and_menu_choices_are_preserved(self):
        result = self.check_bash('''
            source airootfs/root/hyprflux-install.sh
            show_banner() { :; }
            set_status() { :; }
            tui_print() { printf '%s\\n' "$*"; }
            tui_menu() { printf 'Desktop (recommended; smaller and faster)'; }
            step_profile
            [[ $INSTALL_PROFILE == desktop ]]
            tui_menu() { printf 'Full application bundle'; }
            step_profile
            [[ $INSTALL_PROFILE == full ]]
        ''')
        self.assertIn('Smaller and faster to install.', result.stdout)
        self.assertIn('Full application bundle: Same desktop, plus additional editors,', result.stdout)
        self.assertIn('chat, AI, and media applications. More downloads and longer', result.stdout)

    def test_required_prompt_cancellation_exits_cleanly_before_next_step(self):
        for step in ('step_timezone', 'step_keyboard', 'step_hostname', 'step_user'):
            with self.subTest(step=step):
                result = self.check_bash('''
                    source airootfs/root/hyprflux-install.sh
                    show_banner() { :; }
                    set_status() { :; }
                    tui_print() { :; }
                    log_warn() { printf 'CANCELLED\\n'; }
                    curl() { return 1; }
                    timedatectl() { printf UTC; }
                    list_utf8_locales() { printf en_US.UTF-8; }
                    tui_search() { cat >/dev/null; return 130; }
                    tui_menu() { return 130; }
                    tui_input() { return 130; }
                ''' + step + '\nprintf "WRONGLY_CONTINUED\\n"')
                self.assertIn('CANCELLED', result.stdout)
                self.assertNotIn('WRONGLY_CONTINUED', result.stdout)

    def test_password_cancellation_is_not_an_install_failure(self):
        result = self.check_bash('''
            source airootfs/root/hyprflux-install.sh
            show_banner() { :; }
            set_status() { :; }
            log_warn() { printf 'CANCELLED\\n'; }
            tui_input() { printf fluxfixture; }
            validate_username() { return 0; }
            tui_password() { return 130; }
            step_user
            printf 'WRONGLY_CONTINUED\\n'
        ''')
        self.assertIn('CANCELLED', result.stdout)
        self.assertNotIn('WRONGLY_CONTINUED', result.stdout)

    def test_disk_menu_reselection_does_not_accumulate_stack_frames(self):
        self.check_bash('''
            source airootfs/root/hyprflux-install.sh
            show_banner() { :; }
            set_status() { :; }
            tui_menu() { printf 'Automatic (wipe entire disk)'; }
            rounds=0
            step_disk_auto() {
                (( ${#FUNCNAME[@]} < 10 ))
                rounds=$((rounds + 1))
                INSTALL_RESELECT_DISK=true
                if (( rounds == 200 )); then INSTALL_RESELECT_DISK=false; fi
            }
            step_disk
            [[ $rounds == 200 ]]
        ''')

    def test_refusing_wipe_or_cancelling_input_cannot_reach_partitioning(self):
        for response in ('no', 'cancel'):
            with self.subTest(response=response):
                self.check_bash('''
                    source airootfs/root/hyprflux-install.sh
                    show_banner() { :; }
                    set_status() { :; }
                    disk_is_installable() { return 0; }
                    lsblk() { printf '/dev/fixture 40G Fixture\\n'; }
                    tui_menu() { printf '/dev/fixture (40G) Fixture'; }
                    start_progress() { exit 41; }
                    sgdisk() { exit 42; }
                    wipefs() { exit 43; }
                    tui_input() { ''' + ('return 130;' if response == 'cancel' else 'printf no;') + ''' }
                    step_disk_auto
                    [[ $INSTALL_RESELECT_DISK == true ]]
                ''')

    def test_parallel_download_configuration_is_atomic_and_idempotent(self):
        with tempfile.TemporaryDirectory() as temp:
            config = Path(temp) / 'pacman.conf'
            original = '[options]\nSigLevel = Required DatabaseOptional\n#ParallelDownloads = 5\nParallelDownloads = 1\n[core]\nInclude = /etc/pacman.d/mirrorlist\n'
            config.write_text(original)
            self.check_bash(f'''source airootfs/root/lib/common.sh
                configure_parallel_downloads {str(config)!r}
                configure_parallel_downloads {str(config)!r}
            ''')
            text = config.read_text()
            self.assertEqual(text.count('ParallelDownloads'), 1)
            self.assertIn('SigLevel = Required DatabaseOptional', text)
            self.assertIn('ParallelDownloads = 5\n[core]', text)
            self.assertIn('Include = /etc/pacman.d/mirrorlist', text)
            config.write_text('[core]\nServer = https://example.invalid\n')
            before = config.read_bytes()
            self.check_bash(f'''source airootfs/root/lib/common.sh
                if configure_parallel_downloads {str(config)!r}; then exit 20; fi
            ''')
            self.assertEqual(config.read_bytes(), before)
            self.assertEqual(list(Path(temp).iterdir()), [config])

    def test_live_download_setting_precedes_pacstrap(self):
        source = (ROOT / 'airootfs/root/hyprflux-install.sh').read_text()
        self.assertLess(source.index('configure_parallel_downloads /etc/pacman.conf'),
                        source.index('pacstrap -K'))

    def test_network_probe_falls_back_without_disabling_tls_or_timeouts(self):
        self.check_bash('''
            source airootfs/root/lib/common.sh
            calls=0
            curl() {
                calls=$((calls + 1))
                [[ " $* " == *' --max-time 8 '* ]] || return 99
                [[ " $* " != *' --insecure '* ]] || return 99
                if [[ "$*" == *https://archlinux.org/* ]]; then return 22; fi
                [[ "$*" == *https://geo.mirror.pkgbuild.com/core/os/x86_64/core.db* ]]
            }
            check_internet
            [[ $calls == 2 ]]
            curl() { return 6; }
            if check_internet; then exit 21; fi
        ''')


if __name__ == '__main__':
    unittest.main()
