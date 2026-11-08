#!/usr/bin/env python3
"""Inspect structured PreToolUse input. This guard is not an OS sandbox."""

import ast
import fnmatch
import glob
import json
import os
import re
import shlex
import subprocess
import sys
from functools import lru_cache
from pathlib import Path
from shell_cst import parse, source, children, dialect

ROOT_AGENTS = Path(__file__).resolve().parents[2]
GIT_BUILTINS = ('config', 'diff', 'log', 'status', 'clean', 'rm', 'mv', 'checkout',
                'switch', 'worktree', 'checkout-index', 'read-tree', 'restore',
                'reset', 'stash', 'sparse-checkout', 'bisect', 'merge', 'pull',
                'rebase', 'cherry-pick', 'revert', 'add', 'commit', 'branch',
                'fetch', 'push', 'show', 'rev-parse', 'ls-files', 'init',
                'update-index', 'apply', 'am', 'clone', 'format-patch')


def has_agents(base):
    return any((parent / '.agents').exists() for parent in (base, *base.parents))


@lru_cache(maxsize=32)  # One hook process inspects one JSON input; no cross-call stale state.
def git_control_paths(base):
    env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    try:
        result = subprocess.run(['/usr/bin/git', '-C', str(base), 'rev-parse',
                                 '--git-path', 'config', '--git-path', 'config.worktree',
                                 '--git-path', 'info/sparse-checkout'],
                                env=env, capture_output=True, text=True, timeout=2)
    except (OSError, subprocess.TimeoutExpired):
        return None
    lines = result.stdout.splitlines()
    return tuple(paths(line, base)[1] for line in lines) if result.returncode == 0 and len(lines) == 3 else None


def protected_git_file(path, base):
    """Git control files can change the next worktree update without a Git CLI."""
    if not has_agents(base):
        return False
    candidates = paths(path, base)
    control_paths = {'config': 'config', 'config.worktree': 'config.worktree',
                     'sparse-checkout': 'info/sparse-checkout'}
    candidates = [target for target in candidates
                  if target.name.casefold() in control_paths and
                  (target.name.casefold() != 'sparse-checkout' or
                   target.parent.name.casefold() == 'info')]
    if not candidates:
        return False
    if any((target.name == 'config' and target.parent.name == '.git') or
           (target.name == 'sparse-checkout' and target.parent.parent.name == '.git') or
           (target.name == 'sparse-checkout' and
            target.parent.parent.parent.name == 'worktrees' and '.git' in target.parts) or
           (target.name == 'config.worktree' and
            target.parent.parent.name == 'worktrees' and '.git' in target.parts)
           for target in candidates):
        return True
    controls = git_control_paths(base)
    if controls is None:
        return False
    for target in candidates:
        for control in controls:
            if target.name.casefold() != control.name.casefold():
                continue
            if target == control:
                return True
            if target.exists() and control.exists() and target.samefile(control):
                return True
            if (sys.platform == 'darwin' and not target.exists() and
                target.parent.exists() and control.parent.exists() and
                target.parent.samefile(control.parent)):
                return True
    return False


def git_config_result(base, key, git_dir=None, work_tree=None, variables=None,
                      git_options=(), bool_value=False, require_repository=True):
    """Read the effective config under the same Git options and environment."""
    variables = variables or {}
    env = {key: value for key, value in os.environ.items()
           if not key.startswith('GIT_') or key.startswith('GIT_CONFIG_')}
    env.update({key: value for key, value in variables.items()
                if key.startswith('GIT_CONFIG_') or key in ('HOME', 'XDG_CONFIG_HOME')})
    config_options = []
    index = 0
    while index < len(git_options):
        option = git_options[index]
        if option in ('-c', '--config-env'):
            index += 1
            if index >= len(git_options):
                return None
            setting = git_options[index]
            config_options += [option, setting]
        elif option.startswith('-c') and len(option) > 2:
            setting = option[2:]
            config_options.append(option)
        elif option.startswith('--config-env='):
            setting = option[len('--config-env='):]
            config_options.append(option)
        else:
            index += 1
            continue
        if '$' in setting or '`' in setting:
            return None
        if option.startswith('--config-env'):
            _, separator, variable = setting.partition('=')
            if not separator or not re.fullmatch(r'[A-Za-z_][A-Za-z_0-9]*', variable):
                return None
            value = variables.get(variable, os.environ.get(variable))
            if value is None or '$' in value or '`' in value:
                return None
            env[variable] = value
        index += 1
    if any('$' in env.get(key, '') or '`' in env.get(key, '')
           for key in ('HOME', 'XDG_CONFIG_HOME', 'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_SYSTEM',
                       'GIT_CONFIG_PARAMETERS')):
        return None
    if git_dir is not None:
        env['GIT_DIR'] = str(paths(git_dir, base)[1])
    if work_tree is not None:
        env['GIT_WORK_TREE'] = str(paths(work_tree, base)[1])
    try:
        if require_repository:
            probe = subprocess.run(['/usr/bin/git', '-C', str(base), 'rev-parse', '--show-toplevel'],
                                   env=env, capture_output=True, text=True, timeout=2)
            if probe.returncode:
                return None
        result = subprocess.run(['/usr/bin/git', '-C', str(base), *config_options,
                                 'config', *(['--bool'] if bool_value else []), '--get', key], env=env,
                                capture_output=True, text=True, timeout=2)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result


def sparse_enabled(base, git_dir=None, work_tree=None, variables=None, git_options=()):
    """Read effective sparse state; unknown state fails closed."""
    result = git_config_result(base, 'core.sparseCheckout', git_dir, work_tree,
                               variables, git_options, bool_value=True)
    if result is None:
        return True
    if result.returncode == 1 and not result.stdout.strip():
        return False
    return result.returncode != 0 or result.stdout.strip() == 'true'


def paths(path, base):
    expanded = os.path.expandvars(os.path.expanduser(path))
    expanded = expanded.replace('\ue000', '$')  # Literal single-quoted dollar, after expansion.
    lexical = Path(os.path.abspath(os.path.join(str(base), expanded)))
    return lexical, lexical.resolve(strict=False)


def agents_parts(path, base):
    found = []
    for candidate in paths(path, base):
        parts = candidate.parts
        lowered = tuple(part.casefold() for part in parts)
        if ".agents" in lowered:
            found.append(lowered[lowered.index(".agents") + 1 :])
    return found


def protected_write(path, base, expand=True):
    if expand:
        # Shell braces always expand; globs (zsh `(a|b)`/`<1-9>` widened to `*`) hit existing paths.
        brace = re.search(r'\{([^{}]*,[^{}]*)\}', path)
        if brace:
            options = brace.group(1).split(',')
            return len(options) > 16 or any(
                protected_write(path[:brace.start()] + option + path[brace.end():], base)
                for option in options)
        if re.search(r'\{[^{}]*\.\.[^{}]*\}', path):
            return True  # Sequence braces are not expanded statically.
        pattern = re.sub(r'\([^()]*\)|<[0-9]*-[0-9]*>', '*', path)
        if glob.has_magic(pattern):
            for count, match in enumerate(glob.iglob(str(paths(pattern, base)[0]), recursive=True)):
                if count >= 1000 or protected_write(match, base, expand=False):
                    return True
    if protected_git_file(path, base):
        return True
    for part in agents_parts(path, base):
        if len(part) >= 2 and part[:2] == ("work-items", "evidence"):
            if any(re.fullmatch(r'revision-[0-9]+-input-manifest\.json', item) for item in part[3:]):
                return True
            continue
        if part and part[0] in ("reports", "artifacts"):
            continue
        if len(part) >= 2 and part[:2] in (
            ("docs", "exec-plans"), ("docs", "product-specs"), ("docs", "troubleshooting")
        ):
            continue
        return True
    return False


def protected_tree(path, base):
    """A directory operation can replace or move a protected manifest below it."""
    if protected_write(path, base):
        return True
    if has_agents(base):
        controls = git_control_paths(base)
        if controls and any(control.is_relative_to(candidate)
                            for candidate in paths(path, base) for control in controls):
            return True
    if not any(part[:2] == ('work-items', 'evidence') for part in agents_parts(path, base)):
        return False
    for candidate in paths(path, base):
        if candidate.is_dir() and any(candidate.rglob('revision-*-input-manifest.json')):
            return True
    return False


def git_apply_paths_safe(args, command_base, target_bases):
    """Ask Git to list patch paths; never apply it or run patch input as code."""
    options, patch_files = [], []
    queries, force_apply = set(), False
    index = 0
    while index < len(args):
        arg = args[index]
        if arg == '--':
            patch_files.extend(args[index + 1:])
            break
        if arg in ('--check', '--stat', '--numstat', '--summary'):
            queries.add(arg)
            index += 1
        elif arg in ('--no-check', '--no-stat', '--no-numstat', '--no-summary'):
            queries.discard('--' + arg[5:])
            index += 1
        elif arg == '--apply':
            force_apply = True
            index += 1
        elif (arg in ('-R', '--reverse', '--cached', '--index', '--3way', '--reject',
                      '--recount', '--unidiff-zero', '--no-add') or
              arg.startswith(('--include=', '--exclude='))):
            index += 1
        elif re.fullmatch(r'-p[0-9]+', arg) or arg.startswith('--directory='):
            options.append(arg)
            index += 1
        elif arg in ('-p', '--directory') and index + 1 < len(args):
            options.extend(args[index:index + 2])
            index += 2
        elif arg in ('--include', '--exclude') and index + 1 < len(args):
            index += 2  # Probe the whole patch in both directions, ignoring filters.
        elif arg.startswith('-'):
            return False  # Unknown path semantics; do not pass mutating flags to Git.
        else:
            patch_files.append(arg)
            index += 1
    if queries and not force_apply:
        return True
    if not patch_files:
        return False  # stdin or an unknown producer may change managed files.
    env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    env.update(GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_SYSTEM='/dev/null',
               GIT_CONFIG_NOSYSTEM='1')
    for filename in patch_files:
        path = paths(filename, command_base)[0]
        if ('$' in filename or '`' in filename or path.is_symlink() or not path.is_file()
                or path.stat().st_size > 1024 * 1024):
            return False
        for reverse in (False, True):
            try:
                probe = subprocess.run(['/usr/bin/git', 'apply', '--numstat', '-z', *options,
                                        *(['-R'] if reverse else []), str(path)],
                                       cwd=command_base, env=env, capture_output=True, timeout=2)
            except (OSError, subprocess.TimeoutExpired):
                return False
            if probe.returncode or not probe.stdout or len(probe.stdout) > 1024 * 1024:
                return False
            for record in probe.stdout.split(b'\0'):
                if not record:
                    continue
                target = record.split(b'\t', 2)[-1].decode('utf-8', 'surrogateescape')
                if target and ('$' in target or any(
                    protected_write(target, target_base) for target_base in target_bases
                )):
                    return False
    return True


def destination_path(source, destination, base):
    target = paths(destination, base)[0]
    if destination.endswith('/') or target.is_dir():
        return str(target / Path(source.rstrip('/')).name)
    return destination


def copied_protected_content(source, destination, base):
    """Check where existing source files would land, including directory merges."""
    if protected_write(destination, base):
        return True
    if not any(part[:2] == ('work-items', 'evidence') for part in agents_parts(destination, base)):
        controls = git_control_paths(base) if has_agents(base) else None
        if controls is None:
            if not any('.git' in candidate.parts or (candidate / '.git').exists()
                       for candidate in paths(destination, base)):
                return False
        elif not any(control.is_relative_to(candidate) for control in controls
                     for candidate in paths(destination, base)):
            return False
    origin = paths(source, base)[0]
    if not origin.is_dir():
        return False
    return any(protected_write(str(Path(destination) / child.relative_to(origin)), base)
               for child in origin.rglob('*') if child.is_file())


