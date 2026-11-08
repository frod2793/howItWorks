#!/usr/bin/env python3
"""PreToolUse JSON regressions; commands are inspected, never executed."""
import json
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


AGENTS = Path(__file__).resolve().parents[1]
HOOK = AGENTS / 'scripts/hooks/protect-agents-dir.sh'
TEMPLATE = AGENTS / 'templates/claude-settings.json'


class ProtectAgentsDirTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / '.agents/scripts').mkdir(parents=True)
        (self.root / '.agents/work-items/active').mkdir(parents=True)
        evidence = self.root / '.agents/work-items/evidence/TASK-1'
        evidence.mkdir(parents=True)
        (evidence / 'revision-0-input-manifest.json').write_text('{}')
        (self.root / '.agents/reports').mkdir(parents=True)
        (self.root / 'nested').mkdir()
        (self.root / 'Assets').mkdir()

    def hook(self, command, cwd=None, shell=None, env=None):
        value = {'tool_name': 'Bash', 'tool_input': {'command': command}}
        if shell is not None:
            value['tool_input']['shell'] = shell
        if cwd is not None:
            value['cwd'] = str(cwd)
        environment = dict(os.environ, CLAUDE_CODE_SHELL=shell, SHELL=shell) if shell else None
        if env is not None:
            environment = dict(environment or os.environ)
            environment.update(env)
        return subprocess.run(['bash', str(HOOK)], input=json.dumps(value), text=True,
                              capture_output=True, cwd=self.root, env=environment)

    def test_cst_control_and_state_edges(self):
        with tempfile.TemporaryDirectory() as safe_root:
            safe = Path(safe_root)
            (safe / 'child').mkdir()
            pairs = (
                (f'cd "{safe}" && rm -rf child', 0),
                (f'cd "{safe}"; rm -rf .', 2),
                ('f() { rm -rf .agents; }; printf ok', 0),
                ('f() { rm -rf .agents; }; f', 2),
                (f'f() {{ rm -rf .; }}; cd "{safe}" && f', 0),
                ('f() { rm -rf .; }; f', 2),
                ('D=.agents; rm -rf \'$D\'', 0),
                ('D=.agents; rm -rf "$D"', 2),
                ("eval 'f() { rm -rf .agents; }'; f", 2),
                ('printf "%s" "$(f() { rm -rf .agents; }; f)"', 2),
                ('if [[ -d .agents && -d Assets ]]; then cat .agents/AGENTS.md; fi', 0),
                ('if [[ -d .agents && -d Assets ]]; then rm -rf .agents; fi', 2),
                ('time cat .agents/AGENTS.md', 0),
                ('time rm -rf .agents', 2),
            )
            for shell in ('bash', 'zsh'):
                for command, expected in pairs:
                    with self.subTest(shell=shell, command=command):
                        self.assertEqual(self.hook(command, shell='/bin/' + shell).returncode,
                                         expected, command)
            for command, expected in (
                ('time -p cat .agents/AGENTS.md', 0),
                ('time -p rm -rf .agents', 2),
                ('time -p\\\n rm -rf .agents', 2),
            ):
                with self.subTest(shell='bash', command=command):
                    self.assertEqual(self.hook(command, shell='/bin/bash').returncode,
                                     expected, command)

    def test_condition_cwd_and_unknown_cwd_reach_writes(self):
        for shell in ('bash', 'zsh'):
            for command, expected in (
                ('if cd .agents; then printf x > AGENTS.md; fi', 2),
                ('while cd .agents; do printf x > AGENTS.md; break; done', 2),
                ('until cd .agents && false; do printf x > AGENTS.md; break; done', 2),
                ('cd "$TARGET"; printf x > AGENTS.md', 2),
                ('cd "$TARGET"; cat AGENTS.md', 0),
                ('if cd Assets; then printf x > product.txt; fi', 0),
                (f'while cd "{self.root / "Assets"}"; do printf x > product.txt; break; done', 0),
                ('case x in x) cd .agents; printf x > AGENTS.md;; esac', 2),
                ('case x in x) cd Assets; printf x > product.txt;; esac', 0),
            ):
                with self.subTest(shell=shell, command=command):
                    self.assertEqual(self.hook(command, shell='/bin/' + shell).returncode,
                                     expected, command)

    def test_direct_writers_share_protected_path_policy(self):
        for command, expected in (
            ('mkdir .agents/scripts/newdir', 2),
            ('touch .agents/scripts/newfile', 2),
            ('truncate -s 0 .agents/AGENTS.md', 2),
            ('mkdir .agents/reports/newdir', 0),
            ('touch .agents/reports/newfile', 0),
            ('truncate -s 0 Assets/product.txt', 0),
            ('touch -r .agents/AGENTS.md Assets/product.txt', 0),
            ('cat .agents/AGENTS.md', 0),
        ):
            with self.subTest(command=command):
                self.assertEqual(self.hook(command).returncode, expected, command)

    def test_cd_argv_and_home_directory_state(self):
        for command, env, expected in (
            ('cd -- .agents; printf x > AGENTS.md', {}, 2),
            ('cd -P .agents; printf x > AGENTS.md', {}, 2),
            ('cd -L .agents; printf x > AGENTS.md', {}, 2),
            ('cd; printf x > AGENTS.md', {'HOME': str(self.root / '.agents')}, 2),
            ('cd -; printf x > AGENTS.md', {'OLDPWD': str(self.root / '.agents')}, 2),
            ('cd -- Assets && printf x > product.txt', {}, 0),
            ('cd -P Assets && printf x > product.txt', {}, 0),
            ('cd; cat AGENTS.md', {'HOME': str(self.root / '.agents')}, 0),
            ('cd -; cat AGENTS.md', {'OLDPWD': str(self.root / '.agents')}, 0),
        ):
            with self.subTest(command=command):
                self.assertEqual(self.hook(command, env=env).returncode, expected, command)

    def test_explicit_writer_destinations_from_814(self):
        subprocess.run(['/usr/bin/git', 'init', '-q', str(self.root)], check=True,
                       env=dict(os.environ, HOME=str(self.root),
                                GIT_CONFIG_GLOBAL='/dev/null',
                                GIT_CONFIG_SYSTEM='/dev/null',
                                GIT_CONFIG_NOSYSTEM='1'))
        (self.root / '.git/info/sparse-checkout').write_text('/*\n')
        for command, expected in (
            ('unlink .agents/AGENTS.md', 2),
            ('dd if=/dev/null of=.agents/AGENTS.md', 2),
            ('curl -so .agents/AGENTS.md file:///tmp/input', 2),
            ('curl --output=.agents/AGENTS.md file:///tmp/input', 2),
            ('git format-patch -o .agents -1', 2),
            ('find . -name .agents -exec rm -rf {} +', 2),
            ('find Assets -exec rm -rf .agents +', 2),
            ('tar -xf /tmp/input.tar -C .agents/work-items/evidence/TASK-1', 2),
            ('tar xf /tmp/input.tar -C .git/info', 2),
            ('unzip -o /tmp/input.zip -d .agents/work-items/evidence/TASK-1', 2),
            ('unzip -o /tmp/input.zip -d .git/info', 2),
            ('ditto -x -k /tmp/input.zip .agents/work-items/evidence/TASK-1', 2),
            ('ditto -x -k /tmp/input.zip .git/info', 2),
            ('git clone /tmp/source .agents', 2),
            ('unlink Assets/product.txt', 0),
            ('dd if=/dev/null of=Assets/product.txt', 0),
            ('curl -o Assets/product.txt file:///tmp/input', 0),
            ('git format-patch -o Assets -1', 0),
            ('find Assets -name product -exec rm {} +', 0),
            ('tar -xf /tmp/input.tar -C Assets', 0),
            ('tar xf /tmp/input.tar -C Assets', 0),
            ('unzip -o /tmp/input.zip -d Assets', 0),
            ('ditto -x -k /tmp/input.zip Assets', 0),
            ('ditto -c -k Assets /tmp/output.zip', 0),
            ('git clone /tmp/source Assets/new', 0),
        ):
            with self.subTest(command=command):
                self.assertEqual(self.hook(command).returncode, expected, command)

    def test_patch_consumers_check_paths_without_applying(self):
        product = self.root / 'product.patch'
        product.write_text('diff --git a/Assets/product.txt b/Assets/product.txt\n'
                           '--- a/Assets/product.txt\n+++ b/Assets/product.txt\n'
                           '@@ -0,0 +1 @@\n+ok\n')
        protected = self.root / 'protected.patch'
        protected.write_text('diff --git a/.agents/AGENTS.md b/.agents/AGENTS.md\n'
                             '--- a/.agents/AGENTS.md\n+++ b/.agents/AGENTS.md\n'
                             '@@ -0,0 +1 @@\n+bad\n')
        renamed = self.root / 'renamed.patch'
        renamed.write_text('diff --git a/Assets/product.txt b/.agents/AGENTS.md\n'
                           'similarity index 100%\nrename from Assets/product.txt\n'
                           'rename to .agents/AGENTS.md\n')
        (self.root / '--apply').write_bytes(product.read_bytes())
        for command, expected in (
            (f'git apply {product}', 0),
            (f'git apply {protected}', 2),
            (f'git apply -R {protected}', 2),
            (f'git apply {renamed}', 2),
            (f'git apply -R {renamed}', 2),
            (f'git apply --include=Assets/* {product}', 0),
            (f'git apply --include=Assets/* {protected}', 2),
            (f'git apply --stat --apply {product}', 0),
            (f'git apply --check --no-check {protected}', 2),
            (f'git apply --check --no-check {product}', 0),
            (f'git apply --no-check --check {protected}', 0),
            (f'git apply --check --appl {protected}', 2),
            (f'git apply --check --no-chec {protected}', 2),
            (f'git apply --stat --no-sta {protected}', 2),
            (f'git apply --numstat --no-nums {protected}', 2),
            (f'git apply --summary --no-summ {protected}', 2),
            ('git apply -- --apply', 0),
            (f'git apply --numstat {protected}', 0),
            (f'git apply --check {protected}', 0),
            ('git apply /tmp/missing.patch', 2),
            ('git apply', 2),
            ('git am /tmp/missing.mbox', 2),
            ('patch -p1 < /tmp/missing.patch', 2),
            ('patch --dry-run -p1 < /tmp/missing.patch', 0),
        ):
            with self.subTest(command=command):
                self.assertEqual(self.hook(command).returncode, expected, command)

    def test_git_worktree_redirect_and_index_hiding(self):
        for command, expected in (
            ('git config core.worktree /tmp/other', 2),
            ('git config --get core.worktree', 0),
            ('git config user.name Example', 0),
            ('git update-index --skip-worktree .agents/AGENTS.md', 2),
            ('git update-index --assume-unchanged .agents/AGENTS.md', 2),
            ('git update-index --no-skip-worktree .agents/AGENTS.md', 0),
            ('git update-index --skip-worktree Assets/product.txt', 0),
        ):
            with self.subTest(command=command):
                self.assertEqual(self.hook(command).returncode, expected, command)

    def test_git_c_option_resolves_output_in_command_cwd(self):
        for command, expected in (
            ('git -C .agents clone /tmp/source scripts/new', 2),
            ('git -C .agents format-patch -o scripts -1', 2),
            ('git -C Assets clone /tmp/source new', 0),
            ('git -C .agents format-patch -o reports -1', 0),
        ):
            with self.subTest(command=command):
                self.assertEqual(self.hook(command).returncode, expected, command)

    def test_git_apply_and_default_outputs_use_command_cwd(self):
        subprocess.run(['/usr/bin/git', 'init', '-q', str(self.root)], check=True,
                       env=dict(os.environ, HOME=str(self.root),
                                GIT_CONFIG_GLOBAL='/dev/null',
                                GIT_CONFIG_SYSTEM='/dev/null',
                                GIT_CONFIG_NOSYSTEM='1'))
        with tempfile.TemporaryDirectory() as outside:
            product = self.root / 'product.patch'
            product.write_text('diff --git a/Assets/product.txt b/Assets/product.txt\n'
                               '--- a/Assets/product.txt\n+++ b/Assets/product.txt\n'
                               '@@ -0,0 +1 @@\n+ok\n')
            protected = self.root / 'protected.patch'
            protected.write_text('diff --git a/.agents/AGENTS.md b/.agents/AGENTS.md\n'
                                 '--- a/.agents/AGENTS.md\n+++ b/.agents/AGENTS.md\n'
                                 '@@ -0,0 +1 @@\n+bad\n')
            for command, expected in (
                (f'git --git-dir={self.root / ".git"} --work-tree={outside} apply {protected}', 2),
                (f'git --git-dir={self.root / ".git"} --work-tree={outside} apply {product}', 0),
                (f'git --git-dir={self.root / ".git"} --work-tree={outside} am /tmp/mailbox', 2),
                ('git -C .agents clone /tmp/source', 2),
                ('git -C Assets clone /tmp/source', 0),
                ('git -C .agents format-patch HEAD~1', 2),
                ('git -C .agents format-patch --stdout HEAD~1', 0),
                ('git -C Assets format-patch HEAD~1', 0),
            ):
                with self.subTest(command=command):
                    self.assertEqual(self.hook(command).returncode, expected, command)

    def test_line_continuation_in_cst_words(self):
        for shell in ('bash', 'zsh'):
            for command, expected in (
                ('r\\\nm -rf .agents', 2),
                ('rm -rf .age\\\nnts', 2),
                ('ti\\\nme { rm -rf .agents; }', 2),
                ('R=r\\\nm; $R -rf .agents', 2),
                ('R="r\\\nm"; $R -rf .agents', 2),
                ('rm -rf ".age\\\nnts"', 2),
                ('pri\\\nntf ok > Assets/product.txt', 0),
                ('echo "r\\\nm" > Assets/product.txt', 0),
                ("echo 'r\\\nm' > Assets/product.txt", 0),
                ('echo "$(r\\\nm -rf .agents)"', 2),
                ('echo ok # comment\\\nrm -rf .agents', 2),
                ('echo ok # comment\\\ncat .agents/AGENTS.md', 0),
                ("cat <<'EOF'\nr\\\nm\nEOF", 0),
                ('cat <<EOF\nr\\\nm\nEOF', 2),
                ('printf ok' + '\\' * 2 + '\nrm -rf .agents', 2),
                ('printf ok' + '\\' * 2 + '\ncat .agents/AGENTS.md', 0),
            ):
                with self.subTest(shell=shell, command=command):
                    self.assertEqual(self.hook(command, shell='/bin/' + shell).returncode,
                                     expected, command)

    def test_heredoc_shell_consumer_boundary(self):
        for consumer, body, expected in (
                ('sh', 'rm -rf .agents', 2),
                ('dash', 'rm -rf .agents', 2),
                ('ksh', 'rm -rf .agents', 2),
                ('sh', 'printf ok', 2),
                ('bash', 'rm -rf .agents', 2),
                ('zsh', 'rm -rf .agents', 2),
                ('bash', 'printf ok', 0),
                ('zsh', 'printf ok', 0),
                ('cat', 'rm -rf .agents', 0)):
            command = "%s <<'EOF'\n%s\nEOF" % (consumer, body)
            with self.subTest(command=command):
                self.assertEqual(self.hook(command).returncode, expected, command)
        for command, expected in (
                ("env bash <<'EOF'\nrm -rf .agents\nEOF", 2),
                ("command sh <<'EOF'\nrm -rf .agents\nEOF", 2),
                ("bash <<-'EOF'\nrm -rf .agents\nEOF", 2),
                ("bash <<-'EOF'\nprintf ok\nEOF", 0),
                ("bash <<< 'rm -rf .agents'", 2),
                ("zsh <<< 'rm -rf .agents'", 2),
                ("bash -s <<< 'rm -rf .agents'", 2),
                ("bash <<< 'printf ok'", 0),
                ("bash -c 'printf ok' <<< 'rm -rf .agents'", 0),
                ("bash <<< 'printf ok'; sh", 0),
                ("cat <<< 'rm -rf .agents'", 0),
                ("bash <<< '$UNKNOWN'", 2),
                ("bash %s <<'EOF'\nrm -rf .agents\nEOF" %
                 (AGENTS / 'scripts/hooks/protect-agents-dir.sh'), 0),
                ("f(){ bash; }; f <<'EOF'\nrm -rf .agents\nEOF", 2),
                ("bash -c 'bash' <<'EOF'\nrm -rf .agents\nEOF", 2),
                ("bash -c 'read header; bash' <<'EOF'\nHEADER\nrm -rf .agents\nEOF", 2),
                ("eval 'bash' <<'EOF'\nrm -rf .agents\nEOF", 2),
                ("f(){ cat; }; f <<'EOF'\nrm -rf .agents\nEOF", 0),
                ("f(){ printf ok; cat; }; f <<'EOF'\nrm -rf .agents\nEOF", 0),
                ("bash <<'EOF'\nprintf ok\nEOF\ncat .agents/AGENTS.md", 0)):
            with self.subTest(command=command):
                self.assertEqual(self.hook(command).returncode, expected, command)

    def test_unquoted_command_name_field_splitting(self):
        for command, expected in (
                ("R='rm -rf'; $R .agents", 2),
                ("R='rm -rf'; \"$R\" .agents", 0),
                ("R='rm'; $R -rf .agents", 2),
                ("R='cat'; $R .agents/AGENTS.md", 0),
                ("R=rm; R=cat $R -rf .agents", 2),
                ("R=cat; R=rm $R .agents/AGENTS.md", 0),
                ("R=cat; f(){ $R -rf .agents; }; R=rm f", 2),
                ("R=rm; f(){ cat .agents/AGENTS.md; }; R=cat f; $R -rf .agents", 2),
                ("R=rm; R=cat cd .; $R -rf .agents", 2),
                ("R=rm; R=cat export X=1; $R -rf .agents", 2),
                ("R=cat; R=rm cd .; $R .agents/AGENTS.md", 0),
                ("IFS=:; R='rm:-rf'; $R .agents", 2),
                ("IFS=$UNKNOWN; R='rm -rf'; $R .agents", 2),
                ("IFS=''; R='rm -rf'; $R .agents", 0),
                ("IFS=:; R='cat:file'; \"$R\" .agents/AGENTS.md", 0),
                ("D='safe .agents'; rm -rf $D", 2),
                ("D='safe .agents'; command rm -rf $D", 2),
                ("D='safe .agents'; env rm -rf $D", 2),
                ("D='safe .agents'; sudo -u root rm -rf $D", 2),
                ("R='rm -rf'; command $R .agents", 2),
                ("V='x rm -rf .agents'; env A=$V true", 2),
                ("V='x rm -rf .agents'; sudo -u $V true", 2),
                ("V='x printf OK'; env A=\"$V\" true", 0),
                ("D='safe .agents'; command rm -rf \"$D\"", 0),
                ("D='safe .agents'; env cat $D", 0),
                ("D='safe .agents'; cat $D", 0),
                ("R=rm bash -c '$R -rf .agents'", 2),
                ("R=rm; eval '$R -rf .agents'", 2)):
            with self.subTest(command=command):
                self.assertEqual(self.hook(command).returncode, expected, command)

    def test_missing_native_parser_fails_closed_with_actionable_message(self):
        with tempfile.TemporaryDirectory() as temporary:
            hook_dir = Path(temporary) / '.agents/scripts/hooks'
            hook_dir.mkdir(parents=True)
            source_dir = AGENTS / 'scripts/hooks'
            shutil.copy2(source_dir / 'protect-agents-dir.py', hook_dir)
            shutil.copy2(source_dir / 'shell_cst.py', hook_dir)
            payload = {'tool_name': 'Bash', 'cwd': str(self.root),
                       'tool_input': {'command': 'cat .agents/AGENTS.md'}}
            result = subprocess.run(['/usr/bin/python3', str(hook_dir / 'protect-agents-dir.py')],
                                    input=json.dumps(payload), text=True, capture_output=True,
                                    cwd=self.root)
            self.assertEqual(result.returncode, 2)
            self.assertIn('셸 파서 패키지', result.stderr)

    def test_cst_reported_control_forms(self):
        shared = (
            ('while rm -rf .agents; do break; done', 2),
            ('until rm -rf .agents; do break; done', 2),
            ('while cat .agents/AGENTS.md; do break; done', 0),
            ('function f()\n{\n cat .agents/AGENTS.md\n}\nf', 0),
            ('function f()\n{\n rm -rf .agents\n}\nf', 2),
        )
        zsh_only = (
            ('{ true; } always { rm -rf .agents; }', 2),
            ('{ true; } always { cat .agents/AGENTS.md; }', 0),
            ('if [[ -d .agents ]] rm -rf .agents', 2),
            ('if [[ -d .agents ]] cat .agents/AGENTS.md', 0),
            ('while [[ 1 ]] { rm -rf .agents; break }', 2),
        )
        for shell in ('bash', 'zsh'):
            for command, expected in shared + (zsh_only if shell == 'zsh' else ()):
                with self.subTest(shell=shell, command=command):
                    self.assertEqual(self.hook(command, shell='/bin/' + shell).returncode,
                                     expected, command)

    def test_git_config_alias_output_and_budget(self):
        home = self.root / 'home'
        xdg = self.root / 'xdg'
        home.mkdir(); xdg.mkdir()
        isolated = {'HOME': str(home), 'XDG_CONFIG_HOME': str(xdg),
                    'GIT_CONFIG_GLOBAL': '/dev/null', 'GIT_CONFIG_SYSTEM': '/dev/null',
                    'GIT_CONFIG_NOSYSTEM': '1'}
        subprocess.run(['/usr/bin/git', 'init', '-q', str(self.root)],
                       check=True, env=dict(os.environ, **isolated))
        for command in (
            "git config --replace-all alias.sc2 'sparse-checkout set Assets' '.*'",
            'git config --rename-section x alias',
            'git show --output=.agents/AGENTS.md',
            'git range-diff --output=.agents/AGENTS.md HEAD HEAD HEAD',
        ):
            with self.subTest(blocked=command):
                self.assertEqual(self.hook(command, env=isolated).returncode, 2)
        self.assertEqual(self.hook('git show --output=Assets/show.txt', env=isolated).returncode, 0)

    def tool(self, name, tool_input):
        return subprocess.run(['bash', str(HOOK)], input=json.dumps({'tool_name': name, 'tool_input': tool_input}),
                              text=True, capture_output=True, cwd=self.root)

    def test_adversarial_report_execution_forms(self):
        commands = (
            'exec rm -rf .agents', 'timeout 5 rm -rf .agents', 'nice rm -rf .agents',
            'stdbuf -o0 rm -rf .agents', 'caffeinate rm -rf .agents',
            'arch -arm64 rm -rf .agents', 'xcrun rm -rf .agents',
            'busybox rm -rf .agents', 'doas rm -rf .agents', "builtin eval 'rm -rf .agents'",
            "bash --norc -c 'rm -rf .agents'", "sh -c -- 'rm -rf .agents'",
            "dash -c 'rm -rf .agents'", "ksh -c 'rm -rf .agents'",
            "echo 'rm -rf .agents' | bash", "printf 'rm -rf .agents\\n' | sh",
            "echo 'rm -rf .agents' > /tmp/x.sh; bash /tmp/x.sh", 'source /tmp/x.sh',
            'f(){ rm -rf .agents; }; f', 'function f { rm -rf .agents; }; f',
            'rm -rf .{agents,x}', 'rm -rf {.agents,x}',
            'git rm -r .agents', 'git rm -rf --cached .agents', 'git mv .agents x',
            'git checkout .', 'git checkout .agents', 'git checkout HEAD .agents',
            'git checkout -f other', 'git switch -f other', 'git switch --discard-changes other',
            'git worktree remove .', 'git checkout-index -a -f', 'git read-tree -u --reset HEAD',
            'git --work-tree=. checkout .', 'git clean -fdx -e foo',
            'git clean -fdxe foo', 'git clean -fdx :/',
        )
        for command in commands:
            with self.subTest(command=command):
                self.assertEqual(self.hook(command).returncode, 2, command)

    def test_input_manifest_is_protected_but_evidence_remains_writable(self):
        manifest = '.agents/work-items/evidence/TASK-1/revision-0-input-manifest.json'
        self.assertEqual(self.hook('python3 .agents/scripts/shared/change-id.py --manifest . > ' + manifest).returncode, 2)
        self.assertEqual(self.tool('Write', {'file_path': manifest, 'content': '{}'}).returncode, 2)
        self.assertEqual(self.tool('apply_patch', {'patch': '*** Begin Patch\n*** Add File: ' + manifest + '\n+{}\n*** End Patch'}).returncode, 2)
        self.assertEqual(self.tool('Write', {'file_path': '.agents/work-items/evidence/TASK-1/revision-0.conf', 'content': 'ok'}).returncode, 0)

    def test_adversarial_safe_paths(self):
        for command in ('exec cat .agents/AGENTS.md', 'timeout 5 cat .agents/AGENTS.md',
                        f'bash {AGENTS}/scripts/workflow/work-harness.sh status --project-root . --task TASK-1',
                        'find Assets -name "*.meta" -print0 | xargs -0 cat',
                        'echo done > Assets/result.txt'):
            with self.subTest(command=command):
                self.assertEqual(self.hook(command).returncode, 0, command)

    def test_git_global_work_tree_from_outside_cwd(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            project = root / 'project'
            outside = root / 'outside'
            (project / '.agents').mkdir(parents=True)
            outside.mkdir()
            subprocess.run(['git', 'init', '-q', str(project)], check=True, capture_output=True)
            worktree = str(project)
            gitdir = str(project / '.git')

            def inspect(command):
                payload = {'tool_name': 'Bash', 'cwd': str(outside),
                           'tool_input': {'command': command}}
                return subprocess.run(['bash', str(HOOK)], input=json.dumps(payload), text=True,
                                      capture_output=True, cwd=outside).returncode

            for command in (
                f'git --work-tree={worktree} --git-dir={gitdir} checkout .',
                f'git --work-tree {worktree} checkout .',
                f'git -C {project} --work-tree=. checkout .',
                f'GIT_WORK_TREE={worktree} git checkout .',
                f'env GIT_WORK_TREE={worktree} git checkout .',
                f'D={worktree}; git --work-tree=$D checkout .',
                'git --work-tree=$UNKNOWN checkout .',
                f'git --git-dir={gitdir} checkout .',
                f'git --git-dir={gitdir} sparse-checkout set Assets',
                f'git --work-tree={worktree} --git-dir={gitdir} sparse-checkout set Assets',
                'git --git-dir=$UNKNOWN checkout .',
                f'GIT_DIR={gitdir} git checkout .',
                'GIT_DIR=$UNKNOWN git checkout .',
            ):
                with self.subTest(command=command):
                    self.assertEqual(inspect(command), 2, command)
            self.assertEqual(inspect(f'git --work-tree={worktree} status --short'), 0)
            self.assertEqual(inspect(f'git --git-dir={gitdir} status --short'), 0)
            self.assertEqual(inspect(f'git --git-dir={gitdir} sparse-checkout list'), 0)

    def test_third_review_direct_and_indirect_writes(self):
        manifest = '.agents/work-items/evidence/TASK-1/revision-0-input-manifest.json'
        commands = (
            'ln -sf /tmp/ok.py .agents/scripts/hooks/protect-agents-dir.py',
            'ln /tmp/e.sh .agents/scripts/e.sh',
            'ln -f /tmp/x .agents/AGENTS.md',
            'ln -t.agents/scripts /tmp/x',
            'ln --target-directory=.agents/scripts /tmp/x',
            f'ln {manifest} /tmp/h', f'ln -s {manifest} /tmp/l2; echo x > /tmp/l2',
            f'cp /tmp/{Path(manifest).name} .agents/work-items/evidence/TASK-1/',
            f'mv /tmp/{Path(manifest).name} .agents/work-items/evidence/TASK-1/',
            f'rsync -a /tmp/{Path(manifest).name} .agents/work-items/evidence/TASK-1/',
            'mv .agents/work-items/evidence/TASK-1 /tmp/stash',
            'cp -r /tmp/stash .agents/work-items/evidence/TASK-1',
            'nice -n 5 rm -rf .agents', 'timeout -s KILL 5 rm -rf .agents',
            'nice -n5 rm -rf Assets/../.agents',
            'nice --adjustment=5 rm -rf Assets/../.agents',
            'sudo -g staff rm -rf .agents', 'exec -a foo rm -rf .agents',
            'stdbuf -o0 rm -rf Assets/../.agents',
            "$'rm' -rf .agents", 'R=rm; $R -rf .agents',
            'IFS=,; c=rm,-rf,.agents; $c',
            'ls -A | grep -i agents | xargs rm -rf',
            "ls -A | grep -i agents | xargs -I{} sh -c 'rm -rf {}'",
            'parallel rm -rf ::: .agents', 'watch -n1 rm -rf .agents',
            'script -q /dev/null rm -rf .agents',
            'git restore --source=HEAD :/', 'git checkout HEAD -- :/',
            "git checkout -- ':(top)'", 'git stash',
            'git checkout -fq other', 'git checkout-index -fa',
            f'git checkout-index -f -- {manifest}',
            "git -c alias.x='reset --hard' x",
            f'echo x > ${{D:-.agents}}/work-items/evidence/TASK-1/{Path(manifest).name}',
            f'echo x > "$(printf %s {manifest})"',
            'cp /tmp/x "${D:-.agents/AGENTS.md}"',
            'ln /tmp/x "${D:-.agents/AGENTS.md}"',
            'mv /tmp/x "${D:-.agents/AGENTS.md}"',
            'rsync -a /tmp/x "${D:-.agents/AGENTS.md}"',
            'env --chdir=. rm -rf Assets/../.agents',
        )
        for command in commands:
            with self.subTest(command=command):
                self.assertEqual(self.hook(command).returncode, 2, command)
        for command in ('git stash list', "git -c alias.x='reset --hard' status",
                        'nice -n5 cat .agents/AGENTS.md',
                        'ln /tmp/a Assets/product-link', 'cp -r /tmp/input Assets/product-dir',
                        'cp /tmp/review.md .agents/work-items/evidence/TASK-1/',
                        'mv /tmp/review.md .agents/work-items/evidence/TASK-1/',
                        'ln /tmp/review.md .agents/work-items/evidence/TASK-1/',
                        'rsync -a /tmp/review.md .agents/work-items/evidence/TASK-1/'):
            with self.subTest(allowed=command):
                self.assertEqual(self.hook(command).returncode, 0, command)

    def test_third_review_export_pushd_and_git_pathspec_from_outside(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            project = root / 'project'; outside = root / 'outside'
            (project / '.agents').mkdir(parents=True); outside.mkdir()
            subprocess.run(['git', 'init', '-q', str(project)], check=True, capture_output=True)
            commands = (
                f'export GIT_WORK_TREE={project} GIT_DIR={project / ".git"}; git checkout .',
                f'pushd {project}; git reset --hard',
                f'git -C {project} restore :/',
            )
            for command in commands:
                with self.subTest(command=command):
                    payload = {'tool_name': 'Bash', 'cwd': str(outside), 'tool_input': {'command': command}}
                    result = subprocess.run(['bash', str(HOOK)], input=json.dumps(payload), text=True,
                                            capture_output=True, cwd=outside)
                    self.assertEqual(result.returncode, 2, command)

    def test_control_flow_and_dynamic_protected_writes_fail_closed(self):
        for command in (
            'for p in .agents; do rm -rf "$p"; done',
            'if true; then rm -rf .agents; fi',
            '{ rm -rf .agents; }',
            'printf "%s\\n" .agents | xargs rm -rf',
            'printf "%s\\n" .agents | xargs -I{} rm -rf {}',
            'eval "rm -rf .agents"',
            'echo `rm -rf .agents`',
            'bash -lc "rm -rf .agents"',
            'bash -lc "$DYNAMIC_CODE"',
            'rm -rf .ag*',
            'rm -rf .AGENTS',
            'git restore -- .agents',
            'git reset --hard',
            'git stash -u',
            'git checkout -- .agents',
            'env -i rm -rf .agents',
            'command -- rm -rf .agents',
            'time rm -rf .agents',
        ):
            with self.subTest(command=command):
                self.assertEqual(self.hook(command).returncode, 2, command)
        ancestor_glob = f'cd .. && rm -rf {self.root.name[:-2]}*'
        self.assertEqual(self.hook(ancestor_glob).returncode, 2, ancestor_glob)
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True, capture_output=True)
        for command in ('git reset --hard', 'git stash -u', 'git -C . reset --hard'):
            with self.subTest(nested_git=command):
                self.assertEqual(self.hook(command, self.root / 'Assets').returncode, 2, command)

    def test_dynamic_reads_and_product_writes_remain_allowed(self):
        for command in (
            'if true; then cat .agents/AGENTS.md; fi',
            'for p in .agents/docs/*.md; do cat "$p"; done',
            'echo "rm -rf .agents"',
            'echo done > Assets/result.txt',
            'bash -lc "cat .agents/AGENTS.md"',
            'bash -lc \'cat "$HOME/.agents/AGENTS.md"\'',
            'env -i cat .agents/AGENTS.md',
            'command -- cat .agents/AGENTS.md',
            'time cat .agents/AGENTS.md',
        ):
            with self.subTest(command=command):
                self.assertEqual(self.hook(command).returncode, 0, command)
        self.assertEqual(self.hook('echo "`rm -rf .agents`"').returncode, 2)

    def test_nested_cwd_template_launcher_finds_hook_or_denies(self):
        template = json.loads(TEMPLATE.read_text())
        command = template['hooks']['PreToolUse'][0]['hooks'][0]['command']
        payload = json.dumps({'tool_name': 'Bash', 'tool_input': {'command': 'rm -rf ../..'}})
        env = {**os.environ, 'CLAUDE_PROJECT_DIR': str(AGENTS.parent)}
        result = subprocess.run(['bash', '-c', command], input=payload, text=True,
                                capture_output=True, cwd=AGENTS / 'scripts', env=env)
        self.assertEqual(result.returncode, 2, result.stderr)
        readable = json.dumps({'tool_name': 'Bash', 'tool_input': {'command': 'cat ../AGENTS.md'}})
        result = subprocess.run(['bash', '-c', command], input=readable, text=True,
                                capture_output=True, cwd=AGENTS / 'scripts', env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = subprocess.run(['bash', '-c', command], input=payload, text=True,
                                capture_output=True, cwd=self.root / 'nested')
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertNotEqual(result.returncode, 127)
        fake = self.root / 'Packages/pkg/.agents/scripts/hooks/protect-agents-dir.sh'
        fake.parent.mkdir(parents=True)
        fake.write_text('#!/bin/bash\nexit 0\n')
        result = subprocess.run(['bash', '-c', command], input=payload, text=True,
                                capture_output=True, cwd=fake.parent, env=env)
        self.assertEqual(result.returncode, 2, result.stderr)

    def test_fourth_review_dynamic_links_git_ditto_and_xargs(self):
        manifest = '.agents/work-items/evidence/TASK-1/revision-0-input-manifest.json'
        (self.root / 'logs').mkdir()
        (self.root / 'logs/review.md').write_text('review')
        (self.root / 'forged').mkdir()
        (self.root / 'forged/revision-0-input-manifest.json').write_text('forged')
        (self.root / 'args.txt').write_text('.agents\n')
        blocked = (
            '`echo rm` -rf .agents', '`printf rm` -rf .agents',
            f'echo PWNED > `printf %s {manifest}`',
            f'cp -l {manifest} /tmp/hardlink',
            f'cp --link {manifest} /tmp/hardlink',
            'cp -al .agents/work-items/evidence/TASK-1 /tmp/hardlinks',
            f'rsync -a --link-dest={self.root / manifest.rsplit("/", 1)[0]} /tmp/other/ /tmp/output/',
            'rsync -a --link-dest=../.agents/work-items/evidence/TASK-1 /tmp/other/ output/',
            "git restore ':(exclude)Assets'", "git restore ':(glob)**'",
            "git checkout -- ':!Assets'", "git checkout -- ':^Assets'",
            'git sparse-checkout set Assets', 'git sparse-checkout add Assets',
            'git sparse-checkout reapply', 'git sparse-checkout init',
            f'ditto /tmp/{Path(manifest).name} {manifest}',
            'ditto forged .agents/work-items/evidence/TASK-1',
            'xargs -a args.txt rm -rf', 'xargs --arg-file=args.txt rm -rf',
            'xargs --arg-file args.txt rm -rf', 'xargs -aargs.txt rm -rf',
            'xargs -a args.txt ln -f /tmp/x',
            'xargs -a args.txt rsync -a /tmp/x',
            'rsync -a --link-dest="${D:-../.agents/work-items/evidence/TASK-1}" /tmp/other/ Assets/',
            "git clean -fdx ':(glob).agents/**'", "git clean -fdx ':(top).agents'",
            'cp -R forged .agents/work-items/evidence/TASK-1/',
            'mv forged .agents/work-items/evidence/TASK-1/',
        )
        for command in blocked:
            with self.subTest(blocked=command):
                self.assertEqual(self.hook(command).returncode, 2, command)
        allowed = (
            'cp -R logs/ .agents/work-items/evidence/TASK-1/',
            'mv logs .agents/work-items/evidence/TASK-1/',
            'ditto logs .agents/work-items/evidence/TASK-1/logs',
            'rsync -a logs/ .agents/work-items/evidence/TASK-1/logs/',
            f'cp {manifest} Assets/manifest-backup.json',
            'git sparse-checkout list',
            'xargs -a args.txt cat',
            'echo done > Assets/result.txt',
            'cat .agents/AGENTS.md',
        )
        for command in allowed:
            with self.subTest(allowed=command):
                self.assertEqual(self.hook(command).returncode, 0, command)

    def test_filtered_harness_rsync_preserves_managed_update(self):
        filters = ('--exclude=config/project-profile.conf --exclude=reports/ '
                   '--exclude=work-items/ --exclude=artifacts/ '
                   '--exclude=docs/exec-plans/ --exclude=docs/product-specs/ '
                   '--exclude=docs/troubleshooting/')
        self.assertEqual(self.hook(f'rsync -a --delete {filters} source/ .agents/').returncode, 0)
        self.assertEqual(self.hook('rsync -a --delete source/ .agents/').returncode, 2)

    def test_filtered_harness_rsync_rejects_cancelling_filter_rules(self):
        paths = ('config/project-profile.conf', 'reports/', 'work-items/', 'artifacts/',
                 'docs/exec-plans/', 'docs/product-specs/', 'docs/troubleshooting/')
        excludes = ' '.join(f'--exclude={path}' for path in paths)
        allowed = (
            excludes,
            ' '.join(f"--filter='H {path}' --filter='P {path}'" for path in paths),
            ' '.join(f"--filter='- {path}'" for path in paths),
            ' '.join(f"-f '- {path}'" for path in paths),
        )
        for filters in allowed:
            with self.subTest(allowed=filters):
                command = f'rsync -a --delete {filters} source/ .agents/'
                self.assertEqual(self.hook(command).returncode, 0, command)
        blocked = (
            f"{excludes} --filter='!'",
            f'--filter="R reports/***" {excludes}',
            f'--filter="S config/project-profile.conf" {excludes}',
            f"{excludes} -f'!'",
            f"{excludes} --filter='merge x'",
            f'{excludes} --exclude-from=f',
            f"{excludes} --exclude='!'",
            f"--exclude='+ reports/' {excludes}",
            f"{excludes} --filt='!'",
            f'{excludes} -C',
            f'{excludes} -aF',
        )
        for filters in blocked:
            with self.subTest(blocked=filters):
                command = f'rsync -a --delete {filters} source/ .agents/'
                self.assertEqual(self.hook(command).returncode, 2, command)

    def test_glob_targets_find_roots_and_rsync_side_outputs(self):
        (self.root / '.agents/AGENTS.md').write_text('x')
        (self.root / 'Assets/sub').mkdir()
        blocked = (
            'printf x > .agent?/AGENTS.md',
            'printf x | tee .agent?/AGENTS.md',
            'printf x | tee .{agents,unused}/AGENTS.md',
            'printf x > .agent(s|x)/AGENTS.md',
            'printf x > .agent{s..t}/AGENTS.md',
            'find Assets .agents -type f -delete',
            'find -L Assets .agents -delete',
            'find Assets .agents -exec rm {} +',
            'rsync -a -b --backup-dir=../.agents/x source/ Assets/',
            'rsync -a -b --backup-dir ../.agents/x source/ Assets/',
            'rsync -a -b --backup-d=../.agents/x source/ Assets/',
            'rsync -a --write-batch=.agents/b source/ Assets/',
            'rsync -a --only-write-batch .agents/b source/ Assets/',
            'rsync -a --only=.agents/b source/ Assets/',
            'rsync -a --log-file=.agents/l source/ Assets/',
            'rsync -a --log=.agents/l source/ Assets/',
        )
        allowed = (
            'printf x > Assets/?ub/x.txt',
            'printf x | tee Assets/{sub,other}/x.txt',
            'printf x > Assets/x.txt',
            'find Assets -delete',
            'find -L Assets -type f -delete',
            'rsync -a -b --backup-dir=../bak source/ Assets/',
            'rsync -a --log-file=Assets/l --write-batch=Assets/b source/ Assets/',
        )
        for shell in ('bash', 'zsh'):
            for commands, expected in ((blocked, 2), (allowed, 0)):
                for command in commands:
                    with self.subTest(shell=shell, command=command):
                        self.assertEqual(self.hook(command, shell='/bin/' + shell).returncode,
                                         expected, command)

    def test_fifth_review_combined_flags_and_substitution(self):
        blocked = (
            'git config core.sparseCheckout true && git read-tree -mu HEAD',
            'git read-tree -um HEAD',
            'rsync -a --link-dest=$(pwd)/.agents/work-items/evidence/TASK-1 source/ /tmp/d/',
            'xargs -0a args.txt rm -rf',
            'xargs -0aargs.txt rm -rf',
            'xargs -0aargsa rm -rf',
            'xargs -aargsa rm -rf',
        )
        for command in blocked:
            with self.subTest(blocked=command):
                self.assertEqual(self.hook(command).returncode, 2, command)
        allowed = (
            "echo '`printf rm`' > Assets/result.txt",
            "echo '$(pwd)' > Assets/result.txt",
            'xargs -0a args.txt cat',
            'xargs -0aargsa cat',
            'xargs -I{a} cp /tmp/review.md Assets/result.txt',
            'rsync -a --delete --exclude=config/project-profile.conf --exclude=reports/ '
            '--exclude=work-items/ --exclude=artifacts/ --exclude=docs/exec-plans/ '
            '--exclude=docs/product-specs/ --exclude=docs/troubleshooting/ source/ .agents/',
            'cp -R logs/ .agents/work-items/evidence/TASK-1/',
        )
        (self.root / 'logs').mkdir()
        (self.root / 'logs/review.md').write_text('ok')
        for command in allowed:
            with self.subTest(allowed=command):
                self.assertEqual(self.hook(command).returncode, 0, command)

    def test_sixth_review_sparse_configuration_and_consumers(self):
        subprocess.run(['/usr/bin/git', 'init', '-q', str(self.root)], check=True)
        # The hook inspects JSON; only fixture setup executes Git.
        self.assertEqual(self.hook('git checkout other').returncode, 0)
        blocked = (
            'git config core.sparseCheckout true',
            'git config --local core.sparseCheckoutCone false',
            'git -c core.sparseCheckout=true checkout other',
            'git -ccore.sparseCheckout=true checkout other',
            'SPARSE=true git --config-env=core.sparseCheckout=SPARSE checkout other',
            "GIT_CONFIG_PARAMETERS='core.sparseCheckout=true' git checkout other",
            'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.sparseCheckout GIT_CONFIG_VALUE_0=true git checkout other',
            "printf 'Assets/\\n' > .git/info/sparse-checkout",
            'cp /tmp/sparse .git/info/sparse-checkout',
            'tee .git/info/sparse-checkout',
        )
        for command in blocked:
            with self.subTest(blocked=command):
                self.assertEqual(self.hook(command).returncode, 2, command)
        self.assertEqual(self.tool('Write', {
            'file_path': '.git/info/sparse-checkout', 'content': 'Assets/\n'
        }).returncode, 2)
        for command in ('git config --get core.sparseCheckout',
                        'git -c core.sparseCheckout=true status --short'):
            with self.subTest(safe_read=command):
                self.assertEqual(self.hook(command).returncode, 0, command)
        payload = json.dumps({'tool_name': 'Bash', 'tool_input': {'command': 'git checkout other'}})
        configured = {**os.environ, 'GIT_CONFIG_COUNT': '1',
                      'GIT_CONFIG_KEY_0': 'core.sparseCheckout', 'GIT_CONFIG_VALUE_0': 'true'}
        result = subprocess.run(['bash', str(HOOK)], input=payload, text=True,
                                capture_output=True, cwd=self.root, env=configured)
        self.assertEqual(result.returncode, 2, result.stderr)
        subprocess.run(['/usr/bin/git', '-C', str(self.root), 'config', 'core.sparseCheckout', 'true'], check=True)
        for command in ('git checkout other', 'git checkout', 'git checkout HEAD',
                        'git switch other', 'git switch --detach HEAD~1',
                        'git merge other', 'git pull --ff-only', 'git pull --rebase',
                        'git rebase other', 'git cherry-pick other', 'git revert --no-edit HEAD'):
            with self.subTest(sparse_consumer=command):
                self.assertEqual(self.hook(command).returncode, 2, command)
        self.assertEqual(self.hook('git status --short').returncode, 0)
        self.assertEqual(self.hook('git sparse-checkout list').returncode, 0)
        self.assertEqual(self.hook(f'git --git-dir={self.root / ".git"} '
                                   f'--work-tree={self.root} checkout other').returncode, 2)

    def test_sixth_review_adjacent_shell_punctuation(self):
        blocked = ('(true); rm -rf .agents', 'echo $((1+2)); rm -rf .agents',
                   'cat <(true); rm -rf .agents', 'true&&(rm -rf .agents)',
                   'true;(rm -rf .agents)', 'true|(rm -rf .agents)',
                   '(cd Assets); rm -rf .agents', '(echo);git checkout -f',
                   'echo $((1+2)); git reset --hard', 'i=$((i+1)); rm -rf .agents',
                   'echo >(rm -rf .agents)', 'diff <(ls) <(rm -rf .agents)')
        for command in blocked:
            with self.subTest(blocked=command):
                self.assertEqual(self.hook(command).returncode, 2, command)
        for command in ('echo $((1+2))', 'echo "(rm -rf .agents)"',
                        'cat .agents/AGENTS.md', 'echo ok > Assets/result.txt'):
            with self.subTest(allowed=command):
                self.assertEqual(self.hook(command).returncode, 0, command)

    def test_sixth_review_worktree_sparse_config(self):
        repo = self.root / 'repo'
        linked = self.root / 'linked'
        subprocess.run(['/usr/bin/git', 'init', '-q', str(repo)], check=True)
        subprocess.run(['/usr/bin/git', '-C', str(repo), '-c', 'user.name=Fixture',
                        '-c', 'user.email=fixture@example.test', 'commit', '-q',
                        '--allow-empty', '-m', 'init'], check=True)
        subprocess.run(['/usr/bin/git', '-C', str(repo), 'config', 'extensions.worktreeConfig',
                        'true'], check=True)
        subprocess.run(['/usr/bin/git', '-C', str(repo), 'worktree', 'add', '-q', '-b',
                        'fixture-linked', str(linked)], check=True)
        (linked / '.agents').mkdir()
        self.assertEqual(self.hook(f'git -C {linked} checkout HEAD').returncode, 0)
        subprocess.run(['/usr/bin/git', '-C', str(linked), 'config', '--worktree',
                        'core.sparseCheckout', 'true'], check=True)
        self.assertEqual(self.hook(f'git -C {linked} checkout HEAD').returncode, 2)
        sparse_path = subprocess.run(['/usr/bin/git', '-C', str(linked), 'rev-parse',
                                      '--git-path', 'info/sparse-checkout'], check=True,
                                     capture_output=True, text=True).stdout.strip()
        self.assertEqual(self.hook(f'echo Assets/ > {sparse_path}').returncode, 2)
        worktree_config = subprocess.run(['/usr/bin/git', '-C', str(linked), 'rev-parse',
                                          '--git-path', 'config.worktree'], check=True,
                                         capture_output=True, text=True).stdout.strip()
        self.assertEqual(self.hook(f'echo value > {worktree_config}').returncode, 2)

    def test_sixth_review_direct_git_config_writes(self):
        subprocess.run(['/usr/bin/git', 'init', '-q', str(self.root)], check=True)
        (self.root / 'input').mkdir()
        (self.root / 'input/config').write_text('[core]\n sparseCheckout = true\n')
        (self.root / 'input/config.worktree').write_text('[core]\n sparseCheckout = true\n')
        for command in ("printf '[core]\\n sparseCheckout=true\\n' > .git/config",
                        'cp input/config .git/config', 'cp -R input/. .git/',
                        'rsync -a input/ .git/', 'ditto input .git'):
            with self.subTest(blocked=command):
                self.assertEqual(self.hook(command).returncode, 2, command)
        self.assertEqual(self.tool('Write', {'file_path': '.git/config',
                                             'content': '[core]\n sparseCheckout = true\n'}).returncode, 2)
        for command in ('git config user.name Fixture', 'cp input/config Assets/config',
                        'cp -R input .git/', 'rsync -a input/ Assets/config-backup/',
                        'echo harmless > /tmp/config'):
            with self.subTest(allowed=command):
                self.assertEqual(self.hook(command).returncode, 0, command)

    def test_sixth_review_apfs_case_aliases_of_git_controls(self):
        subprocess.run(['/usr/bin/git', 'init', '-q', str(self.root)], check=True)
        for lower, alias in (('.git/config', '.GIT/CONFIG'),
                             ('.git/config.worktree', '.GIT/CONFIG.WORKTREE'),
                             ('.git/info/sparse-checkout', '.GIT/INFO/SPARSE-CHECKOUT')):
            physical = self.root / lower
            physical.parent.mkdir(parents=True, exist_ok=True)
            physical.touch()
            alias_path = self.root / alias
            if alias_path.exists() and os.path.samefile(physical, alias_path):
                with self.subTest(alias=alias):
                    self.assertEqual(self.hook(f'echo x > {alias}').returncode, 2, alias)

    def test_seventh_review_zsh_prefixes_and_git_option_scope(self):
        subprocess.run(['/usr/bin/git', 'init', '-q', str(self.root)], check=True)
        for command in ('noglob rm -rf .agents', 'nocorrect rm -rf .agents',
                        'repeat 1 rm -rf .agents', 'coproc rm -rf .agents',
                        'true; - rm -rf .agents'):
            with self.subTest(blocked=command):
                self.assertEqual(self.hook(command).returncode, 2, command)
        for command in ('noglob cat .agents/AGENTS.md',
                        'nocorrect cat .agents/AGENTS.md',
                        'repeat 1 cat .agents/AGENTS.md',
                        'true; - cat .agents/AGENTS.md',
                        'git switch -C feat', 'git status --short'):
            with self.subTest(allowed=command):
                self.assertEqual(self.hook(command).returncode, 0, command)
        self.assertEqual(self.hook(f'git -C {self.root} checkout .').returncode, 2)

    def test_eighth_review_zsh_block_wrappers(self):
        subprocess.run(['/usr/bin/git', 'init', '-q', str(self.root)], check=True)
        blocked = (
            'repeat 2 { rm -rf .agents }',
            'repeat 2 do rm -rf .agents; done',
            'repeat 2 {rm -rf .agents}',
            'coproc { rm -rf .agents }',
            'time { rm -rf .agents }',
            'repeat 2 { git reset --hard }',
            'repeat 2 do git clean -fdx; done',
            'coproc { git clean -fdx }',
            'time { git reset --hard }',
        )
        for command in blocked:
            with self.subTest(blocked=command):
                self.assertEqual(self.hook(command).returncode, 2, command)
        allowed = ('repeat 2 { cat .agents/AGENTS.md }',
                   'repeat 2 do cat .agents/AGENTS.md; done',
                   'coproc { cat .agents/AGENTS.md }',
                   'time { cat .agents/AGENTS.md }',
                   'repeat 2 { echo safe }')
        for command in allowed:
            with self.subTest(allowed=command):
                self.assertEqual(self.hook(command).returncode, 0, command)

    def test_eighth_review_git_alias_and_output_paths(self):
        subprocess.run(['/usr/bin/git', 'init', '-q', str(self.root)], check=True)
        subprocess.run(['/usr/bin/git', '-C', str(self.root), 'config', '--local',
                        'alias.sc', 'sparse-checkout set Assets'], check=True)
        subprocess.run(['/usr/bin/git', '-C', str(self.root), 'config', '--local',
                        'alias.a', 'b'], check=True)
        subprocess.run(['/usr/bin/git', '-C', str(self.root), 'config', '--local',
                        'alias.b', 'sparse-checkout set Assets'], check=True)
        subprocess.run(['/usr/bin/git', '-C', str(self.root), 'config', '--local',
                        'alias.c', '!git b'], check=True)
        blocked = (
            "git config alias.next 'sparse-checkout set Assets' && git next",
            "git config alias.next '!git sparse-checkout set Assets'",
            "git config alias.next '!git b'",
            "git -c alias.x=sparse-checkout x set Assets",
            "git -calias.x=sparse-checkout x set Assets",
            "git -c alias.a=b -c 'alias.b=sparse-checkout set Assets' a",
            "git -c core.sparseCheckout=true -c alias.x=checkout x HEAD",
            "git -c core.sparseCheckout=true -c 'alias.x=!git checkout HEAD' x",
            'git sc',
            'git a',
            'git c',
            'git diff --output=.agents/AGENTS.md',
            'git log --output .agents/work-items/active/TASK-1.conf',
        )
        for command in blocked:
            with self.subTest(blocked=command):
                self.assertEqual(self.hook(command).returncode, 2, command)
        for command in ('git diff --output=Assets/diff.txt',
                        'git log --output Assets/log.txt',
                        "git -c 'alias.x=!git status --short' x",
                        "git config alias.ss '!git status --short'",
                        "git config alias.st 'status --short'", 'git status --short'):
            with self.subTest(allowed=command):
                self.assertEqual(self.hook(command).returncode, 0, command)
        subprocess.run(['/usr/bin/git', '-C', str(self.root), 'config', '--local',
                        'alias.loop', '!sh -c "git loop"'], check=True)
        started = time.monotonic()
        self.assertEqual(self.hook('git loop').returncode, 2)
        self.assertLess(time.monotonic() - started, 1.5)

    def test_eighth_review_git_branch_sparse_recovery_and_bisect_reads(self):
        subprocess.run(['/usr/bin/git', 'init', '-q', str(self.root)], check=True)
        for command in ('git checkout -Bfeat', 'git checkout -bfeat main',
                        'git switch -Cfeat', 'git bisect view', 'git bisect help'):
            with self.subTest(allowed=command):
                self.assertEqual(self.hook(command).returncode, 0, command)
        for value in ('false', 'FALSE', '0', 'off', 'no'):
            with self.subTest(recovery=value):
                self.assertEqual(self.hook(f'git config core.sparseCheckout {value}').returncode, 0)
        self.assertEqual(self.hook('git config --bool core.sparseCheckout false').returncode, 0)
        self.assertEqual(self.hook('git config set core.sparseCheckout false').returncode, 0)
        self.assertEqual(self.hook('git config unset core.sparseCheckout').returncode, 2)
        self.assertEqual(self.hook('git config --unset core.sparseCheckout').returncode, 2)
        self.assertEqual(self.hook('git config core.sparseCheckout true').returncode, 2)

    def test_eighth_review_subshell_and_directory_stack_restore_cwd(self):
        subprocess.run(['/usr/bin/git', 'init', '-q', str(self.root)], check=True)
        nested = self.root / 'Assets/inner'
        nested.mkdir()
        subprocess.run(['/usr/bin/git', 'init', '-q', str(nested)], check=True)
        subprocess.run(['/usr/bin/git', '-C', str(self.root), 'config', '--local',
                        'core.sparseCheckout', 'true'], check=True)
        for command in ('(cd Assets/inner); git checkout HEAD',
                        'pushd Assets/inner; popd; git checkout HEAD'):
            with self.subTest(blocked=command):
                self.assertEqual(self.hook(command).returncode, 2, command)
        self.assertEqual(self.hook('cd Assets/inner; git checkout HEAD').returncode, 2)
        self.assertEqual(self.hook('cd Assets/inner && git checkout HEAD').returncode, 0)

    def test_seventh_review_evidence_merge_and_sparse_recovery(self):
        subprocess.run(['/usr/bin/git', 'init', '-q', str(self.root)], check=True)
        (self.root / 'logs').mkdir()
        (self.root / 'logs/review.md').write_text('ok')
        (self.root / 'forged').mkdir()
        (self.root / 'forged/revision-0-input-manifest.json').write_text('{}')
        for command in ('cp -R logs/. .agents/work-items/evidence/TASK-1/',
                        'rsync -a logs/ .agents/work-items/evidence/TASK-1/'):
            with self.subTest(allowed=command):
                self.assertEqual(self.hook(command).returncode, 0, command)
        for command in ('cp -R forged/. .agents/work-items/evidence/TASK-1/',
                        'rsync -a --delete logs/ .agents/work-items/evidence/TASK-1/'):
            with self.subTest(blocked=command):
                self.assertEqual(self.hook(command).returncode, 2, command)
        subprocess.run(['/usr/bin/git', '-C', str(self.root), 'config', '--local',
                        'core.sparseCheckout', 'true'], check=True)
        for command in ('git config core.sparseCheckout false',
                        'git config --local core.sparseCheckout false'):
            with self.subTest(recovery=command):
                self.assertEqual(self.hook(command).returncode, 0, command)
        self.assertEqual(self.hook('git config core.sparseCheckout true').returncode, 2)
        self.assertEqual(self.hook('git config --unset core.sparseCheckout').returncode, 2)
        global_config = self.root / 'global.gitconfig'
        global_config.write_text('[core]\n sparseCheckout = true\n')
        subprocess.run(['/usr/bin/git', '-C', str(self.root), 'config', '--local',
                        'core.sparseCheckout', 'false'], check=True)
        payload = json.dumps({'tool_name': 'Bash',
                              'tool_input': {'command': 'git config --unset core.sparseCheckout'}})
        env = {**os.environ, 'GIT_CONFIG_GLOBAL': str(global_config)}
        result = subprocess.run(['bash', str(HOOK)], input=payload, text=True,
                                capture_output=True, cwd=self.root, env=env)
        self.assertEqual(result.returncode, 2, result.stderr)

    def test_seventh_review_git_global_flag_cursor(self):
        subprocess.run(['/usr/bin/git', 'init', '-q', str(self.root)], check=True)
        for option in ('--no-optional-locks', '--no-lazy-fetch',
                       '--icase-pathspecs', '--noglob-pathspecs'):
            with self.subTest(option=option):
                self.assertEqual(self.hook(f'git {option} reset --hard').returncode, 2)
                self.assertEqual(self.hook(f'git {option} status --short').returncode, 0)
        self.assertEqual(self.hook('git --unrecognized reset --hard').returncode, 2)

    def test_seventh_review_indirect_sparse_config_and_bisect(self):
        subprocess.run(['/usr/bin/git', 'init', '-q', str(self.root)], check=True)
        include = self.root / 'sparse-include.conf'
        include.write_text('[core]\n sparseCheckout = true\n')
        home = self.root / 'other-home'
        home.mkdir()
        (home / '.gitconfig').write_text('[core]\n sparseCheckout = true\n')
        xdg = self.root / 'other-xdg'
        (xdg / 'git').mkdir(parents=True)
        (xdg / 'git/config').write_text('[core]\n sparseCheckout = true\n')
        blocked = (
            f'git -c include.path={include} checkout HEAD',
            f'INC={include} git --config-env=include.path=INC checkout HEAD',
            f'HOME={home} git checkout HEAD',
            f'XDG_CONFIG_HOME={xdg} git checkout HEAD',
            f'git config include.path {include} && git checkout HEAD',
            f'git config includeIf.gitdir:{self.root}.path {include}',
            'git config --rename-section zz core',
        )
        for command in blocked:
            with self.subTest(blocked=command):
                if command.startswith(('HOME=', 'XDG_CONFIG_HOME=')):
                    # A forced global config file would hide Git's HOME/XDG lookup.
                    env = {**os.environ}
                    env.pop('GIT_CONFIG_GLOBAL', None)
                    payload = json.dumps({'tool_name': 'Bash', 'tool_input': {'command': command}})
                    result = subprocess.run(['bash', str(HOOK)], input=payload, text=True,
                                            capture_output=True, cwd=self.root, env=env)
                else:
                    result = self.hook(command)
                self.assertEqual(result.returncode, 2, command)
        subprocess.run(['/usr/bin/git', '-C', str(self.root), 'config', 'core.sparseCheckout', 'true'], check=True)
        for command in ('git bisect start HEAD HEAD~1', 'git bisect good', 'git bisect reset',
                        'git bisect replay /tmp/bisect.log', 'git bisect new'):
            with self.subTest(bisect=command):
                self.assertEqual(self.hook(command).returncode, 2, command)
        for command in ('git status --short', 'git bisect log', 'git bisect terms',
                        'git bisect visualize', 'git config --get include.path',
                        'git config include.path',
                        'git config user.name Example'):
            with self.subTest(allowed=command):
                self.assertEqual(self.hook(command).returncode, 0, command)


    def test_native_parser_offline_build_reproduces_committed_universal(self):
        if not all(Path(path).is_file() for path in ('/usr/bin/clang', '/usr/bin/lipo', '/usr/bin/xcrun')):
            self.skipTest('macOS native build tools unavailable')
        compiler = subprocess.run(['/usr/bin/clang', '--version'], capture_output=True, text=True)
        sdk = subprocess.run(['/usr/bin/xcrun', '--show-sdk-version'], capture_output=True, text=True)
        if (compiler.returncode or sdk.returncode or
                'Apple clang version 21.0.0 (clang-2100.1.1.101)' not in compiler.stdout or
                sdk.stdout.strip() != '26.5'):
            self.skipTest('pinned compiler and SDK unavailable')
        package = AGENTS / 'scripts/hooks/shell-parser'
        output = self.root / 'tsparse-universal'
        for name in ('home', 'xdg', 'tmp', 'clang-cache'):
            (self.root / name).mkdir()
        env = dict(os.environ, HOME=str(self.root / 'home'),
                   XDG_CACHE_HOME=str(self.root / 'xdg'),
                   TMPDIR=str(self.root / 'tmp'),
                   CLANG_MODULE_CACHE_PATH=str(self.root / 'clang-cache'))

        def build(architecture, path):
            return subprocess.run(['/bin/sh', str(package / 'build.sh'), architecture,
                                   str(path)], env=env, capture_output=True, text=True, timeout=60)

        result = build('universal', output)
        self.assertEqual(result.returncode, 0, result.stderr)
        committed = package / 'bin/tsparse-macos-universal'
        self.assertEqual(hashlib.sha256(output.read_bytes()).digest(),
                         hashlib.sha256(committed.read_bytes()).digest())
        self.assertEqual(output.read_bytes(), committed.read_bytes())
        self.assertFalse(list(self.root.glob('.tsparse-build.*')))
        for architecture in ('arm64', 'x86_64'):
            thin = self.root / ('tsparse-' + architecture)
            result = build(architecture, thin)
            self.assertEqual(result.returncode, 0, result.stderr)
            committed_thin = self.root / ('committed-' + architecture)
            subprocess.run(['/usr/bin/lipo', '-thin', architecture, str(committed),
                            '-output', str(committed_thin)], check=True)
            self.assertEqual(thin.read_bytes(), committed_thin.read_bytes())
            self.assertFalse(list(self.root.glob('.tsparse-build.*')))
        before = output.read_bytes()
        self.assertEqual(build('universal', output).returncode, 4)
        self.assertEqual(output.read_bytes(), before)
        self.assertFalse(list(self.root.glob('.tsparse-build.*')))


    def test_round10_execution_state_and_stdin_pairs(self):
        (self.root / 'child').mkdir()
        pairs = (
            ("cat <<'E' && rm -rf .agents\nx\nE", 2),
            ("cat <<'E' && printf ok\nx\nE", 0),
            ("cat <<'E' | rm -rf .agents\nx\nE", 2),
            ("cat <<'E' || rm -rf .agents\nx\nE", 2),
            ("cat <<'E' | bash\nrm -rf .agents\nE", 2),
            ("cat <<'E' | cat\nplain data\nE", 0),
            ("case $(rm -rf .agents) in *) ;; esac", 2),
            ("case x in $(rm -rf .agents)) ;; esac", 2),
            ("case $(printf x) in x) printf ok;; esac", 0),
            ('case "$(rm -rf .agents)" in x) ;; esac', 2),
            ("export X=$(rm -rf .agents)", 2),
            ("export X=$(printf ok)", 0),
            ("readonly X=$(rm -rf .agents)", 2),
            ("declare X=$(rm -rf .agents)", 2),
            ("typeset X=$(rm -rf .agents)", 2),
            ("export $(rm -rf .agents)", 2),
            ('export "$(rm -rf .agents)"', 2),
            ("readonly `rm -rf .agents`", 2),
            ("typeset $(rm -rf .agents)", 2),
            ("declare $(rm -rf .agents)", 2),
            ("export $(printf SAFE)", 0),
            ("export SAFE=$(printf yes)", 0),
            ("readonly SAFE", 0),
            ("typeset", 0),
            ("echo x; " * 6 + "echo x", 0),
            ("echo x; " * 19 + "echo x", 0),
            ("echo x\n" * 1000, 0),
            ("echo x\n" * 1000 + "rm -rf .agents", 2),
            ("echo x\n" * 3000, 0),
            ("echo x\n" * 3000 + "rm -rf .agents", 2),
            (" && ".join(["true"] * 100), 0),
            (" && ".join(["true"] * 100) + " && rm -rf .agents", 2),
            (" && ".join(["echo x"] * 100), 0),
            (" && ".join(["echo x"] * 100) + " && rm -rf .agents", 2),
            (" && ".join(["printf x"] * 100), 0),
            (" && ".join(["printf x"] * 100) + " && rm -rf .agents", 2),
            ("while read l; do echo \"$l\"; done < list.txt", 0),
            ("while read l; do rm -rf .agents; done < list.txt", 2),
            ("pushd child; ls; popd", 0),
            ("popd && rm -rf .agents", 0),
            ("popd || rm -rf .agents", 2),
            ("pushd child; popd && rm -rf .agents", 2),
            ("pushd child; popd && printf ok", 0),
            ("f() { rm -rf .agents; }; printf ok", 0),
        )
        for shell in ('bash', 'zsh'):
            for command, expected in pairs:
                with self.subTest(shell=shell, command=command):
                    self.assertEqual(self.hook(command, shell='/bin/' + shell).returncode,
                                     expected, command)

    def test_round10_native_execution_nodes(self):
        pairs = (
            ('! { rm -rf .agents; }', 2),
            ('! { printf ok; }', 0),
            ('! if true; then rm -rf .agents; fi', 2),
            ('! if true; then printf ok; fi', 0),
            ('cat <<E\n`rm -rf .agents`\nE', 2),
            ("cat <<'E'\n`rm -rf .agents`\nE", 0),
            ('cat <<E\n\\`rm -rf .agents\\`\nE', 0),
        )
        for shell in ('bash', 'zsh'):
            for command, expected in pairs:
                with self.subTest(shell=shell, command=command):
                    self.assertEqual(self.hook(command, shell='/bin/' + shell).returncode,
                                     expected, command)

    def test_round10_pipeline_cwd_and_heredoc_scope(self):
        pairs = (
            ("cat <<'E' | cd Assets && rm -rf .\nx\nE", (2, 0)),
            ("cat <<'E' | cd .agents && printf x > AGENTS.md\nx\nE", (2, 2)),
            ("cat <<'E' | cat | cd Assets && rm -rf .\nx\nE", (2, 0)),
            ("cat <<'E' | cd Assets || printf ok\nx\nE", (0, 0)),
            ("cat <<'E' | cd Assets > product.txt && printf ok\nx\nE", (0, 0)),
            ("printf x | cd Assets && rm -rf .", (2, 0)),
            ("printf x | cd .agents && printf x > AGENTS.md", (2, 2)),
            ("cat <<'E' | true || printf x > .agents/AGENTS.md\nx\nE", (2, 2)),
            ("f() { cd Assets; }; printf x | f && rm -rf .", (2, 0)),
            ("f() { cd .agents; }; printf x | f && printf x > AGENTS.md", (2, 2)),
            ("cat <<'E' | { cd Assets && printf x; } && rm -rf .\nx\nE", (2, 0)),
            ("cat <<'E' | (cd Assets; printf x) && rm -rf .\nx\nE", (2, 2)),
            ("cd .agents && printf x > AGENTS.md", (2, 2)),
            ("cd Assets && printf x > product.txt", (0, 0)),
            ("false && printf x > .agents/AGENTS.md", (0, 0)),
            ("{ cd Assets; printf ok; } > .agents/AGENTS.md", (2, 2)),
            ("{ cd .agents; printf ok; } > Assets/product.txt", (0, 0)),
            ("cat <<'E' | true && sh\nplain data\nE", (0, 0)),
            ("cat <<'E' | true && bash\nrm -rf .agents\nE", (0, 0)),
            ("cat <<'E' && bash\nrm -rf .agents\nE", (0, 0)),
            ("cat <<'E' | bash\nrm -rf .agents\nE", (2, 2)),
        )
        for command, expected in pairs:
            for shell, result in zip(('bash', 'zsh'), expected):
                with self.subTest(shell=shell, command=command):
                    self.assertEqual(self.hook(command, shell='/bin/' + shell).returncode,
                                     result, command)

    def test_round10_cat_pipeline_stdout_provenance(self):
        def script(prefix, body='printf ok'):
            return prefix + '\n' + body + '\nE'

        pairs = (
            (script("bash <<'E'"), 0),
            (script("bash <<'E'", 'rm -rf .agents'), 2),
            (script("cat <<'E' | bash"), 0),
            (script("cat <<'E' | bash", 'rm -rf .agents'), 2),
            (script("bash <<E"), 0),
            (script("bash <<E", 'rm -rf .agents'), 2),
            (script("cat <<E | bash"), 0),
            (script("cat <<E | bash", 'rm -rf .agents'), 2),
            (script("cat <<'E' | cat | bash"), 0),
            (script("cat <<'E' | cat | bash", 'rm -rf .agents'), 2),
            (script("/bin/cat <<'E' | bash"), 0),
            (script("PATH=/tmp; /bin/cat <<'E' | bash"), 0),
            (script("alias cat='printf x'; /bin/cat <<'E' | bash"), 0),
            ("cat <<< 'printf ok' | bash", 0),
            ("cat <<< 'rm -rf .agents' | bash", 2),
            (script("cat <<E | bash", 'printf $D'), 2),
            (script("cat -n <<'E' | bash"), 2),
            ('cat Assets/script.sh | bash', 2),
            (script("cat <<'E' | cat -n | bash"), 2),
            (script("cat <<'E' |& bash"), 2),
            (script("cat <<'E' > Assets/out.txt | bash"), 2),
            (script("printf ok <<'E' | bash"), 2),
            (script("R=cat; $R <<'E' | bash"), 2),
            (script("cat(){ printf x; }; cat <<'E' | bash"), 2),
            (script("alias cat='printf x'; cat <<'E' | bash"), 2),
            (script("command -- alias cat='printf x'; cat <<'E' | bash"), 2),
            (script("builtin -- alias cat='printf x'; cat <<'E' | bash"), 2),
            (script("command -v cat; cat <<'E' | bash"), 0),
            (script("builtin -- unset PATH; cat <<'E' | bash"), 2),
            (script("command -- eval 'printf ok'; cat <<'E' | bash"), 2),
            ("command -- eval \"cat <<'E' | bash\nprintf ok\nE\"", 0),
            ("alias cat='printf x'; command -- eval \"cat <<'E' | bash\nprintf ok\nE\"", 2),
            (script(f"command -- . {HOOK}; cat <<'E' | bash"), 2),
            (script("alias other='printf x'; cat <<'E' | bash"), 0),
            (script("f(){ alias cat='printf x'; }; f; cat <<'E' | bash"), 2),
            (script("PATH=/tmp; cat <<'E' | bash"), 2),
            (script("PATH=/tmp cat <<'E' | bash"), 2),
            (script("command cat <<'E' | bash"), 2),
        )
        for shell in ('bash', 'zsh'):
            for command, expected in pairs:
                with self.subTest(shell=shell, command=command):
                    self.assertEqual(self.hook(command, shell='/bin/' + shell).returncode,
                                     expected, command)
        self.assertEqual(self.hook(script("function /bin/cat() { printf x; }; "
                                          "/bin/cat <<'E' | bash"), shell='/bin/zsh').returncode, 2)
        for command, expected in (
                ("noglob alias cat='printf x'", 2),
                ("nocorrect alias cat='printf x'", 2),
                ("repeat 1 alias cat='printf x'", 2),
                ("noglob alias other='printf x'", 0)):
            with self.subTest(shell='zsh', command=command):
                self.assertEqual(self.hook(script(command + "; cat <<'E' | bash"),
                                           shell='/bin/zsh').returncode, expected)

    def test_round11_numbered_heredoc_keeps_parent_stdin(self):
        def outer(body):
            return "\n} <<'F'\n" + body + "\nF"

        pairs = (
            ("{ cat 3<<'E' | bash\necho no\nE" + outer('rm -rf .agents'), 2),
            ("{ bash 3<<'E'\necho no\nE" + outer('rm -rf .agents'), 2),
            ("while read -r l; do cat 3<<'E' | bash\necho no\nE\ndone <<'F'\n"
             "dummy\nrm -rf .agents\nF", 2),
            ("exec <<'F'\nrm -rf .agents\nF\ncat 3<<'E' | bash\necho no\nE", 2),
            ("exec <<'F'\nrm -rf .agents\nF\nbash", 2),
            ("exec 3<<'F'\nrm -rf .agents\nF\nbash <&3", 2),
            ("{ cat 3<<'E' | bash\necho no\nE" + outer('echo hi'), 0),
            ("{ cat <<'E' | bash\necho no\nE" + outer('rm -rf .agents'), 0),
            ("exec <<'F'\necho hi\nF\nbash", 0),
        )
        for shell in ('bash', 'zsh'):
            for command, expected in pairs:
                with self.subTest(shell=shell, command=command):
                    self.assertEqual(self.hook(command, shell='/bin/' + shell).returncode,
                                     expected, command)

    def test_round11_reserved_word_command_names_fail_closed(self):
        pairs = (
            ('! for i in 1; do rm -rf .agents; done', 2),
            ('! select x in a; do rm -rf .agents; done', 2),
            ('! time rm -rf .agents', 2),
            ('\\time rm -rf .agents', 2),
            ('/usr/bin/time rm -rf .agents', 2),
            ('/usr/bin/time -l rm -rf .agents', 2),
            ('time ls', 0),
            ('/usr/bin/time -l ls', 0),
            ('for i in 1; do echo hi; done', 0),
            ('! true', 0),
            ('if ! grep -q x f; then echo no; fi', 0),
        )
        for shell in ('bash', 'zsh'):
            for command, expected in pairs:
                with self.subTest(shell=shell, command=command):
                    self.assertEqual(self.hook(command, shell='/bin/' + shell).returncode,
                                     expected, command)
        for command, expected in (('repeat 2 do echo hi; done', 0),
                                  ('repeat 2 do rm -rf .agents; done', 2),
                                  ('coproc cat', 0)):
            with self.subTest(shell='zsh', command=command):
                self.assertEqual(self.hook(command, shell='/bin/zsh').returncode, expected)

    def test_round12_exec_stdin_persistence_forms(self):
        # Effects follow harmless Bash 3.2 / zsh probes: 'persist' rebinds later stdin.
        persist = {
            'bash': ("exec", "'exec'", '\\exec', 'command exec', 'command -- exec',
                     'command -p exec', 'exec --', 'exec -a named', 'command command exec'),
            'zsh': ("exec", "'exec'", '\\exec', 'builtin exec', 'noglob exec',
                    'nocorrect exec', 'builtin builtin exec'),
        }
        forms = sorted(set(persist['bash']) | set(persist['zsh']) |
                       {'builtin -- exec', 'builtin command exec', 'command builtin exec'})
        outer_danger = "{{ {} <<'E'\nprintf inner\nE\nbash; }} <<'F'\nrm -rf .agents\nF"
        inner_danger = "{{ {} <<'E'\nrm -rf .agents\nE\nbash; }} <<'F'\nprintf hi\nF"
        for shell in ('bash', 'zsh'):
            for form in forms:
                kept = form in persist[shell]
                unknown = shell == 'zsh' and form.startswith('exec ')
                for template, expected in ((outer_danger, 2 if unknown or not kept else 0),
                                           (inner_danger, 2 if unknown or kept else 0)):
                    command = template.format(form)
                    with self.subTest(shell=shell, command=command):
                        self.assertEqual(self.hook(command, shell='/bin/' + shell).returncode,
                                         expected, command)
        piped = "printf '\\n' | exec <<'F'"
        for shell, command, expected in (('zsh', piped + "\nrm -rf .agents\nF\nbash", 2),
                                         ('zsh', piped + "\necho hi\nF\nbash", 0),
                                         ('bash', piped + "\nrm -rf .agents\nF\nbash", 0),
                                         ('bash', 'command -v exec', 0),
                                         ('bash', "( exec <<'F'\nrm -rf .agents\nF\n); echo ok", 0)):
            with self.subTest(shell=shell, command=command):
                self.assertEqual(self.hook(command, shell='/bin/' + shell).returncode,
                                 expected, command)

    def test_round12_time_output_and_negated_compounds(self):
        pairs = (
            ('/usr/bin/time -o .agents/AGENTS.md printf ok', 2),
            ('\\time -o .agents/AGENTS.md printf ok', 2),
            ('command time -o .agents/AGENTS.md printf ok', 2),
            ('/usr/bin/time --output=.agents/AGENTS.md printf ok', 2),
            ('/usr/bin/time -o.agents/AGENTS.md printf ok', 2),
            ('/usr/bin/time -o Assets/timing.txt printf ok', 0),
            ('/usr/bin/time -a -o Assets/timing.txt printf ok', 0),
            ('! for i in 1; do printf ok; done', 0),
            ('! for i in 1; do rm -rf .agents; done', 2),
            ('! select x in a; do printf ok; break; done', 0),
            ('! select x in a; do rm -rf .agents; done', 2),
            ('! time printf ok', 0),
            ('! time rm -rf .agents', 2),
            ('! for i in 1; do true; done || rm -rf .agents', 2),
            ('! for i in 1; do printf ok; done && echo y', 0),
            ('! time true || rm -rf .agents', 2),
            ('! time true && rm -rf .agents', 2),  # rewritten negation keeps both statuses
            ('! while false; do :; done || rm -rf .agents', 2),
            ('! while false; do :; done && rm -rf .agents', 0),
        )
        for shell in ('bash', 'zsh'):
            for command, expected in pairs:
                with self.subTest(shell=shell, command=command):
                    self.assertEqual(self.hook(command, shell='/bin/' + shell).returncode,
                                     expected, command)


    def test_round13_shadowed_wrappers_and_negation_status(self):
        outer = "{{ {} <<'E'\nprintf inner\nE\nbash; }} <<'F'\nrm -rf .agents\nF"
        pairs = []
        for function, form in (('command', 'command exec'), ('builtin', 'builtin exec'),
                               ('exec', 'exec'), ('noglob', 'noglob exec')):
            pairs.append((function + '() { :; }\n' + outer.format(form), 2))
        for prefix in ('false() { :; }; ', 'true() { false; }; ', ''):
            pairs += [(prefix + '! time true || rm -rf .agents', 2),
                      (prefix + '! time false && rm -rf .agents', 2),
                      (prefix + '! for i in 1; do :; done || rm -rf .agents', 2),
                      (prefix + 'if ! for i in 1; do :; done; then :; else rm -rf .agents; fi', 2)]
        pairs += [("! for i in 1; do printf '%s' '<<'; done", 0),
                  ("! for i in 1; do cat <<'E'\nprintf ok\nE\ndone", 0),
                  ("! for i in 1; do cat <<'E' | bash\nrm -rf .agents\nE\ndone", 2),
                  ('! case x in x) printf ok;; esac', 0),
                  ('! case x in x) rm -rf .agents;; esac', 2),
                  ('! for i in 1; do ! time printf ok; done', 0),
                  ('! for i in 1; do ! for j in 1; do rm -rf .agents; done; done', 2)]
        for shell in ('bash', 'zsh'):
            for command, expected in pairs:
                with self.subTest(shell=shell, command=command):
                    self.assertEqual(self.hook(command, shell='/bin/' + shell).returncode,
                                     expected, command)
        for command in ('builtin exec', 'builtin command exec'):
            with self.subTest(shell='bash', command=command):
                self.assertEqual(self.hook(outer.format(command), shell='/bin/bash').returncode, 2)
        for command in ('command exec', 'command -- exec', 'builtin command exec'):
            with self.subTest(shell='zsh', command=command):
                self.assertEqual(self.hook(outer.format(command), shell='/bin/zsh').returncode, 2)

    def test_round14_command_options_aliases_and_negation_text(self):
        outer = "{{ {} <<'E'\nprintf inner\nE\nbash; }} <<'F'\nrm -rf .agents\nF"
        inner = "{{ {} <<'E'\nrm -rf .agents\nE\nbash; }}"
        aliases = 'shopt -s expand_aliases 2>/dev/null; alias {}=\':\'\n'
        pairs = [(aliases.format('exec') + outer.format('exec'), 2),
                 (aliases.format('command') + outer.format('command exec'), 2),
                 ('shopt -s expand_aliases 2>/dev/null; alias e=exec\n' + inner.format('e'), 2),
                 ("alias other='printf x'\n" + outer.format('exec'), 0),
                 ('X=.agents; f() { X=harmless; }; ! time f; rm -rf "$X"', 2),
                 ('X=.agents; f() { X=harmless; }; ! time -p f; rm -rf "$X"', 2),
                 ("! case x in x) printf '%s' ' ! hi';; esac", 0),
                 ('! \\\ncase x in x) printf ok;; esac', 0),
                 ("! \\\ncase x in x) cat <<'E'\n ! hi\nE\n;; esac", 0),
                 ('echo a ! b; ! case x in x) :;; esac', 0),
                 ("! case x in x) printf '%s' ' ! hi'; rm -rf .agents;; esac", 2),
                 ('! \\\ncase x in x) rm -rf .agents;; esac', 2),
                 ('! case x in x) :;; esac # ! \\\nrm -rf .agents', 2)]
        for shell in ('bash', 'zsh'):
            for command, expected in pairs:
                with self.subTest(shell=shell, command=command):
                    self.assertEqual(self.hook(command, shell='/bin/' + shell).returncode,
                                     expected, command)
        with self.subTest(shell='zsh', command='global alias'):
            self.assertEqual(self.hook('alias -g G=exec\n' + inner.format('noglob G'),
                                       shell='/bin/zsh').returncode, 2)
        # Bash: `--` ends `command` options, so the next word is the command name.
        for form in ('command -- -p exec', 'command -- -- exec', 'command -p -- -p exec'):
            with self.subTest(shell='bash', command=form):
                self.assertEqual(self.hook(outer.format(form), shell='/bin/bash').returncode, 2)
        for form in ('command -p -p exec', 'command -p -- exec', 'command -- command exec'):
            with self.subTest(shell='bash', command=form):
                self.assertEqual(self.hook(inner.format(form), shell='/bin/bash').returncode, 2)

    def test_round15_unresolved_aliases_disabled_builtins_and_fallback_text(self):
        outer = "{{ {} <<'E'\nprintf inner\nE\nbash; }} <<'F'\nrm -rf .agents\nF"
        inner = "{{ {} <<'E'\nrm -rf .agents\nE\nbash; }}"
        expand = 'shopt -s expand_aliases 2>/dev/null; '
        bash_pairs = [(expand + 'f(){ alias "$1"=exec; }; f e\n' + inner.format('e'), 2),
                      (expand + "f(){ alias $1; }; f 'e=exec'\n" + inner.format('e'), 2),
                      (expand + 'N=$(printf e); alias "$N"=exec\n' + inner.format('e'), 2),
                      (expand + 'f(){ alias "$1"=\':\'; }; f exec\n' + outer.format('exec'), 2),
                      ('enable -n exec\n' + outer.format('exec'), 2),
                      ('enable -n command\n' + outer.format('command exec'), 2),
                      ('time enable -n exec\n' + outer.format('exec'), 2)]
        pairs = [("! case x in x) cat <<'! E'\nx\n! E\n;; esac", 0),
                 ("! case x in x) cat <<' ! E'\nok\n ! E\n\n;; esac", 0),
                 ("! case x in x) cat <<'! E'\nrm -rf .agents\n! E\n;; esac", 0),
                 ("! case x in x) cat <<'! E'\nx\n! E\n;; esac; rm -rf .agents", 2),
                 ('! case x in x) printf ok;; esac\n# ! \\\n! case y in y) printf ok;; esac', 0),
                 ('! case x in x) printf ok;; esac # ! \\\n! case y in y) printf ok;; esac', 0),
                 ('! case x in x) printf ok;; esac\n# ! \\\n! case y in y) rm -rf .agents;; esac', 2)]
        for shell, command, expected in ([('bash',) + pair for pair in bash_pairs] +
                                         [(shell,) + pair for pair in pairs
                                          for shell in ('bash', 'zsh')]):
            with self.subTest(shell=shell, command=command):
                self.assertEqual(self.hook(command, shell='/bin/' + shell).returncode,
                                 expected, command)

    def test_round16_prefixed_function_shadows_workdir_and_split_delimiters(self):
        outer = "{{ {} <<'E'\nprintf inner\nE\nbash; }} <<'F'\nrm -rf .agents\nF"
        for function, form in (('exec', "noglob 'exec'"), ('exec', "nocorrect 'exec'"),
                               ('exec', "- 'exec'"), ('builtin', 'noglob builtin exec')):
            command = 'function ' + function + ' { :; }; ' + outer.format(form)
            with self.subTest(shell='zsh', command=command):
                self.assertEqual(self.hook(command, shell='/bin/zsh').returncode, 2)
        for workdir in ('.agents', str(self.root / '.agents'), 5):
            with self.subTest(workdir=workdir):
                self.assertEqual(self.tool('exec_command', {'cmd': 'printf x > AGENTS.md',
                                                            'workdir': workdir}).returncode, 2)
        self.assertEqual(self.tool('exec_command', {'cmd': 'printf x > Assets/x.txt',
                                                    'workdir': str(self.root)}).returncode, 0)
        # Harmless forms are paired with the real shells' result before the hook verdict.
        harmless = ("! case x in x) cat <<'! 'E\nhello\n! E\n;; esac",
                    "! case x in x) cat <<-' ! E'\n\thello\n\t ! E\n;; esac",
                    "cat <<\"! \"E\nhello\n! E",
                    "! case x in x) cat <<'!'\\ E\nhello\n! E\n;; esac",
                    "cat <<-\\!\\ 'E'\nhello\n! E",
                    "cat <<$'! E'\nhello\n! E")
        for shell in ('bash', 'zsh'):
            for command in harmless:
                with self.subTest(shell=shell, command=command):
                    real = subprocess.run(['/bin/' + shell, '-c', command], text=True,
                                          capture_output=True, cwd=self.root)
                    self.assertEqual((real.stdout, real.stderr), ('hello\n', ''))
                    self.assertEqual(self.hook(command, shell='/bin/' + shell).returncode, 0)
            for command in ("cat <<'! 'E | bash\nrm -rf .agents\n! E",
                            "cat <<-' ! E' | bash\n\trm -rf .agents\n\t ! E",
                            "cat <<'! 'E | bash\nZZZ\nrm -rf .agents\n! E",
                            "cat <<'!'\\ E | bash\nrm -rf .agents\n! E",
                            "cat <<$'! E' | bash\nrm -rf .agents\n! E",
                            "echo \"<<'a 'b\"; cat <<'c 'd\nhi\nc d\nrm -rf .agents"):
                with self.subTest(shell=shell, command=command):
                    self.assertEqual(self.hook(command, shell='/bin/' + shell).returncode, 2)

if __name__ == '__main__':
    unittest.main()
