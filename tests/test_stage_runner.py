"""Real Linux subprocess/session cleanup, never host package installation."""
from pathlib import Path
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

from test_installer import ROOT, bash

RUNNER = ROOT / 'airootfs/root/lib/run-stage.py'


class StageRunnerTests(unittest.TestCase):
    def run_stage(self, command, seconds=2):
        return subprocess.run([sys.executable, str(RUNNER), '--timeout', str(seconds),
                               '--kill-after', '.1', '--', *command], capture_output=True,
                              text=True, timeout=8)

    def test_child_exit_status_is_preserved(self):
        result = self.run_stage([sys.executable, '-c', 'raise SystemExit(7)'])
        self.assertEqual(result.returncode, 7, result.stderr)

    def assert_gone(self, pid):
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)

    def test_timeout_reaps_detached_term_ignoring_grandchild(self):
        with tempfile.TemporaryDirectory() as directory:
            pidfile = Path(directory) / 'pid'
            child = f'''import os,signal,time
os.setsid()
signal.signal(signal.SIGTERM, signal.SIG_IGN)
open({str(pidfile)!r}, 'w').write(str(os.getpid()))
time.sleep(100)
'''
            parent = f'''import subprocess,sys,time
subprocess.Popen([sys.executable, '-c', {child!r}])
time.sleep(100)
'''
            result = self.run_stage([sys.executable, '-c', parent], seconds=.5)
            self.assertEqual(result.returncode, 124, result.stdout + result.stderr)
            self.assert_gone(int(pidfile.read_text()))

    def test_success_also_cleans_adopted_background_process(self):
        with tempfile.TemporaryDirectory() as directory:
            pidfile = Path(directory) / 'pid'
            child = 'import os,time; os.setsid(); time.sleep(100)'
            parent = f'''import subprocess,sys
p=subprocess.Popen([sys.executable, '-c', {child!r}])
open({str(pidfile)!r}, 'w').write(str(p.pid))
'''
            result = self.run_stage([sys.executable, '-c', parent])
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assert_gone(int(pidfile.read_text()))

    @unittest.skipUnless(os.geteuid() == 0 and shutil.which('su') and shutil.which('script'),
                         'Real su/PTY cleanup runs in the root builder container')
    def test_timeout_reaps_su_and_pty_command(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory).chmod(0o755)
            pidfile = Path(directory) / 'pid'
            pidfile.touch(mode=0o666)
            pidfile.chmod(0o666)
            child = f'''import os,signal,time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
open({str(pidfile)!r}, 'w').write(str(os.getpid()))
time.sleep(100)
'''
            command = shlex.join([sys.executable, '-c', child])
            result = self.run_stage(['su', '-', 'root', '-s', '/bin/bash', '-c',
                                     shlex.join(['script', '-qfc', command, '/dev/null'])], seconds=3)
            self.assertEqual(result.returncode, 124, result.stdout + result.stderr)
            self.assertTrue(pidfile.read_text(), result.stdout + result.stderr)
            self.assert_gone(int(pidfile.read_text()))

    def test_full_timeout_is_fatal_and_has_a_larger_finite_budget(self):
        wrapper = (ROOT / 'airootfs/root/lib/hyprflux-chroot-wrapper.sh').read_text()
        function = 'run_as_user() {' + wrapper.split('run_as_user() {', 1)[1].split('\n}', 1)[0] + '\n}'
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory) / '01-hypr-pkgs.sh'
            script.touch()
            result = bash(function + f'''
                INSTALL_PROFILE=full
                TARGET_USER=fixture TARGET_HOME={directory!r} ARCH_HYPR_DIR={directory!r}
                FAILED_COMPONENTS=()
                run_stage() {{ [[ $1 == 7200 ]] || exit 99; return 124; }}
                run_as_user {str(script)!r}
                echo WRONGLY_CONTINUED
            ''')
            self.assertEqual(result.returncode, 124, result.stdout + result.stderr)
            self.assertNotIn('WRONGLY_CONTINUED', result.stdout)


if __name__ == '__main__':
    unittest.main()