def evidence_directory(path, base):
    return any(part[:2] == ('work-items', 'evidence') and len(part) <= 3
               for part in agents_parts(path, base))


def git_path_touches_agents(path, base):
    return path in (':/', ':(top)') or path.startswith((':(', ':!', ':^')) or deletes_agents(path, base) or protected_tree(path, base)


def git_short_flag(args, flag):
    return any(re.fullmatch(r'-[A-Za-z]*' + re.escape(flag) + r'[A-Za-z]*', arg)
               for arg in args if not arg.startswith('--'))


def git_command_position(args):
    """Only options before the Git subcommand can change its cwd or config."""
    index = 0
    while index < len(args):
        option = args[index]
        if option in ('-C', '-c', '--git-dir', '--work-tree', '--config-env', '--namespace'):
            index += 2
        elif (option.startswith(('-C', '-c')) and len(option) > 2 or
              option.startswith(('--git-dir=', '--work-tree=', '--config-env=',
                                 '--namespace=', '--exec-path=')) or
              option in ('--no-pager', '-P', '-p', '--paginate', '--no-replace-objects',
                         '--literal-pathspecs', '--glob-pathspecs',
                         '--icase-pathspecs', '--noglob-pathspecs',
                         '--no-optional-locks', '--no-lazy-fetch', '--no-advice',
                         '--bare', '--exec-path', '--html-path', '--man-path',
                         '--info-path')):
            index += 1
        elif option.startswith('-'):
            return -1  # An unknown global option may still precede a mutating command.
        else:
            break
    return index


def git_config_assignment(args):
    """Find the actual Git config key/value, excluding optional value patterns."""
    index = 1 if args[:1] in (['set'], ['add']) else 0
    while index < len(args):
        option = args[index]
        if option in ('-f', '--file', '--blob', '--type', '--default'):
            index += 2
        elif option.startswith('-'):
            index += 1
        else:
            break
    return tuple(args[index:index + 2]) if index + 1 < len(args) else None


def find_roots(args):
    """Search roots: after -H/-L/-P-style options (BSD `-f root`), before the expression."""
    roots, index = [], 0
    while index < len(args):
        if args[index] in ('-f', '-D') and index + 1 < len(args):
            roots += [args[index + 1]] if args[index] == '-f' else []
            index += 2
        elif re.fullmatch(r'-[HLPEXdsx]+|-O[0-9]*|-D.+', args[index]):
            index += 1
        else:
            break
    while index < len(args) and not args[index].startswith(('-', '(', '!', ',')):
        roots.append(args[index])
        index += 1
    return roots or ['.']


def deletes_agents(path, base):
    brace = re.search(r'\{([^{}]*,[^{}]*)\}', path)
    if brace:
        options = brace.group(1).split(',')
        if len(options) > 16:
            return True
        return any(deletes_agents(path[:brace.start()] + option + path[brace.end():], base)
                   for option in options)
    roots = [ROOT_AGENTS]
    roots.extend(parent / '.agents' for parent in (base, *base.parents) if (parent / '.agents').exists())
    for target in paths(path, base):
        pattern = str(target).casefold()
        if (target / '.agents').exists():
            return True
        if glob.has_magic(str(target)) and any(
            (Path(match) / '.agents').exists() or
            any(part.casefold() == '.agents' for part in Path(match).resolve(strict=False).parts)
            for match in glob.iglob(str(target))
        ):
            return True
        if any(part.casefold() == '.agents' for part in target.parts):
            return True
        for agents in roots:
            name = str(agents).casefold()
            if fnmatch.fnmatchcase(name, pattern) or any(
                fnmatch.fnmatchcase(str(parent).casefold(), pattern) for parent in agents.parents
            ):
                return True
    return False


def literal_operand(word, variables):
    """Resolve only literal shell words and known simple variables."""
    quoted = []
    quote = None
    for char in word:
        if char in ("'", '"'):
            if quote == char:
                quote = None
            elif quote is None:
                quote = char
        quoted.append('\ue000' if char == '$' and quote == "'" else char)
    if quote:
        return word  # The CST caller rejects incomplete quoting.
    try:
        pieces = shlex.split(''.join(quoted))
    except ValueError:
        return word
    if len(pieces) == 1:
        word = pieces[0]
    def replace_variable(match):
        name = match.group(1) or match.group(2)
        return variables.get(name, match.group(0))
    word = re.sub(r"\$\{([A-Za-z_][A-Za-z_0-9]*)\}|\$([A-Za-z_][A-Za-z_0-9]*)",
                  replace_variable, word)
    return re.sub(r"\[([A-Za-z0-9_.-])\]", r"\1", word)


def python_code_blocked(code, base):
    def string_arg(call, index=0):
        if len(call.args) > index and isinstance(call.args[index], ast.Constant) and isinstance(call.args[index].value, str):
            return call.args[index].value
        return None

    for node in ast.walk(ast.parse(code)):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Name) and func.id == "open":
            path = string_arg(node)
            mode = string_arg(node, 1)
            for keyword in node.keywords:
                if keyword.arg == "mode" and isinstance(keyword.value, ast.Constant):
                    mode = keyword.value.value
            if path and isinstance(mode, str) and any(flag in mode for flag in "wax+") and protected_write(path, base):
                return True
        if not isinstance(func, ast.Attribute):
            continue
        if isinstance(func.value, ast.Name) and func.value.id in ("os", "shutil") and func.attr in ("remove", "unlink", "rmdir", "rmtree"):
            path = string_arg(node)
            if path and protected_write(path, base):
                return True
        owner = func.value
        if isinstance(owner, ast.Call) and isinstance(owner.func, ast.Name) and owner.func.id == "Path":
            path = string_arg(owner)
            if not path:
                continue
            if func.attr in ("write_text", "write_bytes", "unlink", "rmdir", "mkdir", "touch") and protected_write(path, base):
                return True
            if func.attr == "open":
                mode = string_arg(node) or "r"
                if any(flag in mode for flag in "wax+") and protected_write(path, base):
                    return True
    return False


def git_alias_blocked(alias, operands, base, shell_base, variables, git_options,
                      git_dir, work_tree, seen=(), budget=None, stdin_source=None):
    if not alias or '$' in alias or '`' in alias:
        return True
    if alias.startswith('!'):
        code = alias[1:] + (' ' + shlex.join(operands) if operands else '')
        if code.startswith('git '):
            code = 'git ' + shlex.join(git_options) + ' ' + code[4:]
        elif git_options:
            return True  # Cannot transfer Git's per-command options into arbitrary shell code.
        return shell_blocked(code, shell_base, inherited_variables=variables,
                             alias_seen=seen, budget=budget,
                             inherited_stdin_source=stdin_source)
    try:
        words = shlex.split(alias)
    except ValueError:
        return True
    if not words or len(seen) >= 8 or words[0] in seen:
        return True
    if words[0] not in GIT_BUILTINS:
        nested = git_config_result(base, 'alias.' + words[0], git_dir, work_tree,
                                   variables, git_options, require_repository=False)
        if nested is None or nested.returncode not in (0, 1):
            return True
        if nested.returncode == 0:
            return git_alias_blocked(nested.stdout.strip(), words[1:] + list(operands),
                                     base, shell_base, variables, git_options,
                                     git_dir, work_tree, seen + (words[0],), budget,
                                     stdin_source)
    code = 'git ' + shlex.join(list(git_options) + words + list(operands))
    return shell_blocked(code, shell_base, expand_alias=False,
                         inherited_variables=variables, alias_seen=seen, budget=budget,
                         inherited_stdin_source=stdin_source)


