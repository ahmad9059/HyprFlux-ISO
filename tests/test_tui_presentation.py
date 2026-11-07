"""Omarchy-style rendering contracts without any installer/disk operations."""
from pathlib import Path
import tempfile
import unittest

from test_installer import ROOT, bash


class PresentationTests(unittest.TestCase):
    def test_hyprflux_palette_is_preserved(self):
        source = (ROOT / 'airootfs/root/lib/tui.sh').read_text()
        for accent in ('prompt', 'cursor', 'selected', 'indicator', 'match'):
            self.assertIn(f'--{accent}.foreground="212"', source)
            self.assertNotIn(f'--{accent}.foreground="2"', source)
        self.assertNotIn('--selected.background="2"', source)
        self.assertIn('readonly STATUS_COLOR=$\'\\033[1;33m\'', source)
        self.assertIn('readonly GREEN=$\'\\033[0;32m\'', source)

    def test_adaptive_banner_and_menu_height(self):
        # Only replace terminal lookup for this headless test; real PTYs are
        # exercised separately with Gum in the builder.
        source = (ROOT / 'airootfs/root/lib/tui.sh').read_text().replace('</dev/tty', '</dev/null')
        with tempfile.TemporaryDirectory() as directory:
            library = Path(directory) / 'tui.sh'
            library.write_text(source)
            result = bash(f'''set -euo pipefail
                source {str(library)!r}
                TEST_SIZE='24 80'
                stty() {{ printf '%s\\n' "$TEST_SIZE"; }}
                show_banner
                [[ $LOGO_COLOR == $'\\033[1;36m' && $BANNER_HEIGHT == 8 ]]
                [[ $_BANNER_CACHE != *ahmad9059* ]]
                set_status 'Application profile'
                tui_print 'Desktop and Full'
                [[ $(_available_height 20) == 10 ]]
                TEST_SIZE='12 40'
                show_banner
                [[ $BANNER_HEIGHT == 3 && $_BANNER_CACHE == *HyprFlux* ]]
                [[ $(_available_height 20) == 6 ]]
            ''')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_progress_keeps_header_static_sanitizes_display_and_retains_logs(self):
        with tempfile.TemporaryDirectory() as directory:
            library = Path(directory) / 'tui.sh'
            library.write_text((ROOT / 'airootfs/root/lib/tui.sh').read_text().replace('</dev/tty', '</dev/null'))
            result = bash(f'''set -euo pipefail
                source {str(library)!r}
                INSTALL_LOG_DIR={directory!r}
                stty() {{ printf '24 80\\n'; }}
                start_progress 'Installing HyprFlux'
                monitor=$_PROGRESS_PID
                printf '\\033[31mPackage ready\\033[0m\\007\\n' >> "$PROGRESS_LOG"
                sleep .35
                stop_progress
                ! kill -0 "$monitor" 2>/dev/null
            ''')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(result.stdout.count('\x1b[H\x1b[2J'), 1)
            self.assertIn('→ Package ready', result.stdout)
            self.assertNotIn('\x07', result.stdout)
            self.assertIn(b'\x07', next(Path(directory).glob('stage.*.log')).read_bytes())

    def test_progress_command_failure_is_not_hidden(self):
        with tempfile.TemporaryDirectory() as directory:
            result = bash(f'''
                source airootfs/root/lib/tui.sh
                INSTALL_LOG_DIR={directory!r}
                run_with_progress failure bash -c 'echo diagnostic; exit 7'
                status=$?
                [[ $status == 7 ]] || exit 99
                grep -q diagnostic {directory!r}/stage.*.log
            ''')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_console_font_has_ascii_spinner_fallback(self):
        source = (ROOT / 'airootfs/root/lib/tui.sh').read_text()
        function = '_spinner_frames() {' + source.split('_spinner_frames() {', 1)[1].split('\n}', 1)[0] + '\n}'
        function = function.replace('</dev/tty', '</dev/null')
        result = bash(function + '''
            TUI_SPINNER_FRAMES=('⠋' '⠙')
            tty() { printf /dev/tty1; }
            mapfile -t frames < <(_spinner_frames)
            [[ ${#frames[@]} == 4 && ${frames[0]} == '|' ]] || exit 1
            tty() { printf /dev/pts/2; }
            mapfile -t frames < <(_spinner_frames)
            [[ ${frames[0]} == '⠋' ]]
        ''')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_progress_redraws_header_only_when_terminal_resizes(self):
        with tempfile.TemporaryDirectory() as directory:
            library = Path(directory) / 'tui.sh'
            library.write_text((ROOT / 'airootfs/root/lib/tui.sh').read_text().replace('</dev/tty', '</dev/null'))
            sizefile = Path(directory) / 'size'
            sizefile.write_text('24 80\n')
            result = bash(f'''set -euo pipefail
                source {str(library)!r}
                INSTALL_LOG_DIR={directory!r}
                stty() {{ cat {str(sizefile)!r}; }}
                start_progress 'Resize preview'
                sleep .2
                printf '16 60\\n' > {str(sizefile)!r}.new
                mv {str(sizefile)!r}.new {str(sizefile)!r}
                sleep .3
                stop_progress
            ''')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(result.stdout.count('\x1b[H\x1b[2J'), 2)
            self.assertIn('HyprFlux', result.stdout)
