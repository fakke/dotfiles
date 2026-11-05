import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.repo = self.base / 'dotfiles'
        self.home = self.base / 'home'
        self.bin = self.base / 'bin'
        for directory in (self.repo, self.home, self.bin, self.repo / 'setup'):
            directory.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / 'install.sh', self.repo)
        shutil.copy2(ROOT / 'setup/check.sh', self.repo / 'setup')
        shutil.copy2(ROOT / 'setup/bootstrap.sh', self.repo / 'setup')
        shutil.copy2(ROOT / '.stowrc', self.repo)
        self.stub('stow', 'exit 0')
        self.log = self.base / 'commands'
        self.installed = self.base / 'installed'
        self.installed.write_text('')
        self.env = dict(os.environ, HOME=str(self.home), PATH=f'{self.bin}:/usr/bin:/bin',
                        LOG=str(self.log), INSTALLED=str(self.installed))
        self.git = shutil.which('git')
        subprocess.run([self.git, 'init', '-q', str(self.repo)], check=True)
        self.stub('uname', 'echo Darwin')
        self.stub('brew', '''
case "$*" in
    'list --formula -1') cat "$INSTALLED" ;;
    'list --cask -1') ;;
    shellenv) ;;
    'list --versions '*) exit 1 ;;
    install*) printf '%s\\n' "$*" >> "$LOG"; shift; printf '%s\\n' "$@" >> "$INSTALLED" ;;
    *) exit 2 ;;
esac
''')
        self.stub('sudo', 'exec "$@"')

    def stub(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/bash\nset -e\n' + body + '\n')
        path.chmod(0o755)

    def package(self, name, dependencies, linked=True):
        directory = self.repo / 'configs' / name / '.config' / name
        directory.mkdir(parents=True)
        config = directory / 'config'
        config.write_text('configuration\n')
        (self.repo / 'configs' / name / 'setup').mkdir()
        for manager in ('apt', 'brew'):
            (self.repo / 'configs' / name / 'setup' / f'packages.{manager}').write_text(dependencies)
        subprocess.run([self.git, '-C', str(self.repo), 'add', 'configs/' + name], check=True)
        if linked:
            target = self.home / '.config' / name
            target.mkdir(parents=True)
            (target / 'config').symlink_to(os.path.relpath(config, target))
        return directory

    def run_installer(self, *args):
        return subprocess.run(['/bin/bash', str(self.repo / 'install.sh'), *args],
                              env=self.env, cwd=self.base, text=True, capture_output=True)

    def ubuntu(self):
        release = self.base / 'os-release'
        release.write_text('ID=ubuntu\n')
        path = self.repo / 'install.sh'
        path.write_text(path.read_text().replace('/etc/os-release', str(release)))
        self.stub('uname', 'echo Linux')
        self.stub('dpkg-query', '''while read -r name; do printf '%s\\tinstalled\\n' "$name"; done < "$INSTALLED"''')
        self.stub('apt-cache', 'echo "  Candidate: 1.0"')
        self.stub('apt-get', '''
printf '%s\\n' "$*" >> "$LOG"
if [[ $1 == install ]]; then shift 2; printf '%s\\n' "$@" >> "$INSTALLED"; fi
''')

    def test_no_links_does_not_call_package_manager(self):
        self.package('alpha', 'one\n', linked=False)
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('No linked configs', result.stdout)
        self.assertFalse(self.log.exists())

    def test_rejects_explicit_selection(self):
        result = self.run_installer('fish')
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.log.exists())

    def test_regular_copy_is_not_linked(self):
        self.package('alpha', 'one\n', linked=False)
        directory = self.home / '.config/alpha'
        directory.mkdir(parents=True)
        (directory / 'config').write_text('configuration\n')
        self.assertIn('No linked configs', self.run_installer().stdout)

    def test_check_reports_partial_links(self):
        directory = self.package('alpha', 'one\n')
        (directory / 'second').write_text('second\n')
        subprocess.run([self.git, '-C', str(self.repo), 'add', '.'], check=True)
        result = self.run_installer('--check')
        self.assertEqual(result.returncode, 1)
        self.assertIn('Partially linked', result.stderr)
        self.assertFalse(self.log.exists())

    def test_check_reports_missing_without_installing(self):
        self.package('alpha', 'one\n')
        result = self.run_installer('--check')
        self.assertEqual(result.returncode, 1)
        self.assertIn('Missing package: one', result.stdout)
        self.assertFalse(self.log.exists())

    def test_brew_deduplicates_and_skips_unlinked(self):
        self.package('alpha', 'one\nshared\n')
        self.package('beta', 'two\nshared\n')
        self.package('unused', 'never\n', linked=False)
        self.installed.write_text('one\n')
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text(), 'install shared two\n')
        second = self.run_installer()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(self.log.read_text(), 'install shared two\n')

    def test_brew_alias_is_recognized(self):
        self.package('alpha', 'python\n')
        self.stub('brew', '''case "$*" in
'list --formula -1') echo python@3.14 ;;
'list --cask -1') ;;
'list --versions python') echo 'python@3.14 3.14.0' ;;
*) exit 2 ;;
esac''')
        result = self.run_installer('--check')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_apt_ignores_brew_and_batches_installation(self):
        self.ubuntu()
        self.package('alpha', 'one\nshared\n')
        self.package('beta', 'two\nshared\n')
        self.installed.write_text('one\n')
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text(), 'update\ninstall -y shared two\n')

    def test_apt_check_is_read_only(self):
        self.ubuntu()
        self.package('alpha', 'one\n')
        result = self.run_installer('--check')
        self.assertEqual(result.returncode, 1)
        self.assertFalse(self.log.exists())

    def test_unavailable_apt_package_does_not_install(self):
        self.ubuntu()
        self.package('alpha', 'unavailable\n')
        self.stub('apt-cache', 'echo "  Candidate: (none)"')
        result = self.run_installer()
        self.assertEqual(result.returncode, 1)
        self.assertIn('No APT candidate: unavailable', result.stderr)
        self.assertEqual(self.log.read_text(), 'update\n')

    def test_install_failure_is_propagated(self):
        self.package('alpha', 'one\n')
        self.stub('brew', '[[ $1 != install ]] || exit 42')
        self.assertEqual(self.run_installer().returncode, 42)

    def test_setup_receives_check_mode(self):
        self.package('alpha', 'one\n')
        self.installed.write_text('one\n')
        (self.repo / 'configs/alpha/setup/install.sh').write_text('[[ $1 == check ]]\n')
        self.assertEqual(self.run_installer('--check').returncode, 0)

    def test_fzf_capability_failure(self):
        self.package('fish', 'fish\n')
        self.installed.write_text('fish\n')
        for command in ('fish', 'fzf', 'lsd', 'direnv', 'nvim', 'starship', 'bat'):
            self.stub(command, 'exit 0')
        result = self.run_installer('--check')
        self.assertEqual(result.returncode, 1)
        self.assertIn('fzf needs --fish support', result.stderr)

    def test_ubuntu_uses_batcat(self):
        self.ubuntu()
        self.package('fish', 'fish\n')
        self.installed.write_text('fish\n')
        for command in ('fish', 'lsd', 'direnv', 'nvim', 'starship', 'batcat'):
            self.stub(command, 'exit 0')
        self.stub('fzf', "echo --fish")
        result = self.run_installer('--check')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_tmux_plugin_entry_names(self):
        root = self.repo / 'configs/tmux'
        config = root / '.config/tmux'
        config.mkdir(parents=True)
        (root / 'setup').mkdir()
        shutil.copy2(ROOT / 'configs/tmux/setup/install.sh', root / 'setup')
        (config / 'tmux.conf').write_text(
            "set -g @plugin 'tmux-plugins/tpm'\n"
            "set -g @plugin 'tmux-plugins/tmux-resurrect'\n"
            "set -g @plugin 'tmux-plugins/tmux-continuum'\n")
        for name, entry in [('tpm', 'tpm'), ('tmux-resurrect', 'resurrect.tmux'),
                            ('tmux-continuum', 'continuum.tmux')]:
            directory = self.home / '.config/tmux/plugins' / name
            directory.mkdir(parents=True)
            (directory / entry).write_text('plugin\n')
        result = subprocess.run(['/bin/bash', str(root / 'setup/install.sh'), 'check'],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_vscode_check_does_not_install_extensions(self):
        root = self.repo / 'configs/vscode'
        config = root / '.config/vscode'
        config.mkdir(parents=True)
        (root / 'setup').mkdir()
        shutil.copy2(ROOT / 'configs/vscode/setup/install.sh', root / 'setup')
        (config / 'extensions.txt').write_text('publisher.installed\npublisher.missing\n')
        self.stub('code', '''
if [[ $1 == --list-extensions ]]; then echo Publisher.Installed; else echo "$*" >> "$LOG"; fi
''')
        result = subprocess.run(['/bin/bash', str(root / 'setup/install.sh'), 'check'],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('publisher.missing', result.stderr)
        self.assertNotIn('Missing VS Code extension: publisher.installed', result.stderr)
        self.assertFalse(self.log.exists())

    def test_broken_links_are_not_counted(self):
        self.package('alpha', 'one\n')
        target = self.home / '.config/alpha/config'
        target.unlink()
        target.symlink_to(self.base / 'missing')
        result = self.run_installer('--check')
        self.assertIn('No linked configs', result.stdout)
        self.assertFalse(self.log.exists())

    @unittest.skipUnless(shutil.which('stow'), 'Stow is needed for link tests')
    def test_shared_ignore_excludes_setup_directories(self):
        self.package('alpha', 'one\n', linked=False)
        self.package('beta', 'two\n', linked=False)
        shutil.copy2(ROOT / '.stowrc', self.repo)
        (self.repo / 'configs/alpha/.stow-local-ignore').write_text('^local$\n')
        (self.repo / 'configs/alpha/local').write_text('local settings\n')
        (self.repo / 'configs/beta/.DS_Store').write_text('metadata\n')
        result = subprocess.run(
            [shutil.which('stow'), '--target=' + str(self.home), 'alpha', 'beta'],
            cwd=self.repo, env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in ('alpha', 'beta'):
            self.assertTrue((self.home / '.config' / name / 'config').is_symlink())
        for name in ('setup', 'local', '.DS_Store', 'packages.brew', 'packages.apt'):
            self.assertFalse((self.home / name).exists(), name)

    @unittest.skipUnless(shutil.which('stow'), 'Stow is needed for link tests')
    def test_first_run_suggests_all_configs_without_selecting_any(self):
        for name in ('fish', 'kitty', 'nvim', 'starship', 'tmux', 'vscode'):
            self.package(name, 'never\n', linked=False)
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('stow --simulate fish kitty nvim starship tmux vscode', result.stdout)
        self.assertIn('stow fish kitty nvim starship tmux vscode && ./install.sh', result.stdout)
        self.assertFalse((self.home / '.config').exists())
        self.assertFalse(self.log.exists())
        self.assertIn('Stow already available', result.stdout)

    @unittest.skipUnless(shutil.which('stow'), 'Stow is needed for link tests')
    def test_dependencies_follow_manual_stow_selection(self):
        self.package('alpha', 'one\n', linked=False)
        self.package('unused', 'never\n', linked=False)
        result = subprocess.run([shutil.which('stow'), 'alpha'], cwd=self.repo,
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.stub('stow', 'echo unexpected-stow >> "$LOG"; exit 99')
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text(), 'install one\n')
        self.assertIn('Installed packages: one', result.stdout)
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text(), 'install one\n')
        self.assertIn('already installed', result.stdout)

    def test_partial_links_are_left_untouched(self):
        directory = self.package('alpha', 'one\n')
        (directory / 'second').write_text('second\n')
        subprocess.run([self.git, '-C', str(self.repo), 'add', '.'], check=True)
        result = self.run_installer()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('stow alpha', result.stderr)
        self.assertFalse((self.home / '.config/alpha/second').exists())
        self.assertFalse(self.log.exists())

    def hide_homebrew(self):
        (self.bin / 'brew').rename(self.base / 'brew-template')
        bootstrap = self.repo / 'setup/bootstrap.sh'
        bootstrap.write_text(bootstrap.read_text().replace(
            '/opt/homebrew/bin/brew', str(self.bin / 'brew')).replace(
            '/usr/local/bin/brew', str(self.base / 'absent-brew')))

    def test_missing_homebrew_check_does_not_download(self):
        self.package('alpha', 'one\n')
        self.hide_homebrew()
        self.stub('curl', 'echo download >> "$LOG"; exit 99')
        result = self.run_installer('--check')
        self.assertEqual(result.returncode, 1)
        self.assertIn('Missing Homebrew', result.stderr)
        self.assertFalse(self.log.exists())

    def test_homebrew_bootstrap_failure_stops_installation(self):
        self.package('alpha', 'one\n')
        self.hide_homebrew()
        self.stub('curl', 'printf "exit 17\\n" > "$4"')
        result = self.run_installer()
        self.assertEqual(result.returncode, 17, result.stderr)
        self.assertFalse(self.log.exists())

    def test_homebrew_bootstrap_then_installs_dependencies(self):
        self.package('alpha', 'one\n')
        self.hide_homebrew()
        installer = self.base / 'brew-installer'
        installer.write_text(f'cp "{self.base}/brew-template" "{self.bin}/brew"\n')
        self.env['BREW_INSTALLER'] = str(installer)
        self.stub('curl', 'cp "$BREW_INSTALLER" "$4"')
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text(), 'install one\n')

    def test_missing_stow_is_bootstrapped_without_linked_configs(self):
        self.package('alpha', 'never\n', linked=False)
        (self.bin / 'stow').unlink()
        self.stub('brew', '''
case "$*" in
    'install stow')
        printf 'stow bootstrap\\n' >> "$LOG"
        printf '#!/bin/bash\\nexit 0\\n' > "${LOG%/*}/bin/stow"
        chmod +x "${LOG%/*}/bin/stow" ;;
    'list --formula -1') cat "$INSTALLED" ;;
    'list --cask -1') ;;
    *) exit 2 ;;
esac
''')
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text(), 'stow bootstrap\n')
        self.assertIn('Installed Stow.', result.stdout)
        self.assertIn('No linked configs', result.stdout)
        self.assertIn('--simulate alpha', result.stdout)
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text(), 'stow bootstrap\n')

    def test_first_run_bootstraps_homebrew_and_stow_without_config_dependencies(self):
        self.package('alpha', 'never\n', linked=False)
        (self.bin / 'stow').unlink()
        self.stub('brew', '''
case "$*" in
    shellenv) ;;
    'install stow')
        echo 'install stow' >> "$LOG"
        printf '#!/bin/bash\\nexit 0\\n' > "${LOG%/*}/bin/stow"
        chmod +x "${LOG%/*}/bin/stow" ;;
    *) exit 99 ;;
esac
''')
        self.hide_homebrew()
        installer = self.base / 'brew-installer'
        installer.write_text(f'cp "{self.base}/brew-template" "{self.bin}/brew"\n')
        self.env['BREW_INSTALLER'] = str(installer)
        self.stub('curl', 'cp "$BREW_INSTALLER" "$4"')
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Installed Homebrew.', result.stdout)
        self.assertIn('Installed Stow.', result.stdout)
        self.assertIn('No config dependencies installed.', result.stdout)
        self.assertEqual(self.log.read_text(), 'install stow\n')
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('Installed Homebrew.', result.stdout)
        self.assertEqual(self.log.read_text(), 'install stow\n')

    def test_no_homebrew_needed_when_stow_exists_and_nothing_is_linked(self):
        self.package('alpha', 'never\n', linked=False)
        self.hide_homebrew()
        self.stub('curl', 'echo download >> "$LOG"; exit 99')
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Stow already available.', result.stdout)
        self.assertFalse(self.log.exists())

    def test_ubuntu_bootstraps_stow_without_config_dependencies(self):
        self.ubuntu()
        self.package('alpha', 'never\n', linked=False)
        (self.bin / 'stow').unlink()
        self.stub('apt-get', '''
printf '%s\\n' "$*" >> "$LOG"
if [[ "$*" == 'install -y stow' ]]; then
    printf '#!/bin/bash\\nexit 0\\n' > "${LOG%/*}/bin/stow"
    chmod +x "${LOG%/*}/bin/stow"
fi
''')
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text(), 'update\ninstall -y stow\n')
        self.assertIn('Installed Stow.', result.stdout)
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text(), 'update\ninstall -y stow\n')

    def test_vscode_settings_link_is_idempotent_and_preserves_conflicts(self):
        config = self.package('vscode', '')
        (config / 'settings.json').write_text('{}')
        (config / 'extensions.txt').write_text('publisher.extension\n')
        script = self.repo / 'configs/vscode/setup/install.sh'
        shutil.copy2(ROOT / 'configs/vscode/setup/install.sh', script)
        self.stub('code', 'echo publisher.extension')
        target = self.home / 'Library/Application Support/Code/User/settings.json'
        def run():
            return subprocess.run(['/bin/bash', str(script), 'install'], env=self.env,
                                  text=True, capture_output=True)
        result = run()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(target.samefile(config / 'settings.json'))
        self.assertEqual(run().returncode, 0)
        target.unlink()
        target.write_text('local')
        result = run()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(target.read_text(), 'local')

    def test_nvim_has_no_outer_plugin_installer(self):
        self.assertFalse((ROOT / 'configs/nvim/setup/install.sh').exists())
        self.assertEqual(
            {p.name for p in (ROOT / 'configs/nvim/setup').iterdir()},
            {'packages.apt', 'packages.brew'})



if __name__ == '__main__':
    unittest.main()