def command_blocked(segment, state, expand_alias, alias_seen, budget,
                    mentioned_agents=False, pipeline_input=False, argv_variables=None,
                    split_flags=None):
    base = state['base']
    variables = state['variables']
    argv_variables = variables if argv_variables is None else argv_variables
    directories = state['directories']
    split_flags = list(split_flags or [False] * len(segment))
    if len(split_flags) != len(segment):
        return True
    def drop(count):
        nonlocal segment, split_flags
        if any(split_flags[:count]):
            raise ValueError('wrapper operand changes argv')
        segment = segment[count:]
        split_flags = split_flags[count:]
    def directory(value, current, physical=False):
        if not value or '$' in value or '`' in value:
            return None
        if not os.path.isabs(value) and current is None:
            return None
        cdpath = variables.get('CDPATH', os.environ.get('CDPATH', ''))
        if cdpath and not os.path.isabs(value) and not value.startswith('.') and '/' not in value:
            return None
        return paths(value, current)[int(physical)]
    if not segment:
        return False
    parent_builtin = True
    while segment:
        first = os.path.basename(literal_operand(segment[0], argv_variables))
        if first not in ("sudo", "doas", "env", "command", "nohup", "exec",
                         "timeout", "gtimeout", "nice", "stdbuf", "caffeinate",
                         "arch", "xcrun", "busybox", "builtin", "parallel", "watch",
                         "script", "noglob", "nocorrect", "coproc", "repeat", "time", "-"):
            break
        wrapper = first
        if wrapper not in ('command', 'builtin', 'noglob', 'nocorrect', 'repeat', 'time', '-'):
            parent_builtin = False
        drop(1)
        value_options = {'sudo': ('-g', '-u', '-h'), 'doas': ('-u',),
                         'exec': ('-a',), 'nice': ('-n', '--adjustment'),
                         'timeout': ('-s', '--signal', '-k', '--kill-after'),
                         'gtimeout': ('-s', '--signal', '-k', '--kill-after'),
                         'watch': ('-n', '--interval'), 'script': ('-q',)}
        while segment and segment[0].startswith('-'):
            option = segment[0]
            if wrapper == 'time' and (option in ('-o', '--output') or
                                      option.startswith(('--output=', '-o'))):
                # time writes its report to this file; it is a protected write target.
                if option in ('-o', '--output'):
                    if len(segment) < 2:
                        return True
                    target, count = segment[1], 2
                else:
                    target = option.split('=', 1)[1] if option.startswith('--output=') else option[2:]
                    count = 1
                target = literal_operand(target, argv_variables)
                if not target or '$' in target or '`' in target or protected_write(target, base):
                    return True
                drop(count)
            elif option in value_options.get(wrapper, ()) and len(segment) > 1:
                drop(2)
            elif wrapper == 'env' and option.startswith('--chdir='):
                base = directory(literal_operand(option.split('=', 1)[1], argv_variables), base)
                drop(1)
            elif wrapper == 'watch' and re.fullmatch(r'-n[0-9]+', option):
                drop(1)
            elif wrapper == 'nice' and (re.fullmatch(r'-n[+-]?[0-9]+', option) or option.startswith('--adjustment=')):
                drop(1)
            elif wrapper == 'stdbuf' and re.fullmatch(r'-[ioe].+', option):
                drop(1)
            elif wrapper == 'time' and option in ('-l', '-a', '-h'):
                drop(1)
            elif option in ('--', '-i', '--ignore-environment', '-p', '-E', '-n', '-q'):
                drop(1)
            elif option in ('-u', '--unset') and len(segment) > 1:
                drop(2)
            elif wrapper == 'command' and option in ('-v', '-V'):
                return False
            else:
                return True
        if wrapper in ('timeout', 'gtimeout') and segment and re.fullmatch(r'[0-9]+(?:\.[0-9]+)?[smhd]?', segment[0]):
            drop(1)
        if wrapper == 'repeat':
            if not segment or not re.fullmatch(r'[0-9]+', segment[0]):
                return True
            drop(1)
        if wrapper == 'arch' and segment and segment[0].startswith('-'):
            drop(1)
        if wrapper == 'script' and segment and segment[0].startswith('/'):
            drop(1)
        if wrapper == 'parallel':
            if ':::' in segment and any(deletes_agents(value, base) for value in segment[segment.index(':::') + 1:]):
                return True
            if ':::' in segment:
                if any(split_flags[segment.index(':::') + 1:]):
                    raise ValueError('parallel operand changes argv')
                split_flags = split_flags[:segment.index(':::')]
                segment = segment[:segment.index(':::')]
        while wrapper == 'env' and segment:
            assignment = re.fullmatch(r'([A-Za-z_][A-Za-z_0-9]*)=(.*)', segment[0])
            if not assignment:
                break
            variables[assignment.group(1)] = literal_operand(assignment.group(2), argv_variables)
            drop(1)
    if not segment:
        return False
    name = os.path.basename(literal_operand(segment[0], argv_variables))
    if split_flags[0]:
        return True
    if name in ('rm', 'mv', 'cp', 'ln', 'install', 'rsync', 'ditto', 'git',
                'bash', 'zsh', 'sh', 'dash', 'ksh', 'eval', 'source', '.',
                'xargs', 'find', 'sed', 'perl', 'dd', 'curl', 'tee',
                'truncate', 'unlink', 'tar', 'unzip', 'touch', 'mkdir') and any(split_flags[1:]):
        return True
    if base is None and name not in ('cd', 'pushd', 'popd'):
        return name in ('rm', 'mv', 'cp', 'ln', 'install', 'rsync', 'tee', 'sed',
                        'perl', 'find', 'git', 'dd', 'truncate', 'unlink', 'tar',
                        'unzip', 'ditto', 'patch', 'curl', 'touch', 'mkdir', 'cd',
                        'pushd', 'popd')
    if '$' in name or '`' in name:
        return True  # An unresolved command name can execute a destructive command.
    args = [literal_operand(arg, argv_variables) for arg in segment[1:]]
    incoming_cat_taint = state.get('cat_resolution_unknown', False)
    if parent_builtin and name in ('alias', 'enable', 'disable'):
        # Aliases and enable/disable change what `exec` and its prefixes resolve to. The
        # names travel with the variables so functions and eval see them; '*' = unresolved.
        names = [arg.split('=', 1)[0] for arg in args if name == 'alias' and '=' in arg]
        if name != 'alias' or any('$' in arg or '`' in arg for arg in args):
            names.append('*')
        if names:
            state['variables'][ALIAS_NAMES] = '\0'.join(
                [state['variables'].get(ALIAS_NAMES, '')] + names)
    if parent_builtin and ((name == 'alias' and any(arg.startswith('cat=') for arg in args)) or
                           (name == 'unalias' and ('cat' in args or '-a' in args)) or
                           name in ('eval', 'source', '.') or
                           (name == 'unset' and 'PATH' in args)):
        state['cat_resolution_unknown'] = True
    expanded_segment = [segment[0]] + args
    for index, arg in enumerate(expanded_segment[:-1]):
        if arg in ("\0>", "\0>>", "\0>|", "\0>&", "\0&>", "\0&>>") and (
            '$' in expanded_segment[index + 1] or '`' in expanded_segment[index + 1] or
            protected_write(expanded_segment[index + 1], base)
        ):
            return True
    if name == 'pushd':
        if not args:
            return True  # Stack rotation needs shell state we do not model.
        directories.append(base)
        state['base'] = directory(args[0], base)
        return False
    if name == 'popd':
        if not directories:
            return False
        state['base'] = directories.pop()
        return False
    if name == "cd":
        cd_args = list(args)
        physical = False
        while cd_args and cd_args[0] in ('-L', '-P', '--'):
            physical = cd_args[0] == '-P' or physical
            cd_args.pop(0)
        if len(cd_args) > 1 or (cd_args and cd_args[0].startswith('-') and cd_args[0] != '-'):
            state['base'] = None
        else:
            target = cd_args[0] if cd_args else variables.get('HOME', os.environ.get('HOME'))
            if target == '-':
                target = variables.get('OLDPWD', os.environ.get('OLDPWD'))
            previous = base
            state['base'] = directory(target, base, physical)
            if previous is not None:
                variables['OLDPWD'] = str(previous)
        return False
    if name == "export":
        for arg in args:
            assignment = re.match(r"^([A-Za-z_][A-Za-z_0-9]*)=(.*)$", arg)
            if assignment:
                variables[assignment.group(1)] = literal_operand(assignment.group(2), argv_variables)
        return False
    if name in ("bash", "sh", "zsh", "dash", "ksh"):
        code_positions = [index for index, arg in enumerate(args)
                          if re.fullmatch(r'-[a-zA-Z]*c[a-zA-Z]*', arg) and not arg.startswith('--')]
        if code_positions:
            code_args = args[code_positions[0] + 1:]
            if code_args[:1] == ['--']:
                code_args = code_args[1:]
            if name not in ('bash', 'zsh') or not code_args or code_args[0].startswith('$') or shell_blocked(
                code_args[0].replace('\ue000', '$'), base, expand_alias, variables, alias_seen,
                budget=budget, shell=name, inherited_stdin_source=state.get('stdin_source')
            ):
                return True
        else:
            scripts = [arg for arg in args if not arg.startswith('-')]
            if not scripts or scripts[0] == '-':
                # Stdin can be produced by an earlier pipeline segment.
                stdin_source = state.get('stdin_source')
                if stdin_source is not None:
                    if (name not in ('bash', 'zsh') or stdin_source[0] != 'known' or
                            shell_blocked(stdin_source[1], base, expand_alias, variables,
                                          alias_seen, budget=budget, shell=name)):
                        return True
                elif pipeline_input:
                    return True
            elif not (paths(scripts[0], base)[1].is_relative_to(ROOT_AGENTS / 'scripts') or
                      paths(scripts[0], base)[1].is_relative_to(ROOT_AGENTS / 'tests')):
                # An arbitrary script cannot be inspected from this JSON command.
                return True
        return False
    if name in ("source", "."):
        if not args or not (paths(args[0], base)[1].is_relative_to(ROOT_AGENTS / 'scripts') or
                            paths(args[0], base)[1].is_relative_to(ROOT_AGENTS / 'tests')):
            return True
        return False
    if name == "eval":
        code = ' '.join(args).replace('\ue000', '$')
        if not code or '$' in code or shell_blocked(code, base, expand_alias,
                                                   variables, alias_seen, budget=budget,
                                                   inherited_stdin_source=state.get('stdin_source'),
                                                   inherited_cat_resolution_unknown=incoming_cat_taint):
            return True
        return False
    if name == "xargs":
        cursor = 0
        arg_file = False
        while cursor < len(args) and args[cursor].startswith('-'):
            option = args[cursor]
            short_arg_file = re.match(r'^-[0rptx]*a', option)
            if option in ('-a', '--arg-file') or option.startswith('--arg-file=') or (
                short_arg_file
            ):
                arg_file = True
            cursor += 2 if option in ('-I', '--replace', '-n', '--max-args', '-L', '-P', '-s', '-a', '--arg-file') or (
                short_arg_file and short_arg_file.end() == len(option)
            ) else 1
        nested = args[cursor:]
        if nested and os.path.basename(nested[0]) in (
            "rm", "mv", "cp", "ln", "install", "rsync", "ditto", "git", "sh", "bash", "zsh"
        ):
            if arg_file or mentioned_agents or pipeline_input or any('$' in arg for arg in nested) or shell_blocked(
                ' '.join(nested), base, expand_alias, variables, alias_seen, budget=budget
            ):
                return True
        return False
    if re.fullmatch(r"python(?:[0-9]+(?:\.[0-9]+)?)?", name) and "-c" in args:
        code_index = args.index("-c") + 1
        if code_index < len(args) and python_code_blocked(args[code_index], base):
            return True
    target_paths = [arg for arg in args if not arg.startswith("-")]
    if name == 'unlink' and any('$' in path or '`' in path or protected_write(path, base)
                                for path in target_paths):
        return True
    if name == 'dd' and any(
        '$' in arg[3:] or '`' in arg[3:] or protected_write(arg[3:], base)
        for arg in args if arg.startswith('of=')
    ):
        return True
    if name == 'curl':
        outputs = [args[index + 1] for index, arg in enumerate(args[:-1])
                   if arg in ('-o', '--output') or
                   (arg.startswith('-') and not arg.startswith('--') and arg.endswith('o'))]
        outputs += [arg.split('=', 1)[1] for arg in args if arg.startswith('--output=')]
        outputs += [arg[2:] for arg in args if arg.startswith('-o') and len(arg) > 2]
        if any('$' in path or '`' in path or protected_write(path, base) for path in outputs):
            return True
        if any(arg in ('-O', '--remote-name') for arg in args) and protected_tree('.', base):
            return True
    if name in ('tar', 'unzip', 'ditto'):
        extracts = (name == 'tar' and any('x' in arg.lstrip('-') for arg in args[:1]
                                         if arg and not arg.startswith('--'))) or (
            name == 'tar' and any('x' in arg[1:] for arg in args
                                  if arg.startswith('-') and not arg.startswith('--'))) or (
            name == 'tar' and '--extract' in args) or (
            name == 'unzip' and not any(arg in ('-l', '-v', '-t', '-Z') for arg in args)) or (
            name == 'ditto' and '-x' in args)
        if extracts:
            if name == 'ditto':
                destination = target_paths[-1] if target_paths else '.'
            else:
                destinations = [args[index + 1] for index, arg in enumerate(args[:-1])
                                if arg in ('-C', '--directory', '-d')]
                destinations += [arg.split('=', 1)[1] for arg in args
                                 if arg.startswith('--directory=')]
                destination = destinations[-1] if destinations else '.'
            if ('$' in destination or '`' in destination or
                    deletes_agents(destination, base) or protected_tree(destination, base) or
                    any(part[:2] == ('work-items', 'evidence')
                        for part in agents_parts(destination, base))):
                return True
    if name == 'find' and any(option in args for option in ('-exec', '-execdir')):
        roots = find_roots(args)
        for index, arg in enumerate(args):
            if arg not in ('-exec', '-execdir'):
                continue
            nested = []
            for word in args[index + 1:]:
                if word in (';', '+'):
                    break
                nested.append(word)
            if not nested:
                return True
            if (any('$' in path or '`' in path or deletes_agents(path, base) for path in roots) and
                    os.path.basename(nested[0]) in ('rm', 'mv', 'cp', 'ln', 'install',
                                                    'dd', 'truncate', 'unlink', 'git',
                                                    'sh', 'bash', 'zsh')):
                return True
            local = dict(state, variables=dict(variables), directories=list(directories))
            if command_blocked(nested, local, expand_alias, alias_seen, budget):
                return True
    if name == 'patch' and has_agents(base) and '--dry-run' not in args:
        return True  # Patch input may name managed files; only its read-only mode is supported.
    if name in ('mkdir', 'touch', 'truncate'):
        references = {index + 1 for index, arg in enumerate(args[:-1])
                      if name in ('touch', 'truncate') and arg in ('-r', '--reference')}
        targets = [arg for index, arg in enumerate(args)
                   if index not in references and not arg.startswith('-')]
        if any('$' in target or '`' in target or protected_write(target, base)
               for target in targets):
            return True
    target_directories = [args[index + 1] for index, arg in enumerate(args[:-1])
                          if arg in ("-t", "--target-directory")]
    target_directories += [arg.split("=", 1)[1] for arg in args
                           if arg.startswith("--target-directory=")]
    target_directories += [arg[2:] for arg in args if arg.startswith("-t") and len(arg) > 2]
    if name in ("ln", "cp", "mv", "install", "rsync", "tee", "ditto") and any(
        '$' in p or '`' in p for p in target_paths + target_directories
    ):
        return True
    destination = target_directories[0] if target_directories else (target_paths[-1] if target_paths else '')
    sources = ([p for p in target_paths if p not in target_directories] if target_directories
               else target_paths[:-1])
    writes = [destination_path(source, destination, base) for source in sources] if destination else []
    if name == 'cp' and destination:
        writes = [destination if source.rstrip('/').endswith('/.') else write
                  for source, write in zip(sources, writes)]
    if name == 'rsync' and destination:
        writes = [destination if source.endswith('/') else write
                  for source, write in zip(sources, writes)]
    if name == 'ditto' and destination:
        writes = [str(paths(destination, base)[0]) if paths(source, base)[0].is_dir()
                  else destination_path(source, destination, base) for source in sources]
    if name == "ln" and destination and (
        any(protected_tree(p, base) for p in sources) or
        any(protected_tree(p, base) for p in writes)
    ):
        return True
    if name == "rm" and any('$' in p or deletes_agents(p, base) for p in target_paths):
        return True
    if name == "mv" and destination and (
        any(protected_tree(p, base) for p in sources) or
        any(protected_tree(p, base) for p in writes)
    ):
        return True
    if name in ("cp", "install") and any(protected_write(p, base) for p in writes):
        return True
    if name == 'cp' and ('--link' in args or any(
        'l' in arg[1:] for arg in args if arg.startswith('-') and not arg.startswith('--')
    )):
        if any(protected_tree(p, base) for p in sources):
            return True
    check_copied_content = name in ('cp', 'mv', 'install', 'ditto') or (
        name == 'rsync' and not agents_parts(destination, base)
    ) or (name == 'rsync' and any(part[:2] == ('work-items', 'evidence')
                                for part in agents_parts(destination, base)))
    if check_copied_content and destination and any(
        copied_protected_content(source, write, base) for source, write in zip(sources, writes)
    ):
        return True
    if name == 'cp' and destination and evidence_directory(destination, base) and any(
        not paths(source, base)[0].exists() and any(a in ('-r', '-R', '--recursive') for a in args)
        for source in sources
    ):
        return True  # An unknown directory may contain a protected manifest.
    if name == 'rsync' and destination:
        link_destinations = [args[index + 1] for index, arg in enumerate(args[:-1]) if arg == '--link-dest']
        link_destinations += [arg.split('=', 1)[1] for arg in args if arg.startswith('--link-dest=')]
        dest_base = paths(destination, base)[0]
        if any('$' in link or '`' in link or protected_tree(link, dest_base) or
               protected_tree(link, base) for link in link_destinations):
            return True
    if name == 'rsync':
        # Side outputs; getopt_long prefixes (`--backup-d`, `--log`) are checked as every match.
        side_outputs = ('backup-dir', 'write-batch', 'only-write-batch', 'log-file')
        for index, arg in enumerate(args):
            option, separator, value = arg[2:].partition('=')
            matches = [side for side in side_outputs if arg.startswith('--') and option and
                       side.startswith(option) and option != 'backup']
            if not matches:
                continue
            if not separator:
                value = args[index + 1] if index + 1 < len(args) else ''
            if '$' in value or '`' in value or any(
                protected_tree(value, paths(destination, base)[0] if destination else base)
                if match == 'backup-dir' else
                protected_write(value, base) or protected_write(value + '.sh', base)
                for match in matches
            ):
                return True
    if name == "tee" and any(protected_write(p, base) for p in target_paths):
        return True
    if name == "sed" and any(arg == "-i" or arg.startswith("-i") or arg == "--in-place" or
                             arg.startswith("--in-place=") for arg in args):
        if any(protected_write(p, base) for p in target_paths):
            return True
    if name == "perl" and any(re.fullmatch(r"-[pnlw]*i(?:\.[^/]*)?", arg) for arg in args):
        if any(protected_write(p, base) for p in target_paths):
            return True
    if name == "find" and "-delete" in args and any(
            '$' in p or '`' in p or deletes_agents(p, base) for p in find_roots(args)):
        return True
    if name == "git":
        shell_base = base
        command_position = git_command_position(args)
        if command_position < 0:
            return True
        git_command = args[command_position] if command_position < len(args) else ''
        git_args = args[command_position + 1:]
        for index, arg in enumerate(args[:command_position]):
            if arg == '-C' and index + 1 < command_position:
                base = paths(args[index + 1], base)[0]
            elif arg.startswith('-C') and len(arg) > 2:
                base = paths(arg[2:], base)[0]
        git_cwd = base
        if git_command == 'clone':
            operands = [arg for arg in git_args if not arg.startswith('-')]
            if len(operands) >= 2 and (protected_tree(operands[-1], git_cwd) or
                                       deletes_agents(operands[-1], git_cwd) or
                                       any(part[:2] == ('work-items', 'evidence')
                                           for part in agents_parts(operands[-1], git_cwd))):
                return True
            if len(operands) == 1 and (protected_write('.', git_cwd) or
                                       any(part[:2] == ('work-items', 'evidence')
                                           for part in agents_parts('.', git_cwd))):
                return True
        if git_command == 'format-patch':
            outputs = [git_args[index + 1] for index, arg in enumerate(git_args[:-1])
                       if arg in ('-o', '--output-directory')]
            outputs += [arg.split('=', 1)[1] for arg in git_args
                        if arg.startswith('--output-directory=')]
            outputs += [arg[2:] for arg in git_args if arg.startswith('-o') and len(arg) > 2]
            if any('$' in path or '`' in path or protected_write(path, git_cwd)
                   for path in outputs):
                return True
            if not outputs and '--stdout' not in git_args and protected_write('.', git_cwd):
                return True
        mutates = git_command in ("clean", "rm", "mv", "checkout", "switch", "worktree",
                                  "checkout-index", "read-tree", "restore", "reset", "stash", "bisect",
                                  "update-index")
        if git_command == 'sparse-checkout':
            mutates = mutates or bool(git_args and git_args[0] in ('set', 'add', 'reapply', 'init'))
        work_tree = variables.get('GIT_WORK_TREE')
        git_dir = variables.get('GIT_DIR')
        for index, arg in enumerate(args[:command_position]):
            if arg in ('--work-tree', '--git-dir'):
                value = args[index + 1] if index + 1 < len(args) else ''
                if arg == '--work-tree': work_tree = value
                else: git_dir = value
            elif arg.startswith('--work-tree='):
                work_tree = arg.split('=', 1)[1]
            elif arg.startswith('--git-dir='):
                git_dir = arg.split('=', 1)[1]
        if mutates and ((work_tree is not None and (not work_tree or '$' in work_tree)) or
                        (git_dir is not None and (not git_dir or '$' in git_dir or work_tree is None))):
            return True
        if work_tree is not None:
            base = paths(work_tree, base)[1]
        if git_command == 'am' and (has_agents(git_cwd) or has_agents(base)):
            return True  # Mailbox patch targets are not available as a bounded path list.
        if git_command == 'apply' and (has_agents(git_cwd) or has_agents(base)):
            if not git_apply_paths_safe(git_args, git_cwd, (git_cwd, base)):
                return True
        output_args = git_args[:git_args.index('--')] if '--' in git_args else git_args
        if output_args:
            outputs = [output_args[i + 1] for i, arg in enumerate(output_args[:-1])
                       if arg == '--output']
            outputs += [arg.split('=', 1)[1] for arg in output_args
                        if arg.startswith('--output=')]
            if any('$' in output or '`' in output or protected_write(output, git_cwd)
                   for output in outputs):
                return True
        if has_agents(base):
            sparse_key = re.compile(r'^core\.sparsecheckout(?:cone)?$', re.I)
            if git_command == 'config':
                config_args = git_args
                keys = [arg for arg in config_args if sparse_key.fullmatch(arg)]
                read_options = ('--get', '--get-all', '--get-regexp', '--list', '-l')
                reads = any(arg in read_options for arg in config_args)
                if not reads:
                    assignment = git_config_assignment(config_args)
                    if assignment and assignment[0].casefold() == 'core.worktree':
                        return True
                    if assignment and re.fullmatch(r'alias\.[A-Za-z0-9_.-]+',
                                                   assignment[0], re.I) and git_alias_blocked(
                        assignment[1], (), base, shell_base, variables,
                        args[:command_position], git_dir, work_tree, budget=budget
                    ):
                        return True
                    if '--rename-section' in config_args:
                        section = config_args[config_args.index('--rename-section') + 1:]
                        if len(section) >= 2 and section[1].casefold() == 'alias':
                            return True
                include_key = re.compile(r'^include(?:if\..+)?\.path$', re.I)
                include_keys = [arg for arg in config_args if include_key.fullmatch(arg)]
                include_write = include_keys and (
                    config_args[-1] not in include_keys or
                    any(arg.startswith(('--unset', '--add', '--replace-all', '--remove-section'))
                        for arg in config_args))
                if not reads and (include_write or
                                  ('--rename-section' in config_args and
                                   any(arg.casefold() in ('core', 'include') or
                                       arg.casefold().startswith('includeif.')
                                       for arg in config_args[config_args.index('--rename-section') + 2:]))):
                    return True
                if keys and (len(config_args) > 1 and config_args[-1] not in keys or
                             any(arg.startswith(('--unset', '--add', '--replace-all', '--rename-section'))
                                 for arg in config_args) or
                             config_args[:1] in (['unset'], ['unset-all'])) and not reads:
                    scopes = ('set', '--local', '--worktree', '--bool', '--type=bool')
                    recovery_false = (len(config_args) >= 2 and
                                      config_args[-2] == keys[0] and
                                      config_args[-1].casefold() in ('false', 'no', 'off', '0') and
                                      keys[0].casefold() == 'core.sparsecheckout' and
                                      all(arg in scopes for arg in config_args[:-2]))
                    if not recovery_false:
                        return True
            sparse_inline = any(
                sparse_key.fullmatch(args[index + 1].split('=', 1)[0])
                for index, arg in enumerate(args[:-1]) if arg == '-c'
            ) or any(arg.startswith('-c') and sparse_key.fullmatch(arg[2:].split('=', 1)[0])
                     for arg in args if arg != '-c') or any(
                         arg.startswith('--config-env=') and sparse_key.fullmatch(
                             arg[len('--config-env='):].split('=', 1)[0]) for arg in args
                     )
            sparse_environment = any(
                name.startswith('GIT_CONFIG_KEY_') and sparse_key.fullmatch(value)
                for name, value in variables.items()
            ) or 'core.sparsecheckout' in variables.get('GIT_CONFIG_PARAMETERS', '').casefold()
            updates_worktree = git_command in ('checkout', 'switch', 'merge', 'pull', 'rebase',
                                               'cherry-pick', 'revert') or (
                git_command == 'bisect' and
                (not git_args or git_args[0] not in ('log', 'terms', 'visualize', 'view', 'help')))
            if updates_worktree and (sparse_inline or sparse_environment or
                                     sparse_enabled(base, git_dir, work_tree, variables,
                                                    args[:command_position])):
                return True
            if git_command == 'update-index' and any(
                flag in git_args for flag in ('--skip-worktree', '--assume-unchanged')
            ) and any(git_path_touches_agents(path, base) for path in git_args
                      if not path.startswith('-')):
                return True
            if expand_alias and git_command and git_command not in GIT_BUILTINS:
                if git_command in alias_seen or len(alias_seen) >= 8:
                    return True
                alias = git_config_result(base, 'alias.' + git_command, git_dir, work_tree,
                                          variables, args[:command_position],
                                          require_repository=False)
                if alias is None or alias.returncode not in (0, 1):
                    return True
                if alias.returncode == 0 and git_alias_blocked(
                    alias.stdout.strip(), git_args, base, shell_base, variables,
                    args[:command_position], git_dir, work_tree,
                    alias_seen + (git_command,), budget=budget,
                    stdin_source=state.get('stdin_source')
                ):
                    return True
    if name == "git" and git_command == "clean":
        clean_args = git_args
        clean_paths = []
        skip_next = False
        for arg in clean_args:
            if skip_next:
                skip_next = False
            elif arg in ('-e', '--exclude') or (arg.startswith('-') and 'e' in arg[1:] and not arg.startswith('--')):
                skip_next = True
            elif not arg.startswith('-'):
                clean_paths.append(arg)
        if "-n" not in clean_args and "--dry-run" not in clean_args and (
            not clean_paths or any(git_path_touches_agents(p, base) for p in clean_paths)
        ):
            return True
    if name == "git" and git_command == "rm":
        if any(git_path_touches_agents(p, base) for p in git_args if not p.startswith('-')):
            return True
    if name == "git" and git_command == "mv":
        move_args = [p for p in git_args if not p.startswith('-')]
        if move_args and (any(git_path_touches_agents(p, base) for p in move_args[:-1]) or
                          protected_tree(move_args[-1], base)):
            return True
    if name == "git" and git_command == "restore":
        paths_to_restore = [arg for arg in git_args if not arg.startswith('-')]
        if any(git_path_touches_agents(path, base) for path in paths_to_restore):
            return True
    if name == 'git' and git_command == 'sparse-checkout':
        if git_args and git_args[0] in ('set', 'add', 'reapply', 'init') and any(
            (parent / '.agents').exists() for parent in (base, *base.parents)
        ):
            return True
    if name == "git" and git_command == "reset" and any(arg in ("--hard", "--merge", "--keep") for arg in git_args):
        if any((parent / '.agents').exists() for parent in (base, *base.parents)):
            return True
    if name == "git" and git_command == "stash":
        if git_args[:1] not in (['list'], ['show']) and any((parent / '.agents').exists() for parent in (base, *base.parents)):
            return True
    if name == "git" and git_command == "checkout":
        checkout_args = git_args
        force_args = [arg for arg in checkout_args if not arg.startswith(('-B', '-b'))]
        if (git_short_flag(force_args, 'f') or '--force' in checkout_args) and any((p / '.agents').exists() for p in (base, *base.parents)):
            return True
        if any(git_path_touches_agents(path, base) for path in checkout_args if not path.startswith('-') and path != 'HEAD'):
            return True
    if name == "git" and git_command == "switch" and any(a in ('-f', '--force', '--discard-changes') for a in git_args):
        if any((p / '.agents').exists() for p in (base, *base.parents)):
            return True
    if name == "git" and git_command == "worktree" and "remove" in git_args:
        if any(deletes_agents(p, base) for p in git_args[git_args.index("remove") + 1:] if not p.startswith('-')):
            return True
    if name == "git" and git_command == "checkout-index" and (git_short_flag(git_args, 'f') or '--force' in git_args):
        if (git_short_flag(git_args, 'a') or '--all' in git_args) and any((p / '.agents').exists() for p in (base, *base.parents)):
            return True
        if '--' in git_args and any(git_path_touches_agents(p, base) for p in git_args[git_args.index('--') + 1:]):
            return True
    if name == "git" and git_command == "read-tree" and ('--update' in git_args or git_short_flag(git_args, 'u')) and (
        '--reset' in git_args or git_short_flag(git_args, 'm')
    ):
        if any((p / '.agents').exists() for p in (base, *base.parents)):
            return True
    if name == "rsync" and destination and (
        any(protected_write(p, base) for p in writes) or
        (any(a.startswith("--delete") for a in args) and deletes_agents(destination, base))
    ):
        if evidence_directory(destination, base):
            return True
        if "--delete-excluded" in args:
            return True
        # Allowlist: only --exclude PATH and -f/--filter '- PATH'|'H PATH'|'P PATH'. Clear, risk,
        # show, include, merge, -F, *-from, -C (CVSIGNORE may hold '!') and abbreviations block.
        family = ("filter", "exclude", "exclude-from", "include", "include-from", "files-from",
                  "cvs-exclude", "delete-excluded")
        filters = []
        index = 0
        while index < len(args):
            arg, value = args[index], None
            name = arg[2:].split("=", 1)[0]
            if arg in ("--filter", "--exclude", "-f") and index + 1 < len(args):
                index += 1
                value = args[index]
            elif arg.startswith(("--filter=", "--exclude=")):
                value = arg.split("=", 1)[1]
            elif arg.startswith("-f"):
                value = arg[2:]
            elif arg.startswith("--") and name not in ("filter", "exclude", "delete") and any(
                    option.startswith(name) for option in family):
                return True
            elif not arg.startswith("--") and arg.startswith("-") and set(arg) & set("fFC"):
                return True
            index += 1
            if value is None:
                continue
            if arg.startswith("--exclude"):
                if value.startswith(("+", "!")):
                    return True
                filters.append("- " + value)
            elif value[:2] in ("- ", "H ", "P "):
                filters.append(value)
            else:
                return True
        required = ("config/project-profile.conf", "reports/", "work-items/", "artifacts/",
                    "docs/exec-plans/", "docs/product-specs/", "docs/troubleshooting/")
        if not all(
            "- " + path in filters or ("H " + path in filters and "P " + path in filters)
            for path in required
        ):
            return True
    if name == "git":
        base = shell_base
    return False


