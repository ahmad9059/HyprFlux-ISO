"""Optional real-Gum tests on a disposable PTY; no installer or disks run."""
import errno
import fcntl
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import struct
import termios
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('gum'), 'Optional: install gum in the test container for real PTY checks')
class RealInputTests(unittest.TestCase):
    def prompt(self, key):
        child, terminal = pty.fork()
        if child == 0:
            os.chdir(ROOT)
            script = '''source airootfs/root/lib/tui.sh
                if value=$(tui_input Hostname hyprflux); then status=0; else status=$?; fi
                printf '\\nPROMPT_RESULT=%s;STATUS=%s\\n' "$value" "$status"
            '''
            os.execvpe('bash', ['bash', '-c', script], {**os.environ, 'TERM': 'xterm-256color'})
        output = bytearray()
        sent = False
        status = None
        fcntl.ioctl(terminal, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 120, 0, 0))
        try:
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                readable, _, _ = select.select([terminal], [], [], 0.2)
                if readable:
                    try:
                        data = os.read(terminal, 65536)
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
                    if not data:
                        break
                    output.extend(data)
                    if b'\x1b[6n' in data:
                        os.write(terminal, b'\x1b[1;1R')
                    if not sent and b'Hostname' in output:
                        os.write(terminal, key)
                        sent = True
                if not readable:
                    done, result = os.waitpid(child, os.WNOHANG)
                    if done:
                        status = result
                        break
            if status is None:
                done, result = os.waitpid(child, os.WNOHANG)
                if done:
                    status = result
            self.assertTrue(sent, repr(bytes(output)))
            self.assertIn(b'PROMPT_RESULT=', output, repr(bytes(output)))
            return bytes(output)
        finally:
            os.close(terminal)
            if status is None:
                done, _ = os.waitpid(child, os.WNOHANG)
                if not done:
                    os.kill(child, signal.SIGKILL)
                    os.waitpid(child, 0)

    def test_escape_cancels_instead_of_submitting_default(self):
        self.assertIn(b'PROMPT_RESULT=;STATUS=1', self.prompt(b'\x1b'))

    def test_enter_explicitly_accepts_default(self):
        self.assertIn(b'PROMPT_RESULT=hyprflux;STATUS=0', self.prompt(b'\r'))


if __name__ == '__main__':
    unittest.main()
