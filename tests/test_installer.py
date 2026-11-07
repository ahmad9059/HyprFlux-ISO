#!/usr/bin/env python3
"""Fast, root-free regression checks. No real disks or chroots are used."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def smoke_module():
    import importlib.util
    spec = importlib.util.spec_from_file_location("qemu_smoke", ROOT / "tests/qemu-smoke.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def bash(code):
    return subprocess.run(
        ["bash", "-c", code], cwd=ROOT, text=True, capture_output=True,
        env={**os.environ, "TERM": "dumb"}, timeout=20,
    )


class InstallerTests(unittest.TestCase):
    def test_launchers_discover_nested_completed_isos_not_partial_builds(self):
        module = smoke_module()
        with tempfile.TemporaryDirectory(prefix='hyprflux-test-') as temp:
            out = Path(temp)
            self.assertIsNone(module.latest_iso(out))
            images = []
            for index, name in enumerate(('old.iso', 'build-new/new.iso', 'build-failed/partial.iso')):
                path = out / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'fixture')
                os.utime(path, (100 + index, 100 + index))
                if index < 2:
                    path.with_name(path.name + '.sha256').touch()
                images.append(path)
            self.assertEqual(module.latest_iso(out), images[1])
            alias = out / 'alias.iso'
            alias.symlink_to(images[2])
            alias.with_name(alias.name + '.sha256').touch()
            self.assertEqual(module.latest_iso(out), images[1])
            launcher = (ROOT / 'test-qemu.sh').read_text()
            block = launcher.split('# Find ISO if not specified (installation mode only)', 1)[1]
            block = block.split('\nif [[ "${BOOT_DISK_ONLY}" != true ]] && [[ ! -f', 1)[0]
            self.check_bash(f'OUT_DIR={str(out)!r}\nBOOT_DISK_ONLY=false\nISO_FILE=""\n'
                            + block + f'\n[[ "$ISO_FILE" == {str(images[1])!r} ]]')

    def test_exact_image_report_excludes_repairs_and_other_images(self):
        import importlib.util
        import json
        spec = importlib.util.spec_from_file_location('acceptance_report', ROOT / 'tests/acceptance-report.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory(prefix='hyprflux-test-') as temp:
            base = Path(temp)
            for name, digest, resumed in (('good', 'expected', False), ('repair', 'expected', True), ('other', 'different', False)):
                state = base / name
                state.mkdir()
                (state / 'image.sha256').write_text(f'{digest}  image.iso\n')
                (state / 'machine.json').write_text(json.dumps(dict(embedded=True, resumed=resumed, profile='desktop', bios=False, disk_bus='virtio')))
                (state / 'installed.ok').touch()
                (state / 'desktop.png').write_bytes(b'\x89PNG\r\n\x1a\nfixture')
                (state / 'serial.log').write_text('\nHYPRFLUX_TEST_BOOT_PASS\n')
            rows = module.recorded_results(base, 'expected')
            self.assertEqual(len(rows), 2)
            self.assertEqual(sum(row['boot_pass'] for row in rows), 1)
            self.assertEqual(len(module.missing_cases(rows)), 5)
            self.assertIn(dict(profile='full', firmware='bios', layout='automatic'),
                          module.missing_cases(rows))
            good = base / 'good'
            (good / 'serial.log').write_text('echo HYPRFLUX_TEST_BOOT_PASS\n')
            self.assertFalse(any(row['boot_pass'] for row in module.recorded_results(base, 'expected')))
            (good / 'serial.log').write_text('\nHYPRFLUX_TEST_BOOT_PASS\n')
            metadata = json.loads((good / 'machine.json').read_text())
            metadata['maintenance_test'] = True
            (good / 'machine.json').write_text(json.dumps(metadata))
            self.assertFalse(any(row['boot_pass'] for row in module.recorded_results(base, 'expected')))
            metadata['maintenance_test'] = False
            (good / 'machine.json').write_text(json.dumps(metadata))
            (good / 'desktop.png').unlink()
            self.assertFalse(any(row['boot_pass'] for row in module.recorded_results(base, 'expected')))

    def test_batch_upstream_scripts_get_working_terminal_environment(self):
        wrapper = (ROOT / "airootfs/root/lib/hyprflux-chroot-wrapper.sh").read_text()
        run = "run_as_user() {" + wrapper.split("run_as_user() {", 1)[1].split("\n}", 1)[0] + "\n}"
        with tempfile.TemporaryDirectory(prefix="hyprflux-test-") as temp:
            script = Path(temp) / 'upstream.sh'
            script.write_text('set -e\n[[ "$TERM" == xterm-256color ]]\nprintf "UPSTREAM_STARTED\\n"\n')
            self.check_bash(run + f'''
                export TERM=dumb
                TARGET_HOME={temp!r}
                ARCH_HYPR_DIR={temp!r}
                TARGET_USER=fixture
                INSTALL_PROFILE=desktop
                FAILED_COMPONENTS=()
                run_stage() {{ shift; "$@"; }}
                su() {{ bash -c "${{@: -1}}"; }}
                run_as_user {str(script)!r}
                [[ ${{#FAILED_COMPONENTS[@]}} == 0 ]]
            ''')

    def test_audio_is_verified_offline_and_runtime_activation_remains_first_login(self):
        wrapper = (ROOT / "airootfs/root/lib/hyprflux-chroot-wrapper.sh").read_text()
        self.assertNotIn('run_as_user "${INSTALL_SCRIPTS}/pipewire.sh"', wrapper)
        self.assertNotIn('run_as_user "${INSTALL_SCRIPTS}/02-Final-Check.sh"', wrapper)
        self.assertIn('pacman -Q pipewire pipewire-audio pipewire-alsa pipewire-pulse wireplumber sof-firmware', wrapper)
        self.assertIn('systemctl --user enable --now pipewire.socket || session_pending=1', wrapper)
        self.assertIn('systemctl --user enable --now wireplumber.service || session_pending=1', wrapper)
        self.assertIn('cliphist kvantum rofi imagemagick swaync wl-clipboard kitty hypridle hyprlock', wrapper)

    def test_resume_does_not_claim_original_embedded_image_acceptance(self):
        module = smoke_module()
        original = dict(embedded=True, profile='desktop', bios=False, layout='manual-gpt')
        resumed = module.resumed_machine(original, 'full')
        self.assertFalse(resumed['embedded'])
        self.assertTrue(resumed['resumed'])
        self.assertEqual(resumed['profile'], 'full')
        self.assertEqual(resumed['layout'], 'manual-gpt')
        self.assertTrue(original['embedded'])
        self.assertEqual(original['profile'], 'desktop')

    def test_theme_module_runs_upstream_without_iso_rewriting(self):
        wrapper = (ROOT / "airootfs/root/lib/hyprflux-chroot-wrapper.sh").read_text()
        self.assertNotIn('prepare_iso_theme_module', wrapper)
        self.assertNotIn('ISO_THEME_MODULE', wrapper)
        self.assertIn('module_script="$module"', wrapper)
        self.assertIn('source \\"${module_script}\\"', wrapper)

    def test_installed_profile_and_missing_application_report_are_explicit(self):
        script = (ROOT / "tests/guest-install.sh").read_text()
        start = script.index('[[ $(cat "$MOUNT_POINT/etc/hyprflux-install-profile")')
        report = script[start:script.index('# Full-profile package acceptance', start)]
        with tempfile.TemporaryDirectory(prefix="hyprflux-test-") as temp:
            root = Path(temp)
            (root / 'etc').mkdir()
            (root / 'etc/hyprflux-install-profile').write_text('full\n')
            prefix = f'set -euo pipefail; MOUNT_POINT={temp!r}; INSTALL_PROFILE=full; '
            result = bash(prefix + report)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('HYPRFLUX_INSTALLED_PROFILE=full', result.stdout)
            self.assertIn('HYPRFLUX_OPTIONAL_MISSING_NONE', result.stdout)
            missing = root / 'var/log/hyprflux-installer/missing-applications.txt'
            missing.parent.mkdir(parents=True)
            missing.write_text('example-app\nanother-app\n')
            result = bash(prefix + report)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('HYPRFLUX_OPTIONAL_MISSING_BEGIN\nexample-app\nanother-app\nHYPRFLUX_OPTIONAL_MISSING_END', result.stdout)
            result = bash(prefix.replace('INSTALL_PROFILE=full', 'INSTALL_PROFILE=desktop') + report)
            self.assertNotEqual(result.returncode, 0)

    def test_manual_fixture_calls_real_manual_step_and_restores_shell_commands(self):
        script = (ROOT / "tests/guest-install.sh").read_text()
        run = "run_test_manual_layout() {" + script.split("run_test_manual_layout() {", 1)[1].split("\n}\n", 1)[0] + "\n}"
        self.check_bash(run + '''
            set -euo pipefail
            prepare_manual_layout_fixture() { echo FIXTURE; }
            step_disk_manual() { read; bash; echo VALIDATED; }
            run_test_manual_layout
            if declare -F read >/dev/null || declare -F bash >/dev/null; then exit 1; fi
        ''')

    def test_package_seed_copies_only_archives_without_overwriting_local_cache(self):
        script = (ROOT / "tests/guest-install.sh").read_text()
        copy = "copy_test_package_cache() {" + script.split("copy_test_package_cache() {", 1)[1].split("\n}", 1)[0] + "\n}"
        with tempfile.TemporaryDirectory(prefix="hyprflux-test-") as temp:
            source = Path(temp) / 'source'
            target = Path(temp) / 'target'
            source.mkdir()
            target.mkdir()
            (source / 'one.pkg.tar.zst').write_bytes(b'package fixture')
            (source / 'one.pkg.tar.zst.sig').write_bytes(b'signature fixture')
            (source / 'keep.pkg.tar.xz').write_bytes(b'shared old data')
            (target / 'keep.pkg.tar.xz').write_bytes(b'local cache preserved')
            (source / 'partial.pkg.tar.zst.part').write_bytes(b'incomplete')
            (source / 'link.pkg.tar.zst').symlink_to('one.pkg.tar.zst')
            self.check_bash(copy + f'\ncopy_test_package_cache {str(source)!r} {str(target)!r}')
            self.assertEqual((target / 'one.pkg.tar.zst').read_bytes(), b'package fixture')
            self.assertEqual((target / 'one.pkg.tar.zst.sig').read_bytes(), b'signature fixture')
            self.assertEqual((target / 'keep.pkg.tar.xz').read_bytes(), b'local cache preserved')
            self.assertFalse((target / 'partial.pkg.tar.zst.part').exists())
            self.assertFalse((target / 'link.pkg.tar.zst').exists())

    def test_manual_layout_validation_rejects_unsafe_incomplete_layouts(self):
        import shlex
        installer = (ROOT / "airootfs/root/hyprflux-install.sh").read_text()
        manual = installer.split('step_disk_manual() {', 1)[1].split('\n}\n', 1)[0]
        validation = manual[manual.index('    if ! mountpoint -q "$MOUNT_POINT";'):]
        baseline = dict(INSTALL_BOOT_MODE='uefi', ROOT_MOUNT='yes', EFI_MOUNT='yes',
                        ROOT_FS='ext4', EFI_FS='vfat', AVAILABLE='34359738368',
                         SINGLE_DISK='yes', PTTYPE='gpt', BIOS_PART='yes', ROOT_TYPE='part')
        cases = [({}, True), ({'ROOT_MOUNT': 'no'}, False),
                 ({'EFI_MOUNT': 'no'}, False), ({'AVAILABLE': '104857600'}, False),
                 ({'ROOT_FS': 'btrfs'}, False), ({'EFI_FS': 'ext4'}, False),
                 ({'ROOT_TYPE': 'crypt'}, False), ({'ROOT_TYPE': 'lvm'}, False),
                 ({'ROOT_TYPE': 'raid1'}, False),
                 ({'SINGLE_DISK': 'no'}, False),
                 ({'INSTALL_BOOT_MODE': 'bios'}, True),
                 ({'INSTALL_BOOT_MODE': 'bios', 'BIOS_PART': 'no'}, False),
                 ({'INSTALL_BOOT_MODE': 'bios', 'BIOS_PART': 'no', 'PTTYPE': 'dos'}, True)]
        mocks = '''
            set -euo pipefail
            MOUNT_POINT=/fake-target
            mountpoint() {
                if [[ "${@: -1}" == "$MOUNT_POINT" ]]; then [[ $ROOT_MOUNT == yes ]];
                else [[ $EFI_MOUNT == yes ]]; fi
            }
            df() { printf 'Avail\\n%s\\n' "$AVAILABLE"; }
            findmnt() {
                if [[ "$*" == *FSTYPE* ]]; then
                    if [[ "${@: -1}" == */boot ]]; then echo "$EFI_FS"; else echo "$ROOT_FS"; fi
                else echo /dev/fake-part; fi
            }
            parent_disk() { [[ $SINGLE_DISK == yes ]] || return 1; echo /dev/fake-disk; }
            lsblk() {
                if [[ "$*" == '-dnro TYPE '* ]]; then echo "$ROOT_TYPE";
                elif [[ "$*" == *PTTYPE* ]]; then echo "$PTTYPE";
                elif [[ $BIOS_PART == yes ]]; then echo 21686148-6449-6e6f-744e-656564454649; fi
            }
            die() { echo "REJECTED: $*"; exit 1; }
            log_ok() { echo ACCEPTED; }
        '''
        for overrides, accepted in cases:
            with self.subTest(layout=overrides):
                settings = {**baseline, **overrides}
                setup = '\n'.join(f'{key}={shlex.quote(value)}' for key, value in settings.items())
                result = bash(setup + '\n' + mocks + '\ncheck_layout() {\n' + validation + '\n}\ncheck_layout')
                self.assertEqual(result.returncode == 0, accepted, result.stdout + result.stderr)
                self.assertIn('ACCEPTED' if accepted else 'REJECTED', result.stdout)

    def test_installed_cleanup_rejects_shims_privileges_and_dangling_links(self):
        script = (ROOT / "tests/guest-verify.sh").read_text()
        verify = "assert_installer_cleanup() {" + script.split("assert_installer_cleanup() {", 1)[1].split("\n}", 1)[0] + "\n}"
        with tempfile.TemporaryDirectory(prefix="hyprflux-test-") as temp:
            root = Path(temp)
            systemctl = root / 'usr/bin/systemctl'
            systemctl.parent.mkdir(parents=True)
            systemctl.write_bytes(b'\x7fELFfixture')
            self.check_bash(verify + f'\nassert_installer_cleanup {temp!r}')
            for relative in ('etc/sudoers.d/hyprflux-temp', 'usr/local/bin/gsettings'):
                artifact = root / relative
                artifact.parent.mkdir(parents=True, exist_ok=True)
                artifact.symlink_to('missing-artifact')
                result = bash(verify + f'\nassert_installer_cleanup {temp!r}')
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(relative, result.stdout)
                artifact.unlink()
            systemctl.write_text('#!/bin/bash\nexit 0\n')
            result = bash(verify + f'\nassert_installer_cleanup {temp!r}')
            self.assertNotEqual(result.returncode, 0)

    def test_waybar_validation_rejects_errors_without_rewriting_source(self):
        import json
        wrapper = (ROOT / "airootfs/root/lib/hyprflux-chroot-wrapper.sh").read_text()
        validate = "validate_waybar() {" + wrapper.split("validate_waybar() {", 1)[1].split("\n}\n", 1)[0] + "\n}"
        with tempfile.TemporaryDirectory(prefix="hyprflux-test-") as temp:
            directory = Path(temp)
            # Pure-JSON fixture and a stdlib shim keep root-free checks free of
            # external dependencies; installed validation uses real json5.
            (directory / 'json5.py').write_text('from json import load\n')
            for name in ('config', 'ModulesWorkspaces', 'ModulesCustom', 'ModulesGroups', 'UserModules'):
                (directory / name).write_text('{}\n')
            modules = directory / 'Modules'
            modules.write_text('{"temperature": {\n "hwmon-path": [ "/sys/test" ]\n "interval": 10\n}}\n')
            with self.assertRaises(json.JSONDecodeError):
                json.loads(modules.read_text())
            prefix = validate + f'\nexport PYTHONPATH={temp!r}; python() {{ python3 "$@"; }}; '
            original = modules.read_bytes()
            result = bash(prefix + f'validate_waybar {temp!r}')
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(modules.read_bytes(), original)
            modules.write_text('{"temperature": {"hwmon-path": ["/sys/test"], "interval": 10}}\n')
            self.check_bash(prefix + f'validate_waybar {temp!r}')
            self.assertEqual(json.loads(modules.read_text())['temperature']['hwmon-path'], ['/sys/test'])
            (directory / 'UserModules').write_text('{ broken syntax }')
            result = bash(prefix + f'validate_waybar {temp!r}')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('UserModules', result.stderr)

    def test_waybar_session_imports_environment_and_finishes_setup_before_start(self):
        wrapper = (ROOT / "airootfs/root/lib/hyprflux-chroot-wrapper.sh").read_text()
        install = "install_waybar_session_service() {" + wrapper.split("install_waybar_session_service() {", 1)[1].split("\n}\n", 1)[0] + "\n}"
        with tempfile.TemporaryDirectory(prefix="hyprflux-test-") as temp:
            home = Path(temp)
            startup = home / '.config/hypr/UserConfigs/startup-apps.lua'
            startup.parent.mkdir(parents=True)
            startup.write_text('    hl.exec_cmd("waybar")\n    hl.exec_cmd("hypridle")\n')
            self.check_bash(install + f'\ninstall_waybar_session_service {temp!r}')
            self.assertNotIn('hl.exec_cmd("waybar")', startup.read_text())
            self.assertIn('hl.exec_cmd("hypridle")', startup.read_text())
            service = (home / '.config/systemd/user/hyprflux-waybar.service').read_text()
            self.assertIn('Restart=on-failure', service)
            self.assertIn('StartLimitBurst=5', service)
            self.assertNotIn('WantedBy=', service)
            (home / '.local/bin/hyprflux-first-boot.sh').write_text('echo FIRSTBOOT >> "$ORDER_LOG"\n')
            order = home / 'order.log'
            self.check_bash(f'''
                export HOME={temp!r} ORDER_LOG={str(order)!r}
                export WAYLAND_DISPLAY=wayland-1 HYPRLAND_INSTANCE_SIGNATURE=fixture
                dbus-update-activation-environment() {{ echo DBUS >> "$ORDER_LOG"; }}
                systemctl() {{
                    echo "$*" >> "$ORDER_LOG"
                    [[ "$*" != *reset-failed* ]]
                }}
                timeout() {{ shift 2; "$@"; }}
                flock() {{ echo LOCK_WAIT >> "$ORDER_LOG"; }}
                export -f dbus-update-activation-environment systemctl timeout flock
                bash "$HOME/.local/bin/hyprflux-start-waybar.sh"
            ''')
            steps = order.read_text()
            self.assertLess(steps.index('import-environment'), steps.index('FIRSTBOOT'))
            self.assertLess(steps.index('FIRSTBOOT'), steps.index('LOCK_WAIT'))
            self.assertLess(steps.index('LOCK_WAIT'), steps.index('restart hyprflux-waybar.service'))

    def test_waybar_diagnostic_cannot_convert_failed_autostart_to_pass(self):
        import socket
        guest = (ROOT / "tests/guest-verify.sh").read_text()
        cleanup = "boot_exit() {" + guest.split("boot_exit() {", 1)[1].split("\n}", 1)[0] + "\n}"
        with tempfile.TemporaryDirectory(prefix="hyprflux-test-") as temp:
            with socket.socket(socket.AF_UNIX) as server:
                server.bind(str(Path(temp) / "wayland-0"))
                result = bash(cleanup + f'''
                    XDG_RUNTIME_DIR={temp!r}
                    instance=fixture
                    uid=1000
                    ps() {{ :; }}
                    cat() {{ :; }}
                    runuser() {{ :; }}
                    pgrep() {{ return 1; }}
                    timeout() {{ echo "BOUNDED_DIAGNOSTIC $*"; return 0; }}
                    journalctl() {{ :; }}
                    sync() {{ :; }}
                    trap boot_exit EXIT
                    exit 7
                ''')
                self.assertEqual(result.returncode, 7)
                self.assertIn('BOUNDED_DIAGNOSTIC --kill-after=2s 10', result.stdout)
                self.assertIn('HYPRFLUX_TEST_BOOT_FAILED exit=7', result.stdout)
                self.assertNotIn('HYPRFLUX_TEST_BOOT_PASS', result.stdout)

    def test_embedded_install_uses_iso_scripts_without_copying_hotloaded_tree(self):
        script = (ROOT / "tests/guest-install.sh").read_text()
        branch = 'if [[ "${HYPRFLUX_TEST_EMBEDDED:-0}" == 1 ]]; then' + script.split('if [[ "${HYPRFLUX_TEST_EMBEDDED:-0}" == 1 ]]; then', 1)[1].split('\nfi', 1)[0] + '\nfi'
        for embedded in ("0", "1"):
            result = bash(f'export HYPRFLUX_TEST_EMBEDDED={embedded}; source() {{ echo "SOURCE $1"; }}; cp() {{ echo COPY; }}; {branch}')
            self.assertEqual(result.returncode, 0, result.stderr)
            if embedded == "1":
                self.assertIn('SOURCE /root/hyprflux-install.sh', result.stdout)
                self.assertNotIn('COPY', result.stdout)
            else:
                self.assertIn('SOURCE /root/hyprflux-test/hyprflux-install.sh', result.stdout)
                self.assertIn('COPY', result.stdout)

    def test_iso_does_not_rewrite_upstream_workspace_scale(self):
        wrapper = (ROOT / "airootfs/root/lib/hyprflux-chroot-wrapper.sh").read_text()
        self.assertNotIn('normalize_hyprland_defaults', wrapper)
        self.assertNotIn('special_scale_factor', wrapper)

    def test_wayland_capture_selects_socket_not_lock_or_unrelated_mount(self):
        import socket
        script = (ROOT / "tests/guest-verify.sh").read_text()
        select = script[script.index('wayland_socket=""'):script.index('source /root/guest-desktop-checks.sh')]
        with tempfile.TemporaryDirectory(prefix="hyprflux-test-") as temp:
            (Path(temp) / "wayland-0.lock").touch()
            with socket.socket(socket.AF_UNIX) as server:
                server.bind(str(Path(temp) / "wayland-1"))
                self.check_bash(f'export XDG_RUNTIME_DIR={temp!r}; set -euo pipefail; {select}\n[[ "$wayland_socket" == "$XDG_RUNTIME_DIR/wayland-1" ]]')

    def test_guest_screenshot_requires_complete_valid_png_transfer(self):
        import base64
        module = smoke_module()
        image = b"\x89PNG\r\n\x1a\nfixture"
        encoded = base64.b64encode(image)
        transfer = b"\r\nHYPRFLUX_SCREENSHOT_BEGIN\r\n" + encoded + b"\r\nHYPRFLUX_SCREENSHOT_END\r\n"
        self.assertEqual(module.guest_screenshot(transfer), image)
        self.assertIsNone(module.guest_screenshot(transfer.split(b"HYPRFLUX_SCREENSHOT_END")[0]))
        self.assertIsNone(module.guest_screenshot(b'echo HYPRFLUX_SCREENSHOT_BEGIN\n'))
        with self.assertRaises(ValueError):
            module.guest_screenshot(transfer.replace(encoded, base64.b64encode(b"not PNG")))
        with self.assertRaises(ValueError):
            module.guest_screenshot(transfer.replace(encoded, b"A"))

    def test_boot_failure_diagnostics_precede_marker_even_for_explicit_exit(self):
        guest = (ROOT / "tests/guest-verify.sh").read_text()
        cleanup = "boot_exit() {" + guest.split("boot_exit() {", 1)[1].split("\n}", 1)[0] + "\n}"
        result = bash(cleanup + '''
            ps() { echo PROCESSES; }
            cat() { echo FIRST_BOOT_LOG; }
            runuser() { echo USER_JOBS; }
            pgrep() { return 0; }
            journalctl() { echo JOURNAL; }
            sync() { :; }
            trap boot_exit EXIT
            exit 7
        ''')
        self.assertEqual(result.returncode, 7)
        self.assertIn("HYPRFLUX_TEST_BOOT_FAILED exit=7", result.stdout)
        self.assertLess(result.stdout.index("USER_JOBS"), result.stdout.index("HYPRFLUX_TEST_BOOT_FAILED"))

    def check_bash(self, code):
        result = bash(code)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_syntax(self):
        paths = list((ROOT / "airootfs").rglob("*.sh"))
        paths += list((ROOT / "tests").glob("*.sh"))
        paths += list((ROOT / "scripts").glob("*.sh"))
        paths += [ROOT / name for name in ("build.sh", "test-qemu.sh", "profiledef.sh")]
        for path in paths:
            with self.subTest(path=str(path.relative_to(ROOT))):
                result = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_source_does_not_start_installation(self):
        self.check_bash('source airootfs/root/hyprflux-install.sh; declare -F main >/dev/null')

    def test_validation(self):
        self.check_bash('''
            set -e
            source airootfs/root/lib/common.sh
            for name in hyprflux laptop-1 A a1; do validate_hostname "$name"; done
            for name in localhost -pc pc- 'a.b' ''; do ! validate_hostname "$name"; done
            validate_password 'a $ ! ` quote"'
            for pass in '' 'a:b' $'a\nb' $'a\rb'; do ! validate_password "$pass"; done
            ! validate_username root
            ! validate_username nobody
            ! validate_username 'Bad Name'
        ''')

    def test_partition_names(self):
        self.check_bash('''
            set -e
            source airootfs/root/lib/common.sh
            [[ $(get_part_prefix /dev/sda) == /dev/sda ]]
            [[ $(get_part_prefix /dev/vda) == /dev/vda ]]
            [[ $(get_part_prefix /dev/nvme0n1) == /dev/nvme0n1p ]]
            [[ $(get_part_prefix /dev/mmcblk0) == /dev/mmcblk0p ]]
            [[ $(get_part_prefix /dev/nbd0) == /dev/nbd0p ]]
            ! disk_is_installable /dev/null
            ! disk_is_installable /dev/not-a-disk
        ''')

    def test_rejects_unsupported_cpu_before_disk_access(self):
        self.check_bash('''
            set -e
            source airootfs/root/lib/common.sh
            uname() { echo aarch64; }
            ! check_platform
        ''')

    def test_locale_list_includes_commented_and_three_letter_locales(self):
        with tempfile.TemporaryDirectory(prefix="hyprflux-test-") as temp:
            locales = Path(temp) / "locale.gen"
            locales.write_text('# locales using UTF-8\n#en_US.UTF-8 UTF-8\n#fil_PH UTF-8\nur_PK UTF-8\nde_DE ISO-8859-1\n')
            result = bash(f'source airootfs/root/lib/common.sh; list_utf8_locales {str(locales)!r}')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.splitlines(), ['en_US.UTF-8', 'fil_PH', 'ur_PK'])

    def test_parent_disk_uses_block_topology(self):
        self.check_bash('''
            set -e
            source airootfs/root/lib/common.sh
            lsblk() { printf '/dev/nvme0n1p2 part\\n/dev/nvme0n1 disk\\n'; }
            [[ $(parent_disk /dev/nvme0n1p2) == /dev/nvme0n1 ]]
            lsblk() { printf '/dev/sda disk\\n/dev/sdb disk\\n'; }
            ! parent_disk /dev/md0
        ''')

    def test_configuration_stops_at_first_chroot_failure(self):
        with tempfile.TemporaryDirectory(prefix="hyprflux-test-") as temp:
            result = bash(f'''
                source airootfs/root/hyprflux-install.sh
                MOUNT_POINT={temp!r}
                start_progress() {{ PROGRESS_LOG="$MOUNT_POINT/progress.log"; }}
                stop_progress() {{ :; }}
                die() {{ exit 42; }}
                arch-chroot() {{ echo "$*" >> "$MOUNT_POINT/calls"; return 17; }}
                step_configure_system
            ''')
            self.assertEqual(result.returncode, 42, result.stdout + result.stderr)
            calls = (Path(temp) / "calls").read_text().splitlines()
            self.assertEqual(len(calls), 1, calls)
            self.assertIn("ln -sf", calls[0])

    def test_partition_failure_never_reaches_format(self):
        with tempfile.TemporaryDirectory(prefix="hyprflux-test-") as temp:
            result = bash(f'''
                source airootfs/root/hyprflux-install.sh
                MOUNT_POINT={temp!r}
                start_progress() {{ PROGRESS_LOG="$MOUNT_POINT/progress.log"; }}
                stop_progress() {{ :; }}
                show_banner() {{ :; }}
                set_status() {{ :; }}
                tui_print() {{ :; }}
                tui_yesno() {{ return 1; }}
                tui_menu() {{ echo '/dev/fake (40G) Test'; }}
                tui_input() {{ echo yes; }}
                die() {{ exit 42; }}
                disk_is_installable() {{ return 0; }}
                blockdev() {{ echo 42949672960; }}
                lsblk() {{ echo '/dev/fake 40G Test'; }}
                sgdisk() {{ echo sgdisk >> "$MOUNT_POINT/calls"; return 17; }}
                wipefs() {{ echo UNSAFE >> "$MOUNT_POINT/calls"; }}
                step_disk_auto
            ''')
            self.assertEqual(result.returncode, 42, result.stdout + result.stderr)
            self.assertEqual((Path(temp) / "calls").read_text(), "sgdisk\n")

    def test_logs_survive_progress_cleanup(self):
        with tempfile.TemporaryDirectory(prefix="hyprflux-test-") as temp:
            self.check_bash(f'''
                source airootfs/root/lib/tui.sh
                PROGRESS_LOG={temp!r}/failure.log
                echo failure > "$PROGRESS_LOG"
                stop_progress
                [[ -s {temp!r}/failure.log ]]
                _tui_cleanup
                [[ -s {temp!r}/failure.log ]]
            ''')

    def test_failed_reflector_keeps_working_mirrors(self):
        with tempfile.TemporaryDirectory(prefix="hyprflux-test-") as temp:
            mirrors = Path(temp) / "mirrorlist"
            original = 'Server = https://example.org/$repo/os/$arch\n'
            mirrors.write_text(original)
            self.check_bash(f'''
                set -e
                source airootfs/root/lib/common.sh
                timeout() {{ return 124; }}
                refresh_mirrors {str(mirrors)!r}
            ''')
            self.assertEqual(mirrors.read_text(), original)

    def test_existing_qemu_disk_is_not_deleted(self):
        with tempfile.TemporaryDirectory(prefix="hyprflux-test-") as temp:
            disk = Path(temp) / "precious.qcow2"
            iso = Path(temp) / "dummy.iso"
            disk.write_bytes(b"do not delete")
            iso.touch()
            result = bash(f'bash test-qemu.sh --bios --headless --allow-stale-iso --disk={str(disk)!r} {str(iso)!r}')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Refusing to delete existing test disk", result.stdout)
            self.assertEqual(disk.read_bytes(), b"do not delete")

    def test_qemu_disk_lock_precedes_overwrite(self):
        import fcntl
        with tempfile.TemporaryDirectory(prefix="hyprflux-test-") as temp:
            disk = Path(temp) / "running.qcow2"
            iso = Path(temp) / "dummy.iso"
            disk.write_bytes(b"running VM")
            iso.touch()
            with Path(str(disk) + ".lock").open("w") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                result = bash(f'bash test-qemu.sh --bios --headless --allow-stale-iso --overwrite-disk --disk={str(disk)!r} {str(iso)!r}')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("already in use", result.stdout)
            self.assertEqual(disk.read_bytes(), b"running VM")

    def test_first_boot_retries_failed_session_setup(self):
        wrapper = (ROOT / "airootfs/root/lib/hyprflux-chroot-wrapper.sh").read_text()
        script = wrapper.split("<< 'FIRSTBOOT_EOF'\n", 1)[1].split("\nFIRSTBOOT_EOF", 1)[0]
        with tempfile.TemporaryDirectory(prefix="hyprflux-test-") as temp:
            home = Path(temp)
            mock = home / "mock"
            mock.mkdir()
            papirus = home / 'papirus-checkmark.svg'
            papirus.write_text('<svg><style>.ColorScheme-PositiveText { color:#4caf50; }</style>'
                               '<path class="ColorScheme-Text" /></svg>')
            script = script.replace('/usr/share/icons/Papirus/24x24/actions/dialog-ok-apply.svg', str(papirus))
            for command in ("gsettings", "systemctl", "nwg-look", "notify-send", "sleep"):
                path = mock / command
                if command == "systemctl":
                    path.write_text('#!/bin/bash\nexit "${FAIL_SESSION:-0}"\n')
                elif command == "nwg-look":
                    # -a restores a nonexistent backup on a fresh install.
                    # -x exports the settings applied by gsettings instead.
                    path.write_text('#!/bin/bash\n[[ "$1" == -x ]] || exit 1\ntouch "$HOME/exported-gtk-settings"\n')
                elif command == "notify-send":
                    path.write_text('#!/bin/bash\nprintf "%s\\n" "$@" > "$HOME/notification-args"\n')
                else:
                    path.write_text('#!/bin/bash\nexit 0\n')
                path.chmod(0o755)
            entry = home / ".config/autostart/hyprflux-first-boot.desktop"
            entry.parent.mkdir(parents=True)
            entry.touch()
            marker = home / ".config/hyprflux-first-boot-done"
            env = {**os.environ, "HOME": temp, "PATH": f"{mock}:{os.environ['PATH']}", "FAIL_SESSION": "1"}
            subprocess.run(["bash", "-c", script], env=env, check=True, timeout=10)
            self.assertFalse(marker.exists())
            self.assertTrue(entry.exists())
            self.assertNotIn('--icon=', (home / 'notification-args').read_text())
            env["FAIL_SESSION"] = "0"
            subprocess.run(["bash", "-c", script], env=env, check=True, timeout=10)
            self.assertTrue(marker.exists())
            self.assertTrue((home / "exported-gtk-settings").is_file())
            self.assertFalse(entry.exists())
            icon = home / '.local/share/icons/hyprflux-first-boot-success.svg'
            self.assertIn('class="ColorScheme-PositiveText"', icon.read_text())
            self.assertIn('class="ColorScheme-Text"', papirus.read_text())
            self.assertIn(f'--icon={icon}', (home / 'notification-args').read_text())
            self.assertIn('First-boot setup complete!', (home / 'notification-args').read_text())

    def test_wrapper_cleanup_runs_on_failure(self):
        wrapper = (ROOT / "airootfs/root/lib/hyprflux-chroot-wrapper.sh").read_text()
        cleanup = wrapper.split("cleanup_wrapper() {", 1)[1].split("\n}", 1)[0]
        with tempfile.TemporaryDirectory(prefix="hyprflux-test-") as temp:
            for name in ("etc/sudoers.d/hyprflux-temp", "etc/sudoers.d/99-hyprflux-temp", "usr/local/bin/chsh", "usr/local/bin/gsettings",
                         "usr/local/bin/nwg-look", "usr/local/bin/yay-iso", "tmp/hyprflux-module-env.sh"):
                path = Path(temp) / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
            import re
            cleanup = re.sub(r"/(?:etc|usr|tmp)/", lambda match: temp + match[0], cleanup)
            result = bash("cleanup_wrapper() {" + cleanup + "\n}\ntrap cleanup_wrapper EXIT\nexit 17")
            self.assertEqual(result.returncode, 17)
            self.assertFalse(any(path.is_file() for path in Path(temp).rglob("*")))

    def test_serial_marker_does_not_accept_echoed_shell_commands(self):
        module = smoke_module()
        self.assertFalse(module.marker_seen(b'echo HYPRFLUX_TEST_SMOKE_PASS\r\n', b'HYPRFLUX_TEST_SMOKE_PASS'))
        self.assertTrue(module.marker_seen(b'\r\nHYPRFLUX_TEST_SMOKE_PASS\r\n', b'HYPRFLUX_TEST_SMOKE_PASS'))
        self.assertTrue(module.marker_seen(b'\nHYPRFLUX_TEST_FAILED line=42\n', b'HYPRFLUX_TEST_FAILED', details=True))

    def test_serial_accepts_root_prompt_after_interrupted_zlogin(self):
        module = smoke_module()
        self.assertTrue(module.shell_ready(b'\rhyprflux# '))
        self.assertTrue(module.shell_ready(b'Installer exited. You are now in a root shell.'))
        self.assertFalse(module.shell_ready(b'Welcome to the HyprFlux Installer!'))

    def test_core_package_download_retries_are_bounded(self):
        wrapper = (ROOT / "airootfs/root/lib/hyprflux-chroot-wrapper.sh").read_text()
        retry = "pacman_retry() {" + wrapper.split("pacman_retry() {", 1)[1].split("\n}", 1)[0] + "\n}"
        self.check_bash(retry + '''
            calls=0
            sleep() { :; }
            pacman() { calls=$((calls + 1)); (( calls >= 2 )); }
            pacman_retry -Syu test-package || exit 1
            [[ $calls == 2 ]] || exit 1
            calls=0
            pacman() { calls=$((calls + 1)); return 1; }
            if pacman_retry -Syu test-package; then exit 1; fi
            [[ $calls == 3 ]]
        ''')

    def test_only_clean_pinned_checkout_is_reused(self):
        with tempfile.TemporaryDirectory(prefix="hyprflux-test-") as temp:
            repo = Path(temp)
            env = {**os.environ, "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"}
            def git(*args):
                return subprocess.check_output(["git", "-C", temp, *args], env=env, text=True).strip()
            git("init", "-q")
            (repo / "tracked").write_text("original\n")
            (repo / ".gitignore").write_text("# fixture intentionally does not ignore logs\n")
            git("add", ".")
            git("-c", "user.name=Test", "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false", "commit", "-qm", "fixture")
            git("remote", "add", "origin", "https://github.com/ahmad9059/HyprFlux.git")
            revision = git("rev-parse", "HEAD")
            (repo / "logs").mkdir()
            (repo / "logs/iso-wrapper.log").write_text("previous attempt\n")
            self.check_bash(f'source airootfs/root/lib/common.sh; checkout_matches_release {temp!r} {revision!r}')
            (repo / "tracked").write_text("user work\n")
            self.check_bash(f'source airootfs/root/lib/common.sh; ! checkout_matches_release {temp!r} {revision!r}')
            (repo / "tracked").write_text("original\n")
            (repo / "user-script.sh").write_text("echo user work\n")
            self.check_bash(f'source airootfs/root/lib/common.sh; ! checkout_matches_release {temp!r} {revision!r}')

    def test_mirror_retry_rotates_priority_without_losing_servers(self):
        wrapper = (ROOT / "airootfs/root/lib/hyprflux-chroot-wrapper.sh").read_text()
        rotate = "rotate_mirrors() {" + wrapper.split("rotate_mirrors() {", 1)[1].split("\n}", 1)[0] + "\n}"
        with tempfile.TemporaryDirectory(prefix="hyprflux-test-") as temp:
            mirrors = Path(temp) / "mirrorlist"
            mirrors.write_text('# keep comment\nServer = https://one/$repo\nServer = https://two/$repo\nServer = https://three/$repo\n')
            self.check_bash(rotate + f'\nrotate_mirrors {str(mirrors)!r}')
            self.assertEqual(mirrors.read_text().splitlines(), ['# keep comment',
                'Server = https://two/$repo', 'Server = https://three/$repo', 'Server = https://one/$repo'])

    def test_lock_recovery_refuses_busy_or_uninspectable_package_manager(self):
        wrapper = (ROOT / "airootfs/root/lib/hyprflux-chroot-wrapper.sh").read_text()
        recover = "recover_pacman_lock() {" + wrapper.split("recover_pacman_lock() {", 1)[1].split("\n}", 1)[0] + "\n}"
        with tempfile.TemporaryDirectory(prefix="hyprflux-test-") as temp:
            lock = Path(temp) / "db.lck"
            lock.touch()
            self.check_bash(recover + f'''
                pgrep() {{ return 0; }}
                if recover_pacman_lock {str(lock)!r}; then exit 1; fi
                [[ -f {str(lock)!r} ]] || exit 1
                pgrep() {{ return 2; }}
                if recover_pacman_lock {str(lock)!r}; then exit 1; fi
                [[ -f {str(lock)!r} ]] || exit 1
                pgrep() {{ return 1; }}
                recover_pacman_lock {str(lock)!r} || exit 1
                [[ ! -e {str(lock)!r} ]]
            ''')

    def test_guest_failure_flushes_and_unmounts_before_failure_marker(self):
        guest = (ROOT / "tests/guest-install.sh").read_text()
        cleanup = "test_exit() {" + guest.split("test_exit() {", 1)[1].split("\n}", 1)[0] + "\n}"
        with tempfile.TemporaryDirectory(prefix="hyprflux-test-") as temp:
            live = Path(temp) / "live"
            live.mkdir()
            (live / "progress.log").write_text("preserved failure details\n")
            result = bash(cleanup + f'''
                _TEST_VM_CONFIRMED=1
                MOUNT_POINT={temp!r}/target
                INSTALL_LOG_DIR={str(live)!r}
                SWAP_PART=/dev/fake-test-swap
                sync() {{ echo SYNC; }}
                mountpoint() {{ return 0; }}
                umount() {{ echo UNMOUNT; }}
                swapoff() {{ echo SWAPOFF; }}
                false
                test_exit
            ''')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertLess(result.stdout.index("UNMOUNT"), result.stdout.index("HYPRFLUX_TEST_FAILED"))
            self.assertEqual(result.stdout.count("SYNC"), 2)
            self.assertTrue((Path(temp) / "target/var/log/hyprflux-installer/failed-live/progress.log").is_file())

    def test_chroot_config_verifier_uses_private_short_runtime_and_cleans_it(self):
        wrapper = (ROOT / "airootfs/root/lib/hyprflux-chroot-wrapper.sh").read_text()
        start = wrapper.index('if ! timeout 60 su - "$TARGET_USER"')
        verify = wrapper[start:wrapper.index("\nfi", start) + 3]
        with tempfile.TemporaryDirectory(prefix="hyprflux-test-") as temp:
            mock = Path(temp) / "Hyprland"
            mock.write_text('''#!/bin/bash
set -euo pipefail
[[ -d "$XDG_RUNTIME_DIR" && -O "$XDG_RUNTIME_DIR" ]]
[[ $(stat -c %a "$XDG_RUNTIME_DIR") == 700 ]]
[[ ${#XDG_RUNTIME_DIR} -lt 24 ]]
printf '%s' "$XDG_RUNTIME_DIR" > "$AUDIT_FILE"
exit "$VERIFY_RESULT"
''')
            mock.chmod(0o755)
            for code in (0, 7):
                with self.subTest(result=code):
                    audit = Path(temp) / f"runtime-{code}"
                    self.check_bash(f'''
                        export PATH={temp!r}:"$PATH" HOME={temp!r}
                        export AUDIT_FILE={str(audit)!r} VERIFY_RESULT={code}
                        unset XDG_RUNTIME_DIR
                        TARGET_USER=fixture
                        critical_failed=0
                        timeout() {{ shift; "$@"; }}
                        su() {{ bash -c "${{@: -1}}"; }}
                        {verify}
                        [[ $critical_failed == {int(bool(code))} ]]
                    ''')
                    self.assertFalse(Path(audit.read_text()).exists())

    def test_console_key_mapping_rejects_unsupported_input(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location("qemu_console", ROOT / "tests/qemu-console.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertEqual(module.key_for("S"), "shift-s")
        self.assertEqual(module.key_for("/"), "slash")
        self.assertEqual(module.key_for(">"), "shift-dot")
        self.assertEqual(module.key_for("\n"), "ret")
        with self.assertRaises(ValueError):
            module.key_for("\x1b")

    def test_application_profile_choice_is_explicit(self):
        self.check_bash('''
            source airootfs/root/hyprflux-install.sh
            show_banner() { :; }
            set_status() { :; }
            tui_print() { :; }
            tui_menu() { echo 'Desktop (recommended; smaller and faster)'; }
            step_profile
            [[ $INSTALL_PROFILE == desktop ]] || exit 1
            tui_menu() { echo 'Full application bundle'; }
            step_profile
            [[ $INSTALL_PROFILE == full ]]
        ''')

    def test_critical_desktop_aur_is_verified_before_bulk_apps(self):
        wrapper = (ROOT / "airootfs/root/lib/hyprflux-chroot-wrapper.sh").read_text()
        ensure = "install_desktop_aur() {" + wrapper.split("install_desktop_aur() {", 1)[1].split("\n}", 1)[0] + "\n}"
        self.assertLess(wrapper.index("install_desktop_aur || exit 1"), wrapper.index('run_as_user "${INSTALL_SCRIPTS}/01-hypr-pkgs.sh"'))
        with tempfile.TemporaryDirectory(prefix="hyprflux-test-") as temp:
            marker = Path(temp) / "desktop-present"
            self.check_bash(ensure + f'''
                TARGET_USER=fixture
                RETRY_MIRRORLIST=fixture
                calls=0
                desktop_commands_present() {{ [[ -f {str(marker)!r} ]]; }}
                rotate_mirrors() {{ :; }}
                run_stage() {{
                    calls=$((calls + 1))
                    if (( calls >= 2 )); then touch {str(marker)!r}; return 0; fi
                    return 1
                }}
                install_desktop_aur || exit 1
                [[ $calls == 2 ]] || exit 1
                install_desktop_aur || exit 1
                [[ $calls == 2 ]] || exit 1
                rm -f {str(marker)!r}
                calls=0
                run_stage() {{ calls=$((calls + 1)); return 1; }}
                if install_desktop_aur; then exit 1; fi
                [[ $calls == 3 ]]
            ''')

    def test_desktop_readiness_requires_registered_packages_and_commands(self):
        wrapper = (ROOT / "airootfs/root/lib/hyprflux-chroot-wrapper.sh").read_text()
        ready = "desktop_commands_present() {" + wrapper.split("desktop_commands_present() {", 1)[1].split("\n}", 1)[0] + "\n}"
        self.check_bash(ready + '''
            command() { return 0; }
            pacman() { return 1; }
            if desktop_commands_present; then exit 1; fi
            pacman() { return 0; }
            desktop_commands_present || exit 1
            command() { return 1; }
            if desktop_commands_present; then exit 1; fi
        ''')


if __name__ == "__main__":
    unittest.main(verbosity=2)