RESERVED_COMMAND_WORDS = frozenset((
    'for', 'select', 'time', 'while', 'until', 'if', 'then', 'elif', 'else',
    'fi', 'case', 'esac', 'in', 'function', 'foreach', '{', '}', '[[', ']]', '!'))
ALIAS_NAMES = '\0aliases'  # Not a valid shell variable name.
NEGATION_REWRITE_WORDS = frozenset(('for', 'select', 'time', 'while', 'until', 'if', 'case',
                                    'foreach'))


def rewrite_negated_compounds(tree, raw, shell):
    """Undo the bundled grammar's split of `! for ...`, `! select ...`, `! time ...`.

    The `!` byte is replaced by one space, so every other byte offset (and any here
    document) is unchanged, and the command is parsed again as the real compound.
    The negation itself is returned as the (start, end, type) span of that compound;
    the walker inverts the span's exit status directly instead of calling any user-
    shadowable command. Anything that cannot be re-parsed is returned unchanged, so
    the reserved-word guard still fails closed.
    """
    spans = []
    for _ in range(8):
        target = None
        stack = [tree]
        while stack and target is None:
            node = stack.pop()
            if node['type'] == 'negated_command':
                named = [child for child in node['children'] if child['named']]
                if named and named[0]['type'] == 'command':
                    names = children(named[0], 'name')
                    if names and source(names[0], raw) in NEGATION_REWRITE_WORDS:
                        target = (node, named[0])
            stack.extend(node['children'])
        if target is None:
            break
        node, first = target
        bang = next((child for child in node['children']
                     if not child['named'] and source(child, raw) == '!'), None)
        if bang is None or bang['end_byte'] - bang['start_byte'] != 1:
            return tree, raw, []
        start = first['start_byte']
        unbanged = raw[:bang['start_byte']] + b' ' + raw[bang['end_byte']:]
        try:
            tree1, raw1 = parse(unbanged.decode('utf-8'), shell)
        except ValueError:
            return tree, raw, []
        if raw1 != unbanged:
            return tree, raw, []
        candidates = []
        stack = [tree1]
        while stack:
            item = stack.pop()
            if item['start_byte'] == start and item['type'] not in ('program', 'list'):
                candidates.append(item)
            stack.extend(item['children'])
        if not candidates:
            return tree, raw, []
        outer = max(candidates, key=lambda item: item['end_byte'])
        spans.append((outer['start_byte'], outer['end_byte'], outer['type']))
        tree, raw = tree1, raw1
    # Every span must still name a node of the final tree.
    present = set()
    stack = [tree]
    while stack:
        item = stack.pop()
        present.add((item['start_byte'], item['end_byte'], item['type']))
        stack.extend(item['children'])
    if any(span not in present for span in spans):
        return tree, raw, None
    return tree, raw, spans


