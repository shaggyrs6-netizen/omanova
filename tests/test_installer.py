"""Installer control-flow tests. All external services are substituted.

The real Git/lock/file operations run in temporary directories; no session,
package manager, network connection or user's configuration is touched.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1]


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='omanova-installer-test-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.project = self.root / 'project'
        self.project.mkdir()
        self.home = self.root / 'home'
        self.home.mkdir()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, HOME=str(self.home),
                        XDG_CONFIG_HOME=str(self.home / '.config'),
                        XDG_DATA_HOME=str(self.home / '.local/share'),
                        PATH=f'{self.bin}:/usr/bin:/bin', QA=str(self.root),
                        GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1')
        self.env.pop('BASH_ENV', None)
        self.env.pop('GIT_CONFIG_COUNT', None)
        for f in ['install', 'manifest.json', 'BarWidget.qml', 'SkyState.qml',
                  'SkyPanel.qml', 'Compass.qml', 'SettingsPage.qml']:
            shutil.copy2(SOURCE / f, self.project / f)
        shutil.copytree(SOURCE / 'systemd', self.project / 'systemd')
        self.script(self.project / 'setup-runtime', '''#!/bin/bash
set -eu
mkdir -p "$XDG_DATA_HOME/omasky"
ln -s "$PWD" "$XDG_DATA_HOME/omasky/runtime" 2>/dev/null || true
printf '{"generated":"2000-01-01T00:00:00Z"}' >"$XDG_DATA_HOME/omasky/snapshot.json"
touch "$QA/setup-called"
''')
        self.script(self.bin / 'systemctl', '''#!/usr/bin/python
import os,sys,json,datetime
from pathlib import Path
q=Path(os.environ['QA']); args=sys.argv[1:]; action=args[1]
with (q/'service-calls').open('a') as f: f.write(' '.join(args)+'\\n')
if action=='show-environment': print('XDG_DATA_HOME='+os.environ['XDG_DATA_HOME'])
elif action=='is-active': sys.exit(0 if (q/'running').exists() else 3)
elif action=='stop': (q/'running').unlink(missing_ok=True)
elif action=='restart':
 (q/'running').touch()
 if not (q/'fail-worker').exists():
  p=Path(os.environ['XDG_DATA_HOME'])/'omasky/snapshot.json'
  p.write_text(json.dumps({'generated':datetime.datetime.now(datetime.timezone.utc).isoformat()}))
elif action=='enable': (q/'enabled').touch()
elif action=='show': print('0')
''')
        self.script(self.bin / 'omarchy', '''#!/bin/bash
set -eu
if [[ $2 == add ]]; then
 git clone -q "$3" "$HOME/.config/omarchy/plugins/io.github.shaggyrs6-netizen.omanova"
fi
''')
        self.script(self.bin / 'uv', '#!/bin/bash\nexit 0\n')
        self.script(self.bin / 'sleep', '#!/bin/bash\nexit 0\n')
        self.script(self.bin / 'sudo', '''#!/bin/bash
printf '%s\\n' "$*" >"$QA/sudo-called"
''')
        self.git('init', '-q')
        self.git('add', '.')
        self.git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                 'commit', '-qm', 'fixture')

    @staticmethod
    def script(path, body):
        path.write_text(body)
        path.chmod(0o755)

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.project), *args],
                                       env=self.env, text=True).strip()

    def run_install(self, *args, input=None):
        return subprocess.run([str(self.project / 'install'), *args], env=self.env,
                              input=input, text=True, capture_output=True, timeout=15)

    def missing_uv(self):
        # Override discovery only; no real package-manager operation can run.
        envfile = self.root / 'bash-env'
        envfile.write_text('command() { if [[ "$*" == "-v uv" ]]; then return 1; else builtin command "$@"; fi; }\n')
        self.env['BASH_ENV'] = str(envfile)

    def test_fresh_and_repeat_preserve_autostart_default(self):
        for _ in range(2):
            result = self.run_install()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((self.root / 'enabled').exists())
        plugin = self.home / '.config/omarchy/plugins/io.github.shaggyrs6-netizen.omanova'
        self.assertEqual(subprocess.check_output(['git','-C',str(plugin),'rev-parse','HEAD'], text=True).strip(), self.git('rev-parse','HEAD'))

    def test_explicit_autostart_after_readiness(self):
        result = self.run_install('--autostart')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / 'enabled').exists())

    def test_worker_failure_does_not_enable_or_claim_success(self):
        (self.root / 'fail-worker').touch()
        result = self.run_install('--autostart')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('did not produce a fresh snapshot', result.stderr)
        self.assertNotIn('OMANOVA is ready', result.stdout)
        self.assertFalse((self.root / 'enabled').exists())

    def test_config_path_rejected_before_side_effects(self):
        self.env['XDG_CONFIG_HOME'] = str(self.root / 'custom')
        result = self.run_install()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'service-calls').exists())
        self.assertFalse((self.root / 'setup-called').exists())

    def test_uncommitted_widget_rejected(self):
        with (self.project / 'BarWidget.qml').open('a') as f: f.write('\n// changed\n')
        result = self.run_install()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('differs from its Git revision', result.stderr)
        self.assertFalse((self.root / 'setup-called').exists())

    def test_missing_uv_decline(self):
        self.missing_uv()
        result = self.run_install(input='n\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'sudo-called').exists())
        self.assertFalse((self.root / 'setup-called').exists())

    def test_missing_uv_accept_exact_package_command(self):
        self.missing_uv()
        result = self.run_install(input='y\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / 'sudo-called').read_text().strip(), 'pacman -S --needed uv')

    def test_foreground_worker_refused(self):
        import fcntl
        state = Path(self.env['XDG_DATA_HOME']) / 'omasky'
        state.mkdir(parents=True)
        with (state / 'watch.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_install()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('foreground worker', result.stderr)
        self.assertFalse((self.root / 'setup-called').exists())

    def test_dirty_installed_widget_is_preserved(self):
        self.assertEqual(self.run_install().returncode, 0)
        widget = self.home / '.config/omarchy/plugins/io.github.shaggyrs6-netizen.omanova/BarWidget.qml'
        customised = widget.read_text() + '\n// personal change\n'
        widget.write_text(customised)
        result = self.run_install()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('not a clean Git checkout', result.stderr)
        self.assertEqual(widget.read_text(), customised)

    def test_release_archive_uses_tag_when_remote_head_is_newer(self):
        self.git('tag', 'v0.1.2')
        archive = self.root / 'archive'
        shutil.copytree(self.project, archive, ignore=shutil.ignore_patterns('.git'))
        with (self.project / 'BarWidget.qml').open('a') as f:
            f.write('\n// later remote change\n')
        self.git('add', '.')
        self.git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                 'commit', '-qm', 'newer main')
        self.env.update(GIT_CONFIG_COUNT='1',
                        GIT_CONFIG_KEY_0=f'url.file://{self.project}.insteadOf',
                        GIT_CONFIG_VALUE_0='https://github.com/shaggyrs6-netizen/omanova.git')
        result = subprocess.run([str(archive / 'install')], env=self.env,
                                text=True, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        widget = self.home / '.config/omarchy/plugins/io.github.shaggyrs6-netizen.omanova/BarWidget.qml'
        self.assertEqual(widget.read_bytes(), (archive / 'BarWidget.qml').read_bytes())


if __name__ == '__main__':
    unittest.main()