NEGATION_CONTAINERS = frozenset((
    'program', 'list', 'pipeline', 'compound_statement', 'subshell', 'do_group',
    'if_statement', 'elif_clause', 'else_clause', 'while_statement', 'for_statement',
    'c_style_for_statement', 'case_item', 'command_substitution', 'process_substitution',
    'function_definition'))


def canonical_heredocs(command):
    """Rewrite quoted here-document delimiters the grammar rejects into same-length tokens.

    The grammar accepts one `'...'` or `\\...` segment, but not split quoting such as
    `<<'! 'E` or a leading blank under `<<-`. Each quoted delimiter word becomes
    `'ZZ..'` (or `\\ZZ..`) and its terminator line the same number of `Z`, so every
    byte offset is kept. Returns the rewritten text and the (word, terminator) spans,
    or no spans when any delimiter cannot be read exactly.
    """
    encoded = command.encode('utf-8')
    blanks = b' \t\n;&|<>()'
    out = bytearray(encoded)
    spans, cursor = [], 0
    for match in re.finditer(rb'(?<![<])<<(-?)(?!<)[ \t]*', encoded):
        if match.start() < cursor:
            continue  # Inside an earlier here-document body.
        index, value, quoted = match.end(), bytearray(), False
        while index < len(encoded) and encoded[index] not in blanks:
            char = encoded[index:index + 1]
            if char == b"'" or encoded[index:index + 2] == b"$'":
                opening = index + (char == b'$')
                end = encoded.find(b"'", opening + 1)
                # ANSI-C `$'...'` is read only without escapes.
                if end < 0 or b'\n' in encoded[index:end] or (
                        char == b'$' and b'\\' in encoded[opening:end]):
                    return command, []
                value += encoded[opening + 1:end]
                index, quoted = end + 1, True
            elif char == b'"':
                end = encoded.find(b'"', index + 1)
                body = encoded[index + 1:end]
                if end < 0 or any(part in body for part in (b'\n', b'\\', b'$', b'`')):
                    return command, []
                value += body
                index, quoted = end + 1, True
            elif char == b'\\':
                if encoded[index + 1:index + 2] in (b'', b'\n'):
                    return command, []
                value += encoded[index + 1:index + 2]
                index, quoted = index + 2, True
            elif char in (b'$', b'`'):
                return command, []
            else:
                value += char
                index += 1
        word = (match.end(), index)
        pad = (index - match.end()) - len(value)
        if not value or not quoted and pad:
            return command, []
        # The body starts on the line after the operator, after any earlier body.
        line = encoded.find(b'\n', index)
        if line < 0:
            return command, []
        start = max(cursor, line + 1)
        while True:
            end = encoded.find(b'\n', start)
            end = len(encoded) if end < 0 else end
            text_start = start
            if match.group(1):
                while encoded[text_start:text_start + 1] == b'\t':
                    text_start += 1
            if encoded[text_start:end] == bytes(value):
                break
            if end == len(encoded):
                return command, []  # No terminator.
            start = end + 1
        cursor = end + 1
        if not quoted:
            continue
        # Extra quoting bytes become blanks after the word.
        if pad == 1:
            token = b'\\' + b'Z' * len(value)
        else:
            token = b"'" + b'Z' * len(value) + b"'"
        out[word[0]:word[1]] = token + b' ' * (pad - len(token) + len(value))
        out[text_start:end] = b'Z' * len(value)
        spans.append(((word[0], word[0] + len(token)), (text_start, end)))
    return bytes(out).decode('utf-8'), spans


def parse_with_negations(command, shell):
    """Parse, retrying with canonical here-document delimiters when the grammar rejects them.

    The retry is used only when every rewritten delimiter and terminator is exactly a
    `heredoc_start` / `heredoc_end` pair of one redirect in the final tree.
    """
    try:
        return parse_negations(command, shell)
    except ValueError:
        canonical, spans = canonical_heredocs(command)
        if not spans:
            raise
        tree, raw, negations = parse_negations(canonical, shell)
        expected = canonical.encode('utf-8')
        # Only the negation fallback's blanked `!` may differ; offsets must be kept.
        if len(raw) != len(expected) or any(
                (have, want) != (0x20, 0x21) for have, want in zip(raw, expected) if have != want):
            raise ValueError('here-document rewrite changed offsets')
        pairs = set()
        stack = [tree]
        while stack:
            item = stack.pop()
            if item['type'] == 'heredoc_redirect':
                starts = [(child['start_byte'], child['end_byte'])
                          for child in item['children'] if child['type'] == 'heredoc_start']
                ends = [(child['start_byte'], child['end_byte'])
                        for child in item['children'] if child['type'] == 'heredoc_end']
                pairs.update((start, end) for start in starts for end in ends)
            stack.extend(item['children'])
        if any(span not in pairs for span in spans):
            raise ValueError('here-document rewrite not confirmed')
        return tree, raw, negations


def parse_negations(command, shell):
    """Parse, falling back to blanking standalone `!` when the grammar rejects it.

    Some negated compounds (e.g. `! case ...`) do not parse at all. Each blanked `!`
    keeps every byte offset of the input; the parser may still drop line continuations,
    so positions are mapped onto its output. A `!` that lands inside a string, comment,
    here-document body or command argument is text and is put back. The compound
    starting right after each remaining `!` is reported as a negation span.
    """
    try:
        return parse(command, shell) + ([],)
    except ValueError:
        encoded = command.encode('utf-8')
        bangs = [match.start() for match in re.finditer(rb'(?:^|(?<=[\s;&|(]))!(?=[ \t])', encoded)]
        # A `!` on a here-document terminator line is text; blanking it would break the
        # delimiter match (e.g. `<<'! E'`).
        heredocs = list(re.finditer(
            rb"<<-?[ \t]*(?:'([^'\n]*)'|\"([^\"\n]*)\"|\\?([^\s;&|<>()'\"]+))", encoded))
        delimiters = {next(group for group in match.groups() if group is not None)
                      for match in heredocs}

        def terminator(position):
            if any(match.start() <= position < match.end() for match in heredocs):
                return True  # Inside the delimiter word itself.
            start = encoded.rfind(b'\n', 0, position) + 1
            end = encoded.find(b'\n', position)
            end = len(encoded) if end < 0 else end
            lines = (encoded[start:end],
                     encoded[start:position] + b' ' + encoded[position + 1:end])
            return any(line.lstrip(b'\t') in delimiters for line in lines)

        bangs = [bang for bang in bangs if not terminator(bang)]
        if not bangs:
            raise

        def blank(positions, joins=True):
            blanked = bytearray(encoded)
            for position in positions:
                blanked[position] = 0x20
                # A line continuation right after `!` only joins whitespace.
                index = position + 1
                while joins:
                    while blanked[index:index + 1] in (b' ', b'\t'):
                        index += 1
                    if blanked[index:index + 2] != b'\\\n':
                        break
                    blanked[index:index + 2] = b'  '
            tree, raw = parse(bytes(blanked).decode('utf-8'), shell)
            # Walk both byte strings; only unquoted line continuations may be missing.
            mapped, index, place = {}, 0, 0
            while index < len(blanked):
                if blanked[index:index + 2] == b'\\\n' and raw[place:place + 2] != b'\\\n':
                    index += 2
                    continue
                if raw[place:place + 1] != blanked[index:index + 1]:
                    raise ValueError('negation fallback changed input')
                mapped[index] = place
                index, place = index + 1, place + 1
            if place != len(raw):
                raise ValueError('negation fallback changed input')
            return tree, raw, [mapped[position] for position in sorted(positions)]

        def container(tree, position):
            node = tree
            while True:
                inner = next((child for child in node['children']
                              if child['start_byte'] <= position < child['end_byte']), None)
                if inner is None:
                    return node['type']
                node = inner

        # Classify every candidate on one blanked parse. Joining the continuation after a
        # `!` that is really inside a comment would pull the next line into it, so a
        # failed attempt is retried without joins for classification only.
        for joins in (True, False):
            try:
                tree, raw, mapped = blank(bangs, joins)
                real = [bang for bang, place in zip(bangs, mapped)
                        if container(tree, place) in NEGATION_CONTAINERS]
                if not real:
                    continue
                tree, raw, mapped = blank(real)
                break
            except ValueError:
                continue
        else:
            raise ValueError('negation fallback failed')
        spans = []
        for place in mapped:
            # The final tree, not the classification pass, must place the `!` in a statement.
            if raw[place:place + 1] != b' ' or container(tree, place) not in NEGATION_CONTAINERS:
                raise ValueError('negation fallback changed input')
            start = place + 1
            while start < len(raw) and raw[start:start + 1] in (b' ', b'\t'):
                start += 1
            found = []
            stack = [tree]
            while stack:
                item = stack.pop()
                if item['start_byte'] == start and item['type'] not in ('program', 'list'):
                    found.append(item)
                stack.extend(item['children'])
            if not found:
                raise ValueError('negation fallback lost its command')
            outer = max(found, key=lambda item: item['end_byte'])
            spans.append((outer['start_byte'], outer['end_byte'], outer['type']))
        return tree, raw, spans


def shell_blocked(command, base, expand_alias=True, inherited_variables=None,
                  alias_seen=(), budget=None, shell=None, inherited_functions=None,
                  out_states=None, inherited_stdin_source=None,
                  inherited_cat_resolution_unknown=False):
    """Inspect CST execution edges without evaluating the shell command."""
    if budget is None:
        budget = [0, 0]
    budget[0] += 1
    if budget[0] > 48:
        return True
    tree, raw, fallback_spans = parse_with_negations(command, shell or 'zsh')
    tree, raw, negated_spans = rewrite_negated_compounds(tree, raw, shell or 'zsh')
    if negated_spans is None:
        return True  # A rewritten negation no longer maps onto the parsed tree.
    negated_spans = set(negated_spans) | set(fallback_spans)
    if fallback_spans:
        present, stack = set(), [tree]
        while stack:
            item = stack.pop()
            present.add((item['start_byte'], item['end_byte'], item['type']))
            stack.extend(item['children'])
        if not set(fallback_spans) <= present:
            return True  # A blanked negation no longer maps onto the parsed tree.
    initial = {'base': base, 'variables': dict(inherited_variables or {}),
               'directories': [], 'functions': dict(inherited_functions or {}),
               'pipeline_input': inherited_stdin_source is not None,
               'mentioned_agents': False, 'stdin_source': inherited_stdin_source,
               'cat_resolution_unknown': inherited_cat_resolution_unknown,
               'exec_stdin': None}
    initial['variables'].setdefault('PWD', str(base))
    if os.environ.get('TMPDIR'):
        initial['variables'].setdefault('TMPDIR', os.environ['TMPDIR'])

    def clone(state):
        return {'base': state['base'], 'variables': dict(state['variables']),
                'directories': list(state['directories']),
                'functions': dict(state['functions']),
                'pipeline_input': state['pipeline_input'],
                'mentioned_agents': state['mentioned_agents'],
                'stdin_source': state['stdin_source'],
                'cat_resolution_unknown': state['cat_resolution_unknown'],
                'exec_stdin': state.get('exec_stdin')}

    def state_key(state):
        return (state['base'], tuple(sorted(state['variables'].items())),
                tuple(state['directories']), tuple(sorted(state['functions'].items())),
                state['stdin_source'], state['pipeline_input'],
                state['mentioned_agents'], state['cat_resolution_unknown'],
                state.get('exec_stdin'))

    def distinct(outcomes):
        return list({(state_key(state), ok): (state, ok)
                     for state, ok in outcomes}.values())

    def expand(nodes, states):
        outcome = [(state, True) for state in states]
        for node in nodes:
            updated = []
            # A sequential next command replaces the previous exit status.
            # Inspect each identical state once, then retain this command's statuses.
            next_states = {state_key(state): state for state, _ in outcome}
            for state in next_states.values():
                updated.extend(visit(node, state))
            outcome = distinct(updated)
            if len(outcome) > 64:
                raise ValueError('too many shell states')
        return outcome

    def substitutions(node, state):
        if node['type'] in ('command_substitution', 'process_substitution'):
            expand(children(node), [clone(state)])
            return
        for child in node['children']:
            substitutions(child, state)

    def word_value(node, state):
        """Resolve only statically known substitutions, preserving all other text."""
        fragment = raw[node['start_byte']:node['end_byte']]
        replacements = []
        def collect(part):
            if part['type'] == 'command_substitution':
                body = ' '.join(source(child, raw) for child in children(part))
                if body == 'pwd':
                    replacements.append((part['start_byte'] - node['start_byte'],
                                         part['end_byte'] - node['start_byte'],
                                         str(state['base']).encode('utf-8')))
                return
            for child in part['children']:
                collect(child)
        collect(node)
        for start, end, replacement in sorted(replacements, reverse=True):
            fragment = fragment[:start] + replacement + fragment[end:]
        return fragment.decode('utf-8')

    def unquoted_expansion(node):
        if node['type'] in ('string', 'raw_string', 'ansi_c_string'):
            return False
        if node['type'] in ('simple_expansion', 'variable_ref'):
            return True
        return any(unquoted_expansion(child) for child in node['children'])

    def exec_stdin_effect(bodies, state):
        """How a redirected command's input redirect affects the shell's later stdin.

        Returns 'persist' when the `exec` builtin itself rebinds stdin, 'none' when the
        redirect only lasts for the command, and 'unknown' for forms whose effect was
        not established. The accepted forms follow harmless Bash 3.2 / zsh probes: Bash
        reaches the builtin through quoting and `command` (not `builtin`); zsh through
        quoting, `builtin`, `noglob`, `nocorrect` and `-` (not `command`). A function
        named like the first word runs instead and restores stdin on return.
        """
        dialect = shell or 'zsh'
        if state['cat_resolution_unknown']:
            return 'unknown'  # eval or source may have defined aliases for `exec`.
        if len(bodies) == 1 and bodies[0]['type'] == 'pipeline':
            # The redirect belongs to the last stage; only zsh runs it in this shell.
            stages = children(bodies[0])
            if dialect != 'zsh' or not stages:
                return 'none'
            bodies = stages[-1:]
        if len(bodies) != 1 or bodies[0]['type'] != 'command':
            return 'none'
        names = children(bodies[0], 'name')
        if len(names) != 1:
            return 'none'
        words = [literal_operand(word_value(part, state), state['variables'])
                 for part in names + children(bodies[0], 'argument')]
        aliases = set(state['variables'].get(ALIAS_NAMES, '').split('\0')) - {''}
        if '*' in aliases or aliases.intersection(words):
            return 'unknown'  # An alias or enable/disable may rename, disable or add `exec`.
        if words[0] in state['functions']:
            return 'none'  # The function runs and its call redirect is restored.
        index = 0
        if dialect == 'bash':
            while index < len(words) and words[index] == 'command':
                index += 1
                while index < len(words) and words[index] == '-p':
                    index += 1
                if index < len(words) and words[index] == '--':
                    index += 1  # Ends options: the next word is the command name.
                elif index < len(words) and words[index] in ('-v', '-V'):
                    return 'none'
                elif index < len(words) and words[index].startswith('-'):
                    return 'unknown'
            # `builtin exec`, `noglob exec` etc. do not rebind Bash's stdin.
            return 'persist' if index < len(words) and words[index] == 'exec' else 'none'
        while index < len(words) and words[index] in ('noglob', 'nocorrect', '-', 'builtin'):
            index += 1
        if index >= len(words) or words[index] != 'exec':
            return 'none'  # Includes any `command` prefix and `builtin -- exec`.
        if any(word in state['functions'] for word in words[1:index + 1]):
            return 'unknown'  # A function behind a prefix may shadow `builtin` or `exec`.
        return 'persist' if index == len(words) - 1 else 'unknown'

    def pipeline_operators(node):
        return [source(part, raw) for part in node['children'] if not part['named']
                and source(part, raw) in ('|', '|&')]

    def literal_cat_stdout(stage, state):
        redirects = children(stage, 'redirect')
        if stage['type'] == 'redirected_statement':
            bodies = children(stage, 'body')
            if len(bodies) != 1:
                return ('unknown', '')
            stage = bodies[0]
            redirects += children(stage, 'redirect')
        if stage['type'] != 'command':
            return ('unknown', '')
        names = children(stage, 'name')
        if len(names) != 1 or children(stage, 'argument') or any(
                part['type'] == 'variable_assignment' for part in children(stage)):
            return ('unknown', '')
        name = source(names[0], raw)
        if name == 'cat' and (state['cat_resolution_unknown'] or 'PATH' in state['variables']):
            return ('unknown', '')
        if name not in ('cat', '/bin/cat') or name in state['functions']:
            return ('unknown', '')
        if redirects:
            if len(redirects) != 1 or redirects[0]['type'] != 'herestring_redirect':
                return ('unknown', '')
            descriptors = children(redirects[0], 'descriptor')
            if descriptors and source(descriptors[0], raw) != '0':
                return ('unknown', '')
            values = [part for part in children(redirects[0]) if part['named']]
            if len(values) != 1 or values[0]['type'] != 'raw_string':
                return ('unknown', '')
            return ('known', literal_operand(source(values[0], raw),
                                             state['variables']).replace('\ue000', '$') + '\n')
        if state['stdin_source'] is None or state['stdin_source'][0] != 'known':
            return ('unknown', '')
        return state['stdin_source']

    def pipeline_outcomes(stages, state, context=None, operators=()):
        """Each stage starts at pipeline entry; only the last can affect its parent."""
        if not stages or len(operators) != len(stages) - 1:
            raise ValueError('empty pipeline')
        context = state if context is None else context
        last = []
        upstream = state['stdin_source']
        for index, stage in enumerate(stages):
            local = clone(state)
            if index:
                local['stdin_source'] = (upstream if operators[index - 1] == '|'
                                         else ('unknown', ''))
                local['pipeline_input'] = True
                local['mentioned_agents'] |= any(
                    '.agents' in source(prior, raw).casefold() for prior in stages[:index])
            upstream = literal_cat_stdout(stage, local)
            visited = visit(stage, local)
            if index == len(stages) - 1:
                last = visited
        result = []
        for local, ok in last:
            parents = (local,) if shell == 'zsh' else (state, local)
            for parent in parents:
                after = clone(parent)
                for key in ('stdin_source', 'pipeline_input', 'mentioned_agents'):
                    after[key] = context[key]
                # zsh runs the last stage in the current shell, so its `exec` stdin stays.
                if (parent is local and shell == 'zsh' and local.get('exec_stdin') and
                        local.get('exec_stdin') != context.get('exec_stdin')):
                    after['stdin_source'] = local['exec_stdin']
                    after['pipeline_input'] = True
                result.append((after, ok))
                if len(stages) > 1:
                    # pipefail and earlier-stage status are not statically known.
                    result.append((clone(after), False))
        return distinct(result)

    def pipeline_stages(node):
        if node['type'] != 'pipeline':
            return [node]
        stages = children(node)
        if not stages:
            raise ValueError('empty pipeline')
        return stages

    def list_remainder(parts, first, outcome):
        previous = first
        for later in (part for part in parts if part['named'] and part is not first):
            operators = [source(part, raw) for part in parts
                         if not part['named'] and
                         previous['end_byte'] <= part['start_byte'] < later['start_byte']
                         and source(part, raw) in ('&&', '||', ';')]
            op = operators[-1] if operators else ';'
            selected, remaining = [], []
            for item, ok in outcome:
                if op == '&&' and not ok or op == '||' and ok:
                    remaining.append((item, ok))
                else:
                    selected.extend(visit(later, item))
            outcome = distinct(selected + remaining)
            previous = later
        return outcome

    def redirect_scope(node):
        if node['type'] != 'redirected_statement':
            return node
        redirects = children(node, 'redirect')
        bodies = children(node, 'body')
        if not (len(bodies) == 1 and bodies[0]['type'] == 'list' and redirects and
                all(redirect['type'] == 'file_redirect' for redirect in redirects)):
            return node
        parts = bodies[0]['children']
        last = next((part for part in reversed(parts) if part['named']), None)
        if last is None or any(redirect['start_byte'] < last['end_byte']
                               for redirect in redirects):
            raise ValueError('unknown redirect scope')
        body = dict(last, field='body')
        scoped = dict(node, start_byte=last['start_byte'],
                      children=[body] + redirects)
        return dict(bodies[0], children=[scoped if part is last else part
                                         for part in parts])

    def visit(node, state):
        if (node['start_byte'], node['end_byte'], node['type']) not in negated_spans:
            return visit_node(node, state)
        # `!` keeps the compound's effects, but its status and whether the body ran at all
        # are not modelled exactly (Bash 3.2 skips a function after `! time`), so both
        # statuses of both the executed and the untouched state are checked.
        before = clone(state)
        states = [item for item, _ in visit_node(node, state)] + [before]
        return distinct([(item, status) for item in states for status in (True, False)])

    def visit_node(node, state):
        budget[1] += 1
        if budget[1] > 4096:
            raise ValueError('CST analysis budget')
        kind = node['type']
        if kind == 'variable_assignment':
            result = clone(state)
            key, _, value = source(node, raw).partition('=')
            result['variables'][key] = literal_operand(value, result['variables'])
            substitutions(node, state)
            return [(result, True)]
        if kind == 'function_definition':
            names, bodies = children(node, 'name'), children(node, 'body')
            if len(names) != 1 or len(bodies) != 1:
                raise ValueError('unsupported function definition')
            result = clone(state)
            result['functions'][source(names[0], raw)] = source(bodies[0], raw)
            return [(result, True)]
        if kind == 'list':
            parts = node['children']
            executable = [child for child in parts if child['named']]
            if not executable:
                return [(state, True)]
            return list_remainder(parts, executable[0], visit(executable[0], state))
        if kind == 'pipeline':
            return pipeline_outcomes(pipeline_stages(node), state,
                                     operators=pipeline_operators(node))
        if kind == 'declaration_command':
            substitutions(node, state)
            result = clone(state)
            for assignment in children(node):
                if assignment['type'] == 'variable_assignment':
                    key, _, value = source(assignment, raw).partition('=')
                    result['variables'][key] = literal_operand(value, result['variables'])
            return [(result, True)]
        if kind == 'command':
            substitutions(node, state)
            local = clone(state)
            argv_variables = dict(state['variables'])
            assignments = [child for child in children(node)
                           if child['type'] == 'variable_assignment']
            def scoped(states):
                for result, _ in states:
                    for assignment in assignments:
                        key = source(assignment, raw).partition('=')[0]
                        if key in state['variables']:
                            result['variables'][key] = state['variables'][key]
                        else:
                            result['variables'].pop(key, None)
                return states
            for assignment in assignments:
                key, _, value = source(assignment, raw).partition('=')
                local['variables'][key] = literal_operand(value, argv_variables)
            names = children(node, 'name')
            if not names:
                return [(local, True)]
            # A correct parse never leaves a reserved word as a command name;
            # seeing one (e.g. `! for ...`, `! time ...`) means the grammar
            # split a compound command, so its real body is not analysable.
            if source(names[0], raw) in RESERVED_COMMAND_WORDS:
                raise ValueError('reserved word in command position')
            words = [word_value(names[0], local)] + [word_value(child, local)
                                              for child in children(node, 'argument')]
            resolved_name = literal_operand(words[0], argv_variables)
            separators = argv_variables.get('IFS', ' \t\n')
            unknown_ifs = '$' in separators or '`' in separators
            word_nodes = names[:1] + children(node, 'argument')
            split_flags = [unquoted_expansion(part) and
                           (unknown_ifs or any(char in literal_operand(word, argv_variables)
                                               for char in separators))
                           for part, word in zip(word_nodes, words)]
            name = os.path.basename(resolved_name)
            if split_flags[0]:
                raise ValueError('unquoted command name changes argv')
            if name in local['functions']:
                budget[0] += 1
                if budget[0] > 48:
                    raise ValueError('recursive function analysis')
                resulting = []
                if shell_blocked(local['functions'][name], local['base'], expand_alias,
                                 local['variables'], alias_seen, budget, shell or 'zsh',
                                 local['functions'], resulting,
                                 inherited_stdin_source=local['stdin_source'],
                                 inherited_cat_resolution_unknown=local['cat_resolution_unknown']):
                    raise ValueError('protected function')
                return scoped(resulting or [(clone(state), True)])
            if name == 'eval':
                values = [literal_operand(word, argv_variables).replace('\ue000', '$')
                          for word in words[1:]]
                if not values or any('$' in value or '`' in value for value in values):
                    raise ValueError('dynamic eval')
                resulting = []
                if shell_blocked(' '.join(values), local['base'], expand_alias,
                                 local['variables'], alias_seen, budget, shell or 'zsh',
                                 local['functions'], resulting,
                                 inherited_stdin_source=local['stdin_source'],
                                 inherited_cat_resolution_unknown=local['cat_resolution_unknown']):
                    raise ValueError('protected eval')
                return scoped(resulting or [(clone(state), True)])
            if command_blocked(words, local, expand_alias, alias_seen, budget,
                               state.get('mentioned_agents', False),
                               state.get('pipeline_input', False), argv_variables,
                               split_flags):
                raise ValueError('protected command')
            if name == 'popd' and not state['directories']:
                return [(clone(state), False)]
            if name in ('cd', 'pushd', 'popd'):
                local['variables']['PWD'] = str(local['base'])
                return scoped([(local, True), (clone(state), False)])
            if name == 'export':
                return scoped([(local, True), (clone(state), False)])
            # Prefix assignments are local to this simple command.
            after = clone(state)
            after['cat_resolution_unknown'] = local['cat_resolution_unknown']
            if ALIAS_NAMES in local['variables']:
                after['variables'][ALIAS_NAMES] = local['variables'][ALIAS_NAMES]
            if name not in ('printf', 'echo', 'true', 'false', ':', 'pwd', 'test', '[', '[['):
                if after['stdin_source'] is not None:
                    after['stdin_source'] = ('unknown', '')
            if name in ('true', ':', 'false') and len(words) == 1:
                return scoped([(after, name != 'false')])
            return scoped([(after, True), (clone(after), False)])
        if kind == 'redirected_statement':
            redirects = children(node, 'redirect')
            bodies = children(node, 'body')
            normalized = redirect_scope(node)
            if normalized is not node:
                return visit(normalized, state)
            stdin_source = None
            for redirect in redirects:
                op = next((source(child, raw) for child in redirect['children']
                           if not child['named']), '')
                dest = children(redirect, 'destination')
                if op in ('>', '>>', '>|', '>&', '&>', '&>>', '<>'):
                    if len(dest) != 1:
                        raise ValueError('unknown redirect target')
                    target = literal_operand(source(dest[0], raw), state['variables'])
                    if '$' in target or '`' in target or protected_write(target, state['base']):
                        raise ValueError('protected redirect')
                substitutions(redirect, state)
                descriptors = children(redirect, 'descriptor')
                if descriptors and source(descriptors[0], raw) != '0':
                    continue  # Another fd; the command still reads the parent's stdin.
                if op in ('<', '<&', '<&-'):
                    stdin_source = ('unknown', '')
                elif op in ('<<', '<<-'):
                    body = next((child for child in children(redirect)
                                 if child['type'] == 'heredoc_body'), None)
                    marker = next((child for child in children(redirect)
                                   if child['type'] == 'heredoc_start'), None)
                    text = source(body, raw) if body else ''
                    if op == '<<-':
                        text = ''.join(line.lstrip('\t') for line in text.splitlines(True))
                    quoted = marker and any(char in source(marker, raw) for char in ("'", '"', '\\'))
                    literal_body = body and not body['children'] and '\\' not in text
                    stdin_source = ('known', text) if body and (quoted or literal_body) else ('unknown', '')
                elif op == '<<<':
                    values = [child for child in children(redirect) if child['type'] != '<<<']
                    stdin_source = (('known', literal_operand(source(values[0], raw),
                                                              state['variables']).replace('\ue000', '$')) if len(values) == 1
                                    else ('unknown', ''))
            redirected = clone(state)
            if stdin_source is not None:
                redirected['stdin_source'] = stdin_source
                redirected['pipeline_input'] = True
            outcome = expand(bodies, [redirected]) if bodies else [(redirected, True)]
            for redirect in redirects:
                rights = children(redirect, 'right')
                operators = [source(child, raw) for child in redirect['children']
                             if child['field'] == 'operator']
                if not rights:
                    rights = [child for child in children(redirect)
                              if child['type'] == 'pipeline']
                if not rights:
                    continue
                if len(rights) != 1:
                    raise ValueError('unknown heredoc continuation')
                right = rights[0]
                if right['type'] == 'pipeline':
                    right_nodes = children(right)
                    if len(right_nodes) != 1:
                        raise ValueError('unknown heredoc pipeline')
                    continuation = redirect_scope(right_nodes[0])
                    parts = continuation['children'] if continuation['type'] == 'list' else []
                    first = next((part for part in parts if part['named']), continuation)
                    tail = [part for part in parts if part['named'] and part is not first]
                    outer = pipeline_operators(right)
                    inner = pipeline_operators(first) if first['type'] == 'pipeline' else []
                    outcome = pipeline_outcomes(bodies + pipeline_stages(first),
                                                redirected, state, outer + inner)
                    if tail:
                        outcome = list_remainder(parts, first, outcome)
                else:
                    for local, _ in outcome:
                        local['stdin_source'] = state['stdin_source']
                        local['pipeline_input'] = state['pipeline_input']
                    op = operators[0] if len(operators) == 1 else None
                    if op not in ('&&', '||'):
                        raise ValueError('unknown heredoc continuation')
                    following = []
                    for local, ok in outcome:
                        if (op == '&&' and ok) or (op == '||' and not ok):
                            following.extend(visit(right, local))
                        else:
                            following.append((local, ok))
                    outcome = distinct(following)
            # The `exec` builtin rebinds the shell's own stdin for later commands.
            effect = exec_stdin_effect(bodies, state) if stdin_source is not None else 'none'
            persistent = (stdin_source if effect == 'persist' else
                          ('unknown', '') if effect == 'unknown' else None)
            for local, _ in outcome:
                local['stdin_source'] = persistent or state['stdin_source']
                local['pipeline_input'] = bool(persistent) or state['pipeline_input']
                local['mentioned_agents'] = state['mentioned_agents']
                if persistent:
                    local['exec_stdin'] = persistent
            return outcome
        if kind == 'negated_command':
            return [(local, not ok) for local, ok in
                    expand(children(node), [clone(state)])]
        if kind in ('subshell', 'subshell_statement', 'command_substitution',
                    'process_substitution'):
            expand(children(node), [clone(state)])
            return [(state, True), (state, False)]
        if kind == 'test_command':
            substitutions(node, state)
            return [(state, True), (state, False)]
        if kind in ('if_statement', 'elif_clause'):
            clauses = [node] + [child for child in children(node)
                                if child['type'] == 'elif_clause']
            pending, outcome = [clone(state)], []
            for clause in clauses:
                conditioned = expand(children(clause, 'condition'), pending)
                passed = [item for item, ok in conditioned if ok]
                pending = [item for item, ok in conditioned if not ok]
                body = [child for child in children(clause)
                        if child['field'] != 'condition'
                        and child['type'] not in ('elif_clause', 'else_clause')]
                if passed:
                    outcome.extend(expand(body, passed))
            alternatives = [child for child in children(node)
                            if child['type'] == 'else_clause']
            if alternatives and pending:
                outcome.extend(expand(children(alternatives[0]), pending))
                pending = []
            return outcome + [(item, False) for item in pending]
        if kind == 'case_statement':
            branch = [(state, False)]  # No pattern may match.
            for child in children(node):
                if child['type'] == 'case_item':
                    branch.extend(visit(child, clone(state)))
                else:
                    substitutions(child, state)
            return branch
        if kind in ('case_item', 'else_clause'):
            body = []
            for child in children(node):
                if child['field'] in ('value', 'pattern'):
                    substitutions(child, state)
                else:
                    body.append(child)
            return expand(body, [clone(state)])
        if kind in ('while_statement', 'until_statement', 'for_statement',
                    'select_statement', 'repeat_statement'):
            is_until = any(child['type'] == 'until' for child in node['children'])
            branch = [(state, True)]
            bodies = []
            conditions = []
            for child in children(node):
                if child['field'] == 'condition':
                    conditions.append(child)
                elif child['field'] in ('count', 'value'):
                    expand([child], [clone(state)])
                elif child['type'] == 'command' and source(child, raw).startswith('do '):
                    if shell_blocked(source(child, raw)[3:], state['base'], expand_alias,
                                     state['variables'], alias_seen, budget, shell or 'zsh',
                                     state['functions'],
                                     inherited_stdin_source=state['stdin_source'],
                                     inherited_cat_resolution_unknown=state['cat_resolution_unknown']):
                        raise ValueError('protected inline repeat')
                else:
                    bodies.append(child)
            if not bodies:
                return branch
            frontier = [clone(state)]
            previous = None
            for _ in range(3):
                tested = expand(conditions, frontier) if conditions else [(item, True) for item in frontier]
                active = [item for item, ok in tested if ok != is_until]
                branch.extend((item, not ok) for item, ok in tested
                              if ok == is_until)
                outcomes = expand(bodies, active)
                branch.extend(outcomes)
                following = [item for item, _ in outcomes]
                frontier = [item for item, _ in
                            distinct((item, True) for item in following)]
                signature = {state_key(item) for item in frontier}
                if signature == previous:
                    break
                previous = signature
            else:
                uncertain = clone(state)
                uncertain['base'] = None
                uncertain['variables'] = {}
                branch.extend(expand(bodies, [uncertain]))
            return branch
        outcome = expand(children(node), [state])
        return outcome or [(state, True)]

    try:
        result = visit(tree, initial)
        if out_states is not None:
            out_states.extend(result)
    except (ValueError, KeyError, TypeError):
        return True
    return False


def blocked(data):
    if not isinstance(data, dict):
        return True
    tool = str(data.get("tool_name", "")).lower().split(".")[-1]
    inp = data.get("tool_input", {})
    if not isinstance(inp, dict):
        return True
    if "tool_name" in data and not isinstance(data["tool_name"], str):
        return True
    cwd = data.get("cwd", inp.get("cwd", "."))
    base = paths(cwd, Path.cwd())[0] if isinstance(cwd, str) else Path.cwd()
    # exec_command runs in `workdir` (relative to the session cwd) when one is given.
    workdir = inp.get("workdir")
    if workdir is not None:
        if not isinstance(workdir, str):
            return True
        base = paths(workdir, base)[0]
    command = inp.get("command", inp.get("cmd"))
    if tool in ("bash", "exec_command") and not isinstance(command, str):
        return True
    if isinstance(command, str) and shell_blocked(command, base, shell=dialect(inp, tool_name=tool)):
        return True
    if tool in ("write", "edit", "multiedit", "notebookedit"):
        path = inp.get("file_path", inp.get("notebook_path"))
        if not isinstance(path, str) or protected_write(path, base):
            return True
    if tool in ("apply_patch", "applypatch") or "patch" in inp:
        patch = inp.get("patch", inp.get("input", ""))
        if not isinstance(patch, str):
            return True
        for path in re.findall(r"^\*\*\* (?:(?:Add|Update|Delete) File|Move to): (.+)$", patch, re.M):
            if protected_write(path, base):
                return True
    return False


try:
    if blocked(json.load(sys.stdin)):
        raise ValueError("protected .agents path")
except Exception as error:
    if isinstance(error, ValueError) and str(error) in (
        'native shell parser unavailable', 'native shell parser failed',
        'no supported shell', 'unsupported shell', 'shell parser time limit exceeded'
    ):
        print('하네스 보호: 셸 파서 패키지를 확인하거나 하네스를 동기화해야 합니다.', file=sys.stderr)
    else:
        print("하네스 보호: 명령 또는 입력을 차단했습니다. 갱신은 보호 필터 동기화(rsync -a --delete + project-profile·reports·work-items·artifacts·exec-plans·product-specs·troubleshooting exclude 또는 H+P 필터)를 사용하십시오. 근거: docs/troubleshooting/2026-08-27-harness-recopy-local-state-loss.md", file=sys.stderr)
    sys.exit(2)
